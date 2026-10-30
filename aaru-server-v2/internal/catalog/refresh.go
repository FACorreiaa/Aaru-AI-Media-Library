package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"log/slog"
	"sync"
	"time"
)

// Refresher pacing.
const (
	// RefreshConcurrency is shows loaded at once within a pass. The providers are paced.
	RefreshConcurrency = 3
	// RefreshRetryAfter: a show whose refresh was attempted this recently is skipped.
	RefreshRetryAfter = time.Hour
	// GenresRetryAfter: a title the provider gave no genres is asked again after a week.
	GenresRetryAfter = 7 * 24 * time.Hour
	// DefaultRefreshLimit is shows, titles and books per pass.
	DefaultRefreshLimit = 40
)

// Refresher keeps tracked shows' episodes current (JOB-001's second kind). The
// hydration timestamps are the queue: each pass loads shows nobody has loaded yet
// (imports, a provider outage at add time), then shows past their CAT-006 window.
// Title detail still hydrates on read; the calendar and Up Next never do (CAL-004),
// so this is how an import's shows arrive. Each pass also fills genres for titles
// stored before CAT-018, and page counts for books (APP-017).
type Refresher struct {
	Store   *Store
	Catalog *Service
	// PassLimit is shows per pass. Each costs one TMDB call per season, so this stays
	// well inside TMDB's limit while user traffic shares it.
	PassLimit int
	// GenreLimit is titles per pass whose genres are filled; one provider call each.
	GenreLimit int
	// PageCountLimit is books per pass whose page count is filled; one Open Library read each.
	PageCountLimit int
	// Now defaults to time.Now.
	Now func() time.Time
}

// NewRefresher builds a refresher with the default limits.
func NewRefresher(store *Store, catalog *Service) *Refresher {
	return &Refresher{
		Store: store, Catalog: catalog, PassLimit: DefaultRefreshLimit, GenreLimit: DefaultRefreshLimit,
		PageCountLimit: DefaultRefreshLimit, Now: time.Now,
	}
}

func (r *Refresher) now() time.Time {
	if r.Now == nil {
		return time.Now()
	}
	return r.Now()
}

// RunOnce refreshes one batch and returns how many shows were attempted.
func (r *Refresher) RunOnce(ctx context.Context) (int, error) {
	now := r.now()
	due, err := r.Store.StaleTrackedShows(ctx, now, now.Add(-RefreshRetryAfter), r.PassLimit)
	if err != nil {
		return 0, err
	}
	sem := make(chan struct{}, RefreshConcurrency)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var firstErr error
	for _, id := range due {
		if ctx.Err() != nil {
			break
		}
		sem <- struct{}{}
		wg.Go(func() {
			defer func() { <-sem }()
			if ctx.Err() != nil {
				return
			}
			// Stamped first: a show the provider no longer knows would otherwise come back every pass.
			if err := r.Store.MarkEpisodesAttempted(ctx, id, now); err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
				return
			}
			_, _ = r.Catalog.Detail(ctx, id)
		})
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return 0, err
	}
	if firstErr != nil {
		return 0, firstErr
	}
	return len(due), nil
}

// FillGenres is the CAT-018 backfill: one provider read per title missing genres;
// every attempt is stamped. Returns how many titles were attempted.
func (r *Refresher) FillGenres(ctx context.Context) (int, error) {
	now := r.now()
	resolver := NewResolver(r.Store, r.Catalog.Providers)
	due, err := r.Store.TitlesMissingGenres(ctx, now.Add(-GenresRetryAfter), r.GenreLimit)
	if err != nil {
		return 0, err
	}
	for _, title := range due {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		genres, _ := resolver.Genres(ctx, title)
		// A shutdown mid-call is not "no genres": leave the title unstamped for the next pass.
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		if err := r.Store.FillGenres(ctx, title.ID, nonNil(genres), now); err != nil {
			return 0, err
		}
	}
	return len(due), nil
}

// FillPageCounts is the APP-017 backfill: a page count for shelved books stored
// before Open Library's was kept, in-progress books first. Every attempt is stamped;
// one without a count is asked again weekly.
func (r *Refresher) FillPageCounts(ctx context.Context) (int, error) {
	now := r.now()
	due, err := r.Store.BooksMissingPageCount(ctx, now.Add(-GenresRetryAfter), r.PageCountLimit)
	if err != nil {
		return 0, err
	}
	for _, book := range due {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		var pages *int
		if found, err := r.Catalog.Providers.OpenLibrary.Hydrate(ctx, book.IDs, core.MediaBook); err == nil && found != nil {
			pages = found.Hit.PageCount
		}
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		if err := r.Store.FillPageCount(ctx, book.ID, pages, now); err != nil {
			return 0, err
		}
	}
	return len(due), nil
}

// RefreshWorker runs the refresher in the API process: every minute, and again
// after a short pause while a full pass says more shows are waiting (an import's
// backlog clears in minutes).
type RefreshWorker struct {
	Refresher       *Refresher
	Log             *slog.Logger
	Interval        time.Duration
	BacklogInterval time.Duration
}

// NewRefreshWorker is the worker with the 60 s / 5 s pauses.
func NewRefreshWorker(refresher *Refresher, log *slog.Logger) *RefreshWorker {
	return &RefreshWorker{Refresher: refresher, Log: log, Interval: 60 * time.Second, BacklogInterval: 5 * time.Second}
}

// Name names the worker in logs.
func (w *RefreshWorker) Name() string { return "catalog-refresh" }

// Run loops until ctx is cancelled.
func (w *RefreshWorker) Run(ctx context.Context) error {
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for ctx.Err() == nil {
		pause := w.Interval
		if err := w.pass(ctx, log, &pause); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			log.Error("Show refresh pass failed", "error", err.Error())
		}
		timer := time.NewTimer(pause)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-timer.C:
		}
	}
	return nil
}

func (w *RefreshWorker) pass(ctx context.Context, log *slog.Logger, pause *time.Duration) error {
	attempted, err := w.Refresher.RunOnce(ctx)
	if err != nil {
		return err
	}
	if attempted >= w.Refresher.PassLimit {
		*pause = w.BacklogInterval
	}
	if attempted > 0 {
		log.Info("Show episodes refreshed", "count", attempted)
	}
	genres, err := w.Refresher.FillGenres(ctx)
	if err != nil {
		return err
	}
	if genres > 0 {
		log.Info("Title genres filled", "count", genres)
	}
	pages, err := w.Refresher.FillPageCounts(ctx)
	if err != nil {
		return err
	}
	if pages > 0 {
		log.Info("Book page counts filled", "count", pages)
	}
	return nil
}
