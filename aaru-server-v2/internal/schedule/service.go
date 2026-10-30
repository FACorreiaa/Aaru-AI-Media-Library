// Package schedule is the calendar (CAL-001), Watching (APP-018) and Up Next (UPN-001, UPN-002):
// derived reads over the library with no table of their own. None calls a provider (CAL-004):
// episodes are loaded by the catalog refresher, and the calendar reports how many shows it is
// still waiting on. It also runs the ten-minute airing notifier loop (AiringNotifierService).
package schedule

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"
)

const (
	// MaxCalendarSpan is six weeks: a month view's full grid, Monday before the 1st to Sunday after the last.
	MaxCalendarSpan = 42 * 24 * time.Hour
	// StalledAfter is how long an untouched in-progress item takes to become unfinished business (UPN-002).
	StalledAfter = 30 * 24 * time.Hour
	// UnfinishedLimit bounds Up Next's unfinished row.
	UnfinishedLimit = 20
	// WatchingLimit only bounds a pathological library: Watching reads every title in progress.
	WatchingLimit = 5000
)

// Service is ScheduleService.
type Service struct {
	pool  *pgxpool.Pool
	q     *sqlc.Queries
	store *catalog.Store
	// Now is the clock; tests pin it.
	Now func() time.Time
}

// New builds the service over the pool.
func New(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool, q: sqlc.New(pool), store: catalog.NewStore(pool), Now: time.Now}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Calendar is the episodes of the user's tracked shows (wishlist or in progress) airing in [from, until).
func (s *Service) Calendar(ctx context.Context, userID uuid.UUID, from, until time.Time) ([]CalendarEntry, error) {
	if !until.After(from) || until.Sub(from) > MaxCalendarSpan {
		const message = "The range must be positive and at most 42 days."
		return nil, apperr.New(http.StatusUnprocessableEntity, "validation_failed", message).
			WithDetails(map[string]string{"to": message})
	}
	rows, err := s.q.ScheduleCalendar(ctx, sqlc.ScheduleCalendarParams{UserID: userID, FromTime: &from, UntilTime: &until})
	if err != nil {
		return nil, fmt.Errorf("calendar: %w", err)
	}
	out := make([]CalendarEntry, 0, len(rows))
	for _, row := range rows {
		title, ok := scheduleTitle(row.Title)
		key, err := core.NewEpisodeKey(int(row.Season), int(row.Episode))
		if !ok || err != nil || row.AirsAt == nil {
			continue
		}
		kind := KindRegular
		switch row.Episode {
		case 1:
			kind = KindPremiere
		case row.SeasonLast:
			kind = KindFinale
		}
		out = append(out, CalendarEntry{
			LibraryItemID: row.ItemID, Title: title, Key: key, EpisodeName: row.Name, AirsAt: *row.AirsAt,
			RuntimeMinutes: intPtr(row.RuntimeMinutes), Watched: row.Watched, Kind: kind,
			AirTimeKnown: row.AirsAtExact, EpisodeOverview: row.Overview, StillURL: row.StillUrl,
		})
	}
	return out, nil
}

// PendingShows is how many tracked shows the refresher has not tried yet: the calendar may still grow.
// A show the provider does not know drops out after its first attempt, so a waiting client stops.
func (s *Service) PendingShows(ctx context.Context, userID uuid.UUID) (int, error) {
	n, err := s.q.SchedulePendingShowCount(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("pending shows: %w", err)
	}
	return int(n), nil
}

// UpNext is everything the home screen's rows need, in one answer.
func (s *Service) UpNext(ctx context.Context, userID uuid.UUID) (UpNext, error) {
	now := s.now()
	var out UpNext
	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) {
		out.ContinueWatching, err = s.continueWatching(ctx, userID, now, 50)
		return err
	})
	g.Go(func() (err error) {
		out.StartWatching, err = s.startWatching(ctx, userID, 20)
		return err
	})
	g.Go(func() (err error) {
		out.Counts, err = s.libraryCounts(ctx, userID)
		return err
	})
	g.Go(func() (err error) {
		out.Unfinished, err = s.unfinished(ctx, userID, now.Add(-StalledAfter), now, UnfinishedLimit)
		return err
	})
	if err := g.Wait(); err != nil {
		return UpNext{}, err
	}
	return out, nil
}

// Watching is films and shows in progress, newest change first (APP-018). Backlog anime are kept;
// clients split them out by the entry's inBacklog.
func (s *Service) Watching(ctx context.Context, userID uuid.UUID) ([]WatchingRow, error) {
	now := s.now()
	status := core.StatusInProgress
	all, err := ReadEntries(ctx, s.pool, userID, EntryFilter{Status: &status}, WatchingLimit, now)
	if err != nil {
		return nil, err
	}
	entries := make([]LibraryEntry, 0, len(all))
	var shows []uuid.UUID
	for _, e := range all {
		switch e.Title.Type {
		case core.MediaMovie:
			entries = append(entries, e)
		case core.MediaShow:
			entries = append(entries, e)
			shows = append(shows, e.Title.ID)
		}
	}
	var (
		airing     map[uuid.UUID]catalog.TitleAiring
		continuing []ContinueEntry
	)
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) {
		airing, err = s.store.Airing(gctx, shows, now)
		return err
	})
	g.Go(func() (err error) {
		continuing, err = s.continueWatching(gctx, userID, now, max(len(shows), 1))
		return err
	})
	if err := g.Wait(); err != nil {
		return nil, err
	}
	next := make(map[uuid.UUID]ContinueEntry, len(continuing))
	for _, c := range continuing {
		if _, seen := next[c.LibraryItemID]; !seen {
			next[c.LibraryItemID] = c
		}
	}
	out := make([]WatchingRow, 0, len(entries))
	for _, e := range entries {
		row := WatchingRow{Entry: e}
		if a, ok := airing[e.Title.ID]; ok {
			row.Airing = &a
		}
		if c, ok := next[e.Item.ID]; ok {
			row.Next = &c
		}
		out = append(out, row)
	}
	return out, nil
}

func (s *Service) continueWatching(ctx context.Context, userID uuid.UUID, now time.Time, limit int) ([]ContinueEntry, error) {
	rows, err := s.q.ScheduleContinueWatching(ctx, sqlc.ScheduleContinueWatchingParams{
		Now: &now, UserID: userID, MaxRows: int32(min(limit, WatchingLimit)), //nolint:gosec // bounded above
	})
	if err != nil {
		return nil, fmt.Errorf("continue watching: %w", err)
	}
	out := make([]ContinueEntry, 0, len(rows))
	for _, row := range rows {
		title, ok := scheduleTitle(row.Title)
		next, err := core.NewEpisodeKey(int(row.NextSeason), int(row.NextEpisode))
		if !ok || err != nil {
			continue
		}
		out = append(out, ContinueEntry{
			LibraryItemID: row.ItemID, Title: title, Next: next, NextName: row.NextName,
			NextRuntimeMinutes: intPtr(row.NextRuntime), RemainingCount: int(row.RemainingCount),
			RemainingMinutes: int(row.RemainingMinutes), IsFinale: row.IsFinale,
		})
	}
	return out, nil
}

func (s *Service) startWatching(ctx context.Context, userID uuid.UUID, limit int32) ([]StartEntry, error) {
	rows, err := s.q.ScheduleStartWatching(ctx, sqlc.ScheduleStartWatchingParams{UserID: userID, MaxRows: limit})
	if err != nil {
		return nil, fmt.Errorf("start watching: %w", err)
	}
	out := make([]StartEntry, 0, len(rows))
	for _, row := range rows {
		if title, ok := scheduleTitle(row.Title); ok {
			out = append(out, StartEntry{LibraryItemID: row.ItemID, Title: title, RuntimeMinutes: intPtr(row.Title.RuntimeMinutes)})
		}
	}
	return out, nil
}

func (s *Service) libraryCounts(ctx context.Context, userID uuid.UUID) (LibraryCounts, error) {
	rows, err := s.q.ScheduleLibraryCounts(ctx, userID)
	if err != nil {
		return LibraryCounts{}, fmt.Errorf("library counts: %w", err)
	}
	var c LibraryCounts
	for _, row := range rows {
		n := int(row.Count)
		switch core.LibraryStatus(row.Status) {
		case core.StatusWishlist:
			c.Wishlist = n
		case core.StatusInProgress:
			c.InProgress = n
		case core.StatusOnHold:
			c.OnHold = n
		case core.StatusFinished:
			c.Finished = n
		case core.StatusDropped:
			c.Dropped = n
		}
	}
	return c, nil
}

// scheduleTitle is the title as PostgresScheduleStore's TitleColumns read it: no byline, length
// counts or MusicBrainz id. Schedule rows are shows and films, and Swift left those out.
func scheduleTitle(row sqlc.Title) (core.Title, bool) {
	t, ok := catalog.TitleFromRow(row)
	if !ok {
		return core.Title{}, false
	}
	t.Byline, t.PageCount, t.ChapterCount, t.VolumeCount = nil, nil, nil, nil
	t.IDs.MusicBrainz = ""
	return t, true
}
