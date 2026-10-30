package gamification

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// LibraryWrite is one journaled library write, as RecordLibraryWrite needs it.
type LibraryWrite struct {
	// Facts from the op and its inverse (NewWriteFacts(kind) then Episodes/Fields/Inserted).
	Facts *WriteFacts
	// Scrobbled: the write came from a player (Stremio or the browser extension, Caller.scrobbled);
	// it earns the scrobble bonus on top.
	Scrobbled bool
	// ActionID is the journal row the write made.
	ActionID uuid.UUID
	UserID   uuid.UUID
	// RequestedZone is reqctx.TimeZone(ctx) read before the transaction (nil: stored, else UTC).
	RequestedZone *time.Location
	// Now defaults to time.Now().
	Now time.Time
}

// RecordLibraryWrite writes the points and the streak day for one live library write, inside the
// library's own transaction (pass the pgx.Tx as db), from the op and the inverse the store
// computed (ARCHITECTURE.md §Gamification; PostgresGamificationStore.recordLibraryWrite).
//
// The library store calls it for every `apply` (with the write's journal kind) and every undo
// (kind "undo", the undone action's inverse as the op and the redo as its inverse), right after
// journaling, so points commit with the write or not at all (GAM-001). After the commit the
// library calls Service.AfterWrite (or AfterUndo for an undo).
func RecordLibraryWrite(ctx context.Context, db sqlc.DBTX, w LibraryWrite) error {
	facts := w.Facts
	if facts == nil || facts.IsEmpty() {
		return nil
	}
	now := w.Now
	if now.IsZero() {
		now = time.Now()
	}
	s := newStore(db)
	items, err := s.itemTitles(ctx, facts.ItemIDs())
	if err != nil {
		return err
	}
	loc, err := s.zone(ctx, w.UserID, w.RequestedZone)
	if err != nil {
		return err
	}
	date := core.LocalDate(now, loc)
	action := w.ActionID
	awards, err := s.tickAwards(ctx, facts, items, w.Scrobbled, &action)
	if err != nil {
		return err
	}
	awards = append(awards, finishAwards(facts, items, w.Scrobbled, &action, date)...)
	if revokes := revokedRoots(facts, items); len(revokes) > 0 {
		if _, err := s.revoke(ctx, revokes, w.UserID); err != nil {
			return err
		}
	}
	if len(awards) > 0 {
		if _, err := s.award(ctx, awards, w.UserID, loc, now); err != nil {
			return err
		}
	}
	for _, a := range awards {
		if a.Kind.MarksStreakDay() {
			return s.markStreakDay(ctx, w.UserID, loc, now)
		}
	}
	return nil
}

type itemTitle struct {
	id  uuid.UUID
	typ core.MediaType
}

func (s store) itemTitles(ctx context.Context, items []uuid.UUID) (map[uuid.UUID]itemTitle, error) {
	rows, err := s.q.GamificationItemTitles(ctx, items)
	if err != nil {
		return nil, fmt.Errorf("item titles: %w", err)
	}
	out := map[uuid.UUID]itemTitle{}
	for _, row := range rows {
		if t := core.MediaType(row.Type); t.Valid() {
			out[row.ItemID] = itemTitle{id: row.TitleID, typ: t}
		}
	}
	return out, nil
}

// tickAwards is an episode each, a scrobble bonus each when a player sent it, and a season bonus
// for every season the ticks completed.
func (s store) tickAwards(ctx context.Context, facts *WriteFacts, items map[uuid.UUID]itemTitle, scrobbled bool, action *uuid.UUID) ([]Award, error) {
	var awards []Award
	for _, item := range facts.order {
		keys, ok := facts.Ticked[item]
		if !ok {
			continue
		}
		title, ok := items[item]
		if !ok {
			continue
		}
		titleID := title.id
		var seasons []int
		seenSeason := map[int]bool{}
		for _, key := range keys {
			awards = append(awards, NewAward(KindEpisode, EpisodeRoot(titleID, key), &titleID, action))
			if scrobbled {
				awards = append(awards, NewAward(KindScrobbleBonus, ScrobbleRoot(titleID, key), &titleID, action))
			}
			if !seenSeason[key.Season] {
				seenSeason[key.Season] = true
				seasons = append(seasons, key.Season)
			}
		}
		for _, season := range seasons {
			if season <= 0 {
				continue
			}
			row, err := s.q.GamificationSeasonComplete(ctx, sqlc.GamificationSeasonCompleteParams{
				ItemID: item, TitleID: titleID, Season: int32(season),
			})
			if err != nil {
				return nil, fmt.Errorf("season complete: %w", err)
			}
			if row.Aired > 0 && row.Missing == 0 {
				awards = append(awards, NewAward(KindSeasonBonus, SeasonRoot(titleID, season), &titleID, action))
			}
		}
	}
	return awards, nil
}

func finishAwards(facts *WriteFacts, items map[uuid.UUID]itemTitle, scrobbled bool, action *uuid.UUID, date string) []Award {
	var awards []Award
	for _, item := range facts.order {
		if !facts.Finished[item] {
			continue
		}
		title, ok := items[item]
		if !ok {
			continue
		}
		kind, ok := finishKind(title.typ)
		if !ok {
			continue
		}
		titleID := title.id
		awards = append(awards, NewAward(kind, FinishRoot(titleID), &titleID, action))
		if scrobbled {
			awards = append(awards, NewAward(KindScrobbleBonus, ScrobbleFinishRoot(titleID), &titleID, action))
		}
	}
	for _, item := range facts.order {
		if !facts.BookForward[item] {
			continue
		}
		title, ok := items[item]
		if !ok || (title.typ != core.MediaBook && title.typ != core.MediaManga) {
			continue
		}
		titleID := title.id
		awards = append(awards, NewAward(KindBookProgress, BookDayRoot(titleID, date), &titleID, action))
	}
	return awards
}

// revokedRoots are unticked episodes and their seasons, and finishes taken back.
func revokedRoots(facts *WriteFacts, items map[uuid.UUID]itemTitle) []string {
	var revokes []string
	for _, item := range facts.order {
		keys, ok := facts.Unticked[item]
		if !ok {
			continue
		}
		title, ok := items[item]
		if !ok {
			continue
		}
		seen := map[int]bool{}
		var seasons []string
		for _, key := range keys {
			revokes = append(revokes, EpisodeRoot(title.id, key), ScrobbleRoot(title.id, key))
			if !seen[key.Season] {
				seen[key.Season] = true
				seasons = append(seasons, SeasonRoot(title.id, key.Season))
			}
		}
		revokes = append(revokes, seasons...)
	}
	for _, item := range facts.order {
		if !facts.Unfinished[item] {
			continue
		}
		if title, ok := items[item]; ok {
			revokes = append(revokes, FinishRoot(title.id), ScrobbleFinishRoot(title.id))
		}
	}
	return revokes
}
