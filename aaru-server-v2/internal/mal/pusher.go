package mal

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/provider"
	"context"
	"log/slog"
	"math"
	"slices"
	"strconv"
	"time"

	"github.com/google/uuid"
)

// Pusher is SCR-005: sends anime progress to connected MyAnimeList accounts. It reads the
// library's own changes since each connection's cursor, so every write path (a tap, an import, a
// scrobble, an undo, an agent) goes out the same way, and nothing has to remember to call it.
// Deletes are not pushed: removing an anime from Aaru leaves it on MAL.
type Pusher struct {
	Store   *Store
	Connect *ConnectService
	API     *API
	Library *library.Store
	Catalog *catalog.Store
	Log     *slog.Logger
	Now     func() time.Time
}

// Share is one entry's share of a show: its ticks, its episodes when known, whether it is the
// show's first entry, and whether any of its episodes is still to air.
type Share struct {
	Ticks    int
	Total    *int
	IsFirst  bool
	IsAiring bool
}

// Target is one MAL entry an Aaru show stands for. Season nil: an anime that is not a TMDB show,
// so every tick counts.
type Target struct {
	MalID  string
	Season *int
}

func (p *Pusher) now() time.Time {
	if p.Now != nil {
		return p.Now()
	}
	return time.Now()
}

func (p *Pusher) log() *slog.Logger {
	if p.Log != nil {
		return p.Log
	}
	return slog.Default()
}

// RunOnce pushes for every connection with library writes past its cursor. It returns the entries sent.
func (p *Pusher) RunOnce(ctx context.Context) (int, error) {
	due, err := p.Store.PushesDue(ctx)
	if err != nil {
		return 0, err
	}
	sent := 0
	for _, d := range due {
		n, err := p.Push(ctx, d)
		if err != nil {
			if ctx.Err() != nil {
				return sent, ctx.Err()
			}
			// The cursor stays put, so the next pass tries these writes again.
			p.log().Warn("MyAnimeList push failed", "error", err.Error())
			continue
		}
		sent += n
	}
	return sent, nil
}

// Push sends one connection's changes and moves its cursor.
func (p *Pusher) Push(ctx context.Context, due PushDue) (int, error) {
	started := p.now()
	sent, err := p.push(ctx, due, started)
	if pe, ok := provider.AsError(err); ok && pe.Kind == provider.KindUnauthorized {
		return 0, p.Store.MarkRevoked(ctx, due.UserID, started)
	}
	return sent, err
}

func (p *Pusher) push(ctx context.Context, due PushDue, started time.Time) (int, error) {
	token, err := p.Connect.AccessToken(ctx, due.UserID)
	if err != nil || token == nil {
		return 0, err
	}
	sent, err := p.pushWith(ctx, due, *token, started)
	if err != nil {
		return 0, err
	}
	// Writes committing while this ran are read again next time, like the sync token.
	if err := p.Store.AdvanceCursor(ctx, due.UserID, started.Add(-library.SyncOverlap)); err != nil {
		return 0, err
	}
	return sent, nil
}

type plannedShow struct {
	entry   library.Entry
	targets []Target
}

func (p *Pusher) pushWith(ctx context.Context, due PushDue, token string, now time.Time) (int, error) {
	cursor := due.Cursor
	entries, _, err := p.Library.Changes(ctx, due.UserID, &cursor, now)
	if err != nil {
		return 0, err
	}
	var shows []library.Entry
	var tmdbIDs, anilistIDs []string
	for _, e := range entries {
		if e.Title.Type != core.MediaShow {
			continue
		}
		shows = append(shows, e)
		if e.Title.IDs.TMDB != "" {
			tmdbIDs = append(tmdbIDs, e.Title.IDs.TMDB)
		}
		if e.Title.IDs.AniList != "" {
			anilistIDs = append(anilistIDs, e.Title.IDs.AniList)
		}
	}
	if len(shows) == 0 {
		return 0, nil
	}
	byTMDB, err := p.Catalog.MappingsByTMDB(ctx, tmdbIDs)
	if err != nil {
		return 0, err
	}
	byAniList, err := p.Catalog.MappingsByAniList(ctx, anilistIDs)
	if err != nil {
		return 0, err
	}
	tmdbMappings := map[string][]catalog.AnimeMapping{}
	for _, m := range byTMDB {
		key := ""
		if m.TMDB != nil {
			key = *m.TMDB
		}
		tmdbMappings[key] = append(tmdbMappings[key], m)
	}
	anilistMappings := map[string]catalog.AnimeMapping{}
	for _, m := range byAniList {
		if _, ok := anilistMappings[m.AniList]; !ok {
			anilistMappings[m.AniList] = m
		}
	}
	var planned []plannedShow
	for _, e := range shows {
		var forTMDB []catalog.AnimeMapping
		if e.Title.IDs.TMDB != "" {
			forTMDB = tmdbMappings[e.Title.IDs.TMDB]
		}
		var forAniList *catalog.AnimeMapping
		if m, ok := anilistMappings[e.Title.IDs.AniList]; ok && e.Title.IDs.AniList != "" {
			forAniList = &m
		}
		if targets := Targets(e.Title, forTMDB, forAniList); len(targets) > 0 {
			planned = append(planned, plannedShow{entry: e, targets: targets})
		}
	}
	if len(planned) == 0 {
		return 0, nil
	}
	itemIDs := make([]uuid.UUID, len(planned))
	var malIDs []string
	for i, ps := range planned {
		itemIDs[i] = ps.entry.Item.ID
		for _, t := range ps.targets {
			malIDs = append(malIDs, t.MalID)
		}
	}
	ticks, err := p.Library.WatchedOf(ctx, itemIDs)
	if err != nil {
		return 0, err
	}
	states, err := p.Store.EntryStates(ctx, due.UserID, malIDs)
	if err != nil {
		return 0, err
	}
	sent := 0
	for _, ps := range planned {
		episodes, err := p.Catalog.ShowEpisodes(ctx, ps.entry.Title.ID)
		if err != nil {
			return sent, err
		}
		for index, target := range ps.targets {
			inSeason := func(season int) bool {
				if target.Season != nil {
					return *target.Season == season
				}
				return season > 0
			}
			count := 0
			for key := range ticks[ps.entry.Item.ID] {
				if inSeason(key.Season) {
					count++
				}
			}
			total, isAiring := 0, false
			for _, ep := range episodes {
				if !inSeason(ep.Season) {
					continue
				}
				total++
				if ep.AirsAt != nil && ep.AirsAt.After(now) {
					isAiring = true
				}
			}
			share := Share{Ticks: count, IsFirst: index == 0, IsAiring: isAiring}
			if total > 0 {
				share.Total = &total
			}
			state := State(target.MalID, ps.entry.Item, share)
			if state == nil {
				continue
			}
			if known, ok := states[target.MalID]; ok && known == *state {
				continue
			}
			if err := p.API.UpdateListStatus(ctx, target.MalID, *state, token); err != nil {
				if pe, ok := provider.AsError(err); ok && (pe.Kind == provider.KindNotFound || pe.Kind == provider.KindRefused) {
					// MAL does not know this id (a stale mapping): skip it rather than block the rest.
					p.log().Info("MyAnimeList refused an entry", "mal", target.MalID)
					continue
				}
				return sent, err
			}
			if err := p.Store.SaveEntryState(ctx, *state, entryTitle(ps.entry.Title.Title, target.Season), due.UserID); err != nil {
				return sent, err
			}
			sent++
		}
	}
	return sent, nil
}

// entryTitle is the title saved beside a pushed state, as Swift computed it: the show's title
// for an entry with no season, "Title · Season N" for a later season, and none (the known one
// kept) for season 1 (`String??` coalesced to `String?`).
func entryTitle(title string, season *int) *string {
	if season == nil {
		return &title
	}
	if *season > 1 {
		name := title + " · Season " + strconv.Itoa(*season)
		return &name
	}
	return nil
}

// Targets are the MAL entries a show stands for. A TMDB show splits by the anime mapping into one
// entry per season; a season several MAL entries map to (a split cour) is skipped, because Aaru
// cannot tell which of its ticks belong to which. Anything else uses its own MAL id.
func Targets(title core.Title, tmdbMappings []catalog.AnimeMapping, anilistMapping *catalog.AnimeMapping) []Target {
	if title.Type != core.MediaShow {
		return nil
	}
	if len(tmdbMappings) > 0 {
		bySeason := map[int][]string{}
		for _, m := range tmdbMappings {
			if m.MAL == nil {
				continue
			}
			season := 1
			if m.TMDBSeason != nil {
				season = *m.TMDBSeason
			}
			if !slices.Contains(bySeason[season], *m.MAL) {
				bySeason[season] = append(bySeason[season], *m.MAL)
			}
		}
		seasons := make([]int, 0, len(bySeason))
		for s := range bySeason {
			seasons = append(seasons, s)
		}
		slices.Sort(seasons)
		var out []Target
		for _, s := range seasons {
			if ids := bySeason[s]; len(ids) == 1 {
				out = append(out, Target{MalID: ids[0], Season: &s})
			}
		}
		return out
	}
	switch {
	case title.IDs.MAL != "":
		return []Target{{MalID: title.IDs.MAL}}
	case anilistMapping != nil && anilistMapping.MAL != nil:
		return []Target{{MalID: *anilistMapping.MAL}}
	}
	return nil
}

// State is what one MAL entry should say, or nil when Aaru has nothing to say about it (a later
// season nobody started). Only the first entry carries a show's plan or a drop with no ticks, so
// planning a show does not add every season to MAL. A season still airing is never completed: in
// a show finished before that season aired, it goes as one in progress. On hold is Aaru's own
// status (LIB-007), sent as MAL's on hold.
func State(malID string, item core.LibraryItem, share Share) *EntryState {
	ticks, total, isFirst := share.Ticks, share.Total, share.IsFirst
	score := 0
	if item.Rating != nil {
		score = int(math.Round(item.Rating.Value()))
	}
	status := item.Status
	if status == core.StatusFinished && share.IsAiring {
		status = core.StatusInProgress
	}
	state := func(s ListStatus, episodes int) *EntryState {
		return &EntryState{MalID: malID, Status: s, Episodes: episodes, Score: score}
	}
	switch status {
	case core.StatusFinished:
		if total != nil {
			return state(Completed, *total)
		}
		return state(Completed, ticks)
	case core.StatusDropped:
		if ticks > 0 || isFirst {
			return state(Dropped, ticks)
		}
	case core.StatusWishlist:
		if ticks > 0 || isFirst {
			return state(PlanToWatch, ticks)
		}
	case core.StatusInProgress, core.StatusOnHold:
		switch {
		case total != nil && ticks >= *total:
			return state(Completed, *total)
		case ticks > 0 || isFirst:
			if item.Status == core.StatusOnHold {
				return state(OnHold, ticks)
			}
			return state(Watching, ticks)
		}
	}
	return nil
}
