package library

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"context"
	"encoding/base64"
	"errors"
	"log/slog"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// SyncOverlap is how far a sync token lags the server clock, so a write whose transaction
// started before the sync and committed after it is still delivered next time.
const SyncOverlap = 5 * time.Second

// Clearable names a field a patch empties (JSON cannot tell "absent" from "null").
type Clearable string

// The clearable fields.
const (
	ClearRating        Clearable = "rating"
	ClearNotes         Clearable = "notes"
	ClearBookProgress  Clearable = "bookProgress"
	ClearMangaProgress Clearable = "mangaProgress"
)

// ItemPatch is a partial update to a library item. Absent fields are left alone; Clear names
// fields to empty.
type ItemPatch struct {
	Status       *core.LibraryStatus
	Rating       *float64
	Notes        *string
	IsOwned      *bool
	BookPage     *int
	BookPercent  *float64
	MangaChapter *int
	MangaVolume  *int
	Clear        map[Clearable]bool
}

// ShowContext is what a show's progress write needs: the item, its episodes, and the show's status.
type ShowContext struct {
	Entry    Entry
	Episodes []catalog.Episode
	Status   *catalog.TitleStatus
}

// ShowWatched is PROG-005's result: the item after the whole show was marked watched, the action
// that did it (nil when nothing changed), and how many episodes it ticked.
type ShowWatched struct {
	Entry    Entry
	Action   *ActionRecord
	Episodes int
}

// ProgressWrite is an episode or season tick: the item after it, and the action Undo takes back.
type ProgressWrite struct {
	Entry  Entry
	Action ActionRecord
}

// ItemWrite is a PATCH: the item after it, and the action Undo takes back (nil when nothing changed).
type ItemWrite struct {
	Entry  Entry
	Action *ActionRecord
}

// SyncResult is one sync answer: what changed, what was deleted, and the token for next time.
type SyncResult struct {
	Entries []Entry
	Deleted []uuid.UUID
	Token   string
}

// Service is the library rules (LibraryService, M4, M5). Every write becomes a journaled Op.
type Service struct {
	Store        *Store
	Catalog      *catalog.Kit
	Gamification *gamification.Service
	Log          *slog.Logger
	// Now defaults to time.Now.
	Now func() time.Time
}

// NewService builds the library service.
func NewService(store *Store, kit *catalog.Kit, game *gamification.Service, log *slog.Logger) *Service {
	return &Service{Store: store, Catalog: kit, Gamification: game, Log: log, Now: time.Now}
}

func (s *Service) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

func (s *Service) log() *slog.Logger {
	if s.Log == nil {
		return slog.Default()
	}
	return s.Log
}

func validation(field, message string) *apperr.Error { return apperr.Validation(field, message) }

// MARK: Items (LIB-001…003)

// Add adds a title, or returns the existing item: posting the same ref twice is idempotent,
// never a duplicate and never a 500 from the unique index.
func (s *Service) Add(ctx context.Context, ref core.MediaRef, status *core.LibraryStatus, user uuid.UUID, caller Caller) (Entry, error) {
	title, err := s.Catalog.Resolver().Resolve(ctx, ref, nil)
	if err != nil {
		return Entry{}, err
	}
	existing, err := s.Store.EntryForTitle(ctx, user, title.ID, s.now())
	if err != nil {
		return Entry{}, err
	}
	if existing != nil {
		return s.Entry(ctx, existing.Item.ID, user)
	}
	write := s.PrepareAdd(title, status, caller)
	if title.Type == core.MediaShow && status != nil && *status == core.StatusFinished {
		// PROG-005: added as watched means every aired episode, in the same one action. An insert
		// writes its ticks undated, like the whole-show mark.
		detail, err := s.Catalog.Service.Detail(ctx, title.ID)
		if err != nil {
			return Entry{}, err
		}
		snapshot := *write.Op.Snapshot
		snapshot.Watched = nil
		for _, ep := range detail.Episodes {
			if ep.Season > 0 && HasAired(ep, detail.Status, s.now()) {
				if k, err := core.NewEpisodeKey(ep.Season, ep.Episode); err == nil {
					snapshot.Watched = append(snapshot.Watched, k)
				}
			}
		}
		if len(snapshot.Watched) == 0 || !endedOrCanceled(detail.Status) {
			if len(snapshot.Watched) == 0 {
				snapshot.Fields.Status = core.StatusWishlist
			} else {
				snapshot.Fields.Status = core.StatusInProgress
			}
			snapshot.Fields.FinishedAt = nil
			byHand := false
			snapshot.Fields.StatusByHand = &byHand
		}
		write.Op = InsertItem(snapshot)
		write.Episodes = len(snapshot.Watched)
	}
	if _, err := s.Commit(ctx, write, user, caller); err != nil {
		var conflict *StoreConflict
		if !errors.As(err, &conflict) {
			return Entry{}, err
		}
		winner, err := s.Store.EntryForTitle(ctx, user, title.ID, s.now())
		if err != nil {
			return Entry{}, err
		}
		if winner == nil {
			return Entry{}, apperr.NotFound()
		}
		return s.Entry(ctx, winner.Item.ID, user)
	}
	if title.Type == core.MediaShow {
		// Fetch episodes now so the calendar and Up Next have them. Best effort: a provider outage
		// must not fail the add; the calendar retries.
		if _, err := s.Catalog.Service.Detail(ctx, title.ID); err != nil {
			s.log().DebugContext(ctx, "episodes after add", "title", title.ID, "error", err)
		}
	}
	return s.Entry(ctx, write.ItemID, user)
}

// Entry is the user's item. Another user's item is 404, never 403: do not confirm it exists.
func (s *Service) Entry(ctx context.Context, id, user uuid.UUID) (Entry, error) {
	e, err := s.Store.Entry(ctx, id, user, s.now())
	if err != nil {
		return Entry{}, err
	}
	if e == nil {
		return Entry{}, apperr.NotFound()
	}
	return *e, nil
}

// ItemForTitle is the user's entry for a title, or nil.
func (s *Service) ItemForTitle(ctx context.Context, user, titleID uuid.UUID) (*Entry, error) {
	return s.Store.EntryForTitle(ctx, user, titleID, s.now())
}

// List is one page of the library under a filter, and the next page's cursor token (nil on the
// last). limit is clamped to 1…200.
func (s *Service) List(ctx context.Context, user uuid.UUID, filter Filter, cursor *string, limit int) ([]Entry, *string, error) {
	var after *Cursor
	if cursor != nil {
		parsed, ok := ParseCursor(*cursor)
		if !ok {
			return nil, nil, apperr.BadRequest("That cursor is not valid.")
		}
		after = &parsed
	}
	entries, next, err := s.Store.Entries(ctx, user, filter, after, max(1, min(limit, 200)), s.now())
	if err != nil {
		return nil, nil, err
	}
	if next == nil {
		return entries, nil, nil
	}
	token := next.Token()
	return entries, &token, nil
}

// Patch applies a patch and returns the item after it.
func (s *Service) Patch(ctx context.Context, id, user uuid.UUID, patch ItemPatch, caller Caller) (Entry, error) {
	w, err := s.PatchWrite(ctx, id, user, patch, caller)
	return w.Entry, err
}

// PatchWrite is Patch with the action it made, so the caller can offer Undo.
func (s *Service) PatchWrite(ctx context.Context, id, user uuid.UUID, patch ItemPatch, caller Caller) (ItemWrite, error) {
	current, err := s.Entry(ctx, id, user)
	if err != nil {
		return ItemWrite{}, err
	}
	// PROG-005: a show set to watched by hand is the whole show watched.
	wholeShow := current.Title.Type == core.MediaShow && patch.Status != nil && *patch.Status == core.StatusFinished &&
		current.Item.Status != core.StatusFinished
	var write *PreparedWrite
	if wholeShow {
		show, err := s.ShowContext(ctx, id, user)
		if err != nil {
			return ItemWrite{}, err
		}
		write, err = s.PrepareShowWatched(ctx, show, patch, caller)
		if err != nil {
			return ItemWrite{}, err
		}
	} else {
		write, err = s.PreparePatch(current, patch, caller)
		if err != nil {
			return ItemWrite{}, err
		}
	}
	if write == nil {
		return ItemWrite{Entry: current}, nil
	}
	action, err := s.Commit(ctx, *write, user, caller)
	if err != nil {
		return ItemWrite{}, err
	}
	entry, err := s.Entry(ctx, id, user)
	if err != nil {
		return ItemWrite{}, err
	}
	return ItemWrite{Entry: entry, Action: &action}, nil
}

// MarkShowWatched (PROG-005) ticks every aired episode of a show as one undoable action. The
// action is nil when there was nothing left to tick.
func (s *Service) MarkShowWatched(ctx context.Context, id, user uuid.UUID, caller Caller) (ShowWatched, error) {
	show, err := s.ShowContext(ctx, id, user)
	if err != nil {
		return ShowWatched{}, err
	}
	write, err := s.PrepareShowWatched(ctx, show, ItemPatch{}, caller)
	if err != nil {
		return ShowWatched{}, err
	}
	if write == nil {
		return ShowWatched{Entry: show.Entry}, nil
	}
	action, err := s.Commit(ctx, *write, user, caller)
	if err != nil {
		return ShowWatched{}, err
	}
	entry, err := s.Entry(ctx, id, user)
	if err != nil {
		return ShowWatched{}, err
	}
	return ShowWatched{Entry: entry, Action: &action, Episodes: write.Episodes}, nil
}

// Delete removes an item, as one undoable action.
func (s *Service) Delete(ctx context.Context, id, user uuid.UUID, caller Caller) error {
	current, err := s.Entry(ctx, id, user)
	if err != nil {
		return err
	}
	_, err = s.Commit(ctx, s.PrepareDelete(current), user, caller)
	return err
}

// MARK: Sync (LIB-004)

// Sync is everything changed since the token (everything without one), what was deleted, and
// the token for next time.
func (s *Service) Sync(ctx context.Context, user uuid.UUID, token *string) (SyncResult, error) {
	var since *time.Time
	if token != nil {
		micros, ok := parseSyncToken(*token)
		if !ok {
			return SyncResult{}, apperr.BadRequest("That sync token is not valid.")
		}
		t := time.UnixMicro(micros).UTC()
		since = &t
	}
	now := s.now()
	next := now.Add(-SyncOverlap)
	entries, deleted, err := s.Store.Changes(ctx, user, since, now)
	if err != nil {
		return SyncResult{}, err
	}
	nextToken := base64.StdEncoding.EncodeToString([]byte(strconv.FormatInt(next.UnixMicro(), 10)))
	return SyncResult{Entries: entries, Deleted: deleted, Token: nextToken}, nil
}

func parseSyncToken(token string) (int64, bool) {
	data, err := base64.StdEncoding.DecodeString(token)
	if err != nil || !utf8.Valid(data) {
		return 0, false
	}
	micros, err := strconv.ParseInt(string(data), 10, 64)
	return micros, err == nil
}

// MARK: Progress (PROG-001…004)

// SetEpisode ticks or unticks one episode, as one action.
func (s *Service) SetEpisode(ctx context.Context, id, user uuid.UUID, key core.EpisodeKey, watched bool, caller Caller) (ProgressWrite, error) {
	show, err := s.ShowContext(ctx, id, user)
	if err != nil {
		return ProgressWrite{}, err
	}
	known := false
	for _, ep := range show.Episodes {
		if ep.Season == key.Season && ep.Episode == key.Episode {
			known = true
			break
		}
	}
	if !known {
		return ProgressWrite{}, &core.ValidationError{Kind: core.InvalidEpisodeNumber, Season: key.Season, Episode: key.Episode}
	}
	verb := "unwatched"
	var watch, unwatch []core.EpisodeKey
	if watched {
		verb = "watched"
		watch = []core.EpisodeKey{key}
	} else {
		unwatch = []core.EpisodeKey{key}
	}
	write, err := s.PrepareProgress(ctx, watch, unwatch, show, nil,
		"episode", "Marked "+key.String()+" of "+show.Entry.Title.Title+" "+verb)
	if err != nil {
		return ProgressWrite{}, err
	}
	return s.commitProgress(ctx, write, id, user, caller)
}

// SetEpisodes ticks or unticks several episodes of one show as one action, for outside callers
// (Stremio's player and library events). Episodes the show does not have are skipped, and
// episodes already in the asked state are left alone; with nothing left to change there is no
// write and no journal row, so a repeated event is a no-op (nil).
func (s *Service) SetEpisodes(ctx context.Context, id, user uuid.UUID, keys []core.EpisodeKey, watched bool, caller Caller) (*Entry, error) {
	show, err := s.ShowContext(ctx, id, user)
	if err != nil {
		return nil, err
	}
	write, err := s.PrepareEpisodes(ctx, show, keys, watched)
	if err != nil || write == nil {
		return nil, err
	}
	if _, err := s.Commit(ctx, *write, user, caller); err != nil {
		return nil, err
	}
	entry, err := s.Entry(ctx, id, user)
	if err != nil {
		return nil, err
	}
	return &entry, nil
}

// MarkSeasonWatched marks every aired episode of a season watched in one action; unaired ones
// are left alone.
func (s *Service) MarkSeasonWatched(ctx context.Context, id, user uuid.UUID, season int, caller Caller) (ProgressWrite, error) {
	show, err := s.ShowContext(ctx, id, user)
	if err != nil {
		return ProgressWrite{}, err
	}
	write, err := s.PrepareSeason(ctx, show, season)
	if err != nil {
		return ProgressWrite{}, err
	}
	return s.commitProgress(ctx, write, id, user, caller)
}

func (s *Service) commitProgress(ctx context.Context, write PreparedWrite, id, user uuid.UUID, caller Caller) (ProgressWrite, error) {
	action, err := s.Commit(ctx, write, user, caller)
	if err != nil {
		return ProgressWrite{}, err
	}
	entry, err := s.Entry(ctx, id, user)
	if err != nil {
		return ProgressWrite{}, err
	}
	return ProgressWrite{Entry: entry, Action: action}, nil
}

// ShowContext is the item, its episodes and the show's status. Only shows have episodes (422).
// It hydrates episodes on first use (CAT-006), so a tick never races an empty list.
func (s *Service) ShowContext(ctx context.Context, id, user uuid.UUID) (ShowContext, error) {
	current, err := s.Entry(ctx, id, user)
	if err != nil {
		return ShowContext{}, err
	}
	if current.Title.Type != core.MediaShow {
		return ShowContext{}, validation("episode", "Only shows have episodes.")
	}
	detail, err := s.Catalog.Service.Detail(ctx, current.Title.ID)
	if err != nil {
		return ShowContext{}, err
	}
	return ShowContext{Entry: current, Episodes: detail.Episodes, Status: detail.Status}, nil
}

// Actions are the user's newest journal rows.
func (s *Service) Actions(ctx context.Context, user uuid.UUID, limit int) ([]ActionRecord, error) {
	return s.Store.Actions(ctx, user, limit)
}

// Undo takes an action back as a new `undo` action, then lets gamification take back what it earned.
func (s *Service) Undo(ctx context.Context, actionID, user uuid.UUID) (ActionRecord, error) {
	undo, err := s.Store.Undo(ctx, actionID, user)
	if err != nil {
		return ActionRecord{}, err
	}
	if s.Gamification != nil {
		s.Gamification.AfterUndo(ctx, user, actionID, undo.ID)
	}
	return undo, nil
}

// MARK: Field validation and journal wording for patches

// applyBookProgress (PROG-004): page or percent, never both; each validated as BookProgress.
func applyBookProgress(patch ItemPatch, fields *ItemFields, mediaType core.MediaType) error {
	if patch.BookPage == nil && patch.BookPercent == nil && !patch.Clear[ClearBookProgress] {
		return nil
	}
	if mediaType != core.MediaBook {
		return validation("progress", "Only books have page progress.")
	}
	if patch.BookPage != nil && patch.BookPercent != nil {
		return validation("progress", "Send a page or a percent, not both.")
	}
	if patch.Clear[ClearBookProgress] {
		fields.BookPage, fields.BookPercent = nil, nil
	}
	if patch.BookPage != nil {
		if _, err := core.NewBookProgress(patch.BookPage, nil); err != nil {
			return err
		}
		page := *patch.BookPage
		fields.BookPage, fields.BookPercent = &page, nil
	}
	if patch.BookPercent != nil {
		if _, err := core.NewBookProgress(nil, patch.BookPercent); err != nil {
			return err
		}
		percent := *patch.BookPercent
		fields.BookPercent, fields.BookPage = &percent, nil
	}
	return nil
}

// applyMangaProgress (MNG-001): a chapter, a volume, or both; each validated as MangaProgress.
func applyMangaProgress(patch ItemPatch, fields *ItemFields, mediaType core.MediaType) error {
	if patch.MangaChapter == nil && patch.MangaVolume == nil && !patch.Clear[ClearMangaProgress] {
		return nil
	}
	if mediaType != core.MediaManga {
		return validation("progress", "Only manga have chapter progress.")
	}
	if patch.Clear[ClearMangaProgress] {
		fields.MangaChapter, fields.MangaVolume = nil, nil
	}
	if _, err := core.NewMangaProgress(patch.MangaChapter, patch.MangaVolume); err != nil {
		return err
	}
	if patch.MangaChapter != nil {
		v := *patch.MangaChapter
		fields.MangaChapter = &v
	}
	if patch.MangaVolume != nil {
		v := *patch.MangaVolume
		fields.MangaVolume = &v
	}
	return nil
}

// UpdateSummary is the journal wording for a patch.
func UpdateSummary(current Entry, fields ItemFields) string {
	name := current.Title.Title
	before := current.Fields()
	switch {
	case fields.Status != before.Status:
		return "Moved " + name + " to " + StatusLabel(fields.Status, current.Title.Type)
	case !eqPtr(fields.Rating, before.Rating):
		if fields.Rating == nil {
			return "Cleared the rating on " + name
		}
		return "Rated " + name + " " + core.Rating(*fields.Rating).String()
	case fields.IsOwned != before.IsOwned:
		if fields.IsOwned {
			return "Marked " + name + " owned"
		}
		return "Marked " + name + " not owned"
	case fields.MangaChapter != nil && !eqPtr(fields.MangaChapter, before.MangaChapter):
		return "Read " + name + " to chapter " + strconv.Itoa(*fields.MangaChapter)
	case fields.MangaVolume != nil && !eqPtr(fields.MangaVolume, before.MangaVolume):
		return "Read " + name + " to volume " + strconv.Itoa(*fields.MangaVolume)
	}
	return "Updated " + name
}
