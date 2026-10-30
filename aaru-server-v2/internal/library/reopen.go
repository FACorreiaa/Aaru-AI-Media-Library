package library

import (
	"aaru-go-api/internal/db/sqlc"
	"context"
	"log/slog"
	"time"
)

const (
	// ReopenInterval is how often finished shows are checked for a new episode. Shorter than the
	// airing notifier's ten minutes, so a reopened show is in progress before its alert is due.
	ReopenInterval = 5 * time.Minute
	// ReopenWindow is how far back an airing counts as new.
	ReopenWindow = 7 * 24 * time.Hour
)

// ReopenAired moves finished shows back to in progress when a regular episode they have not
// ticked aired after they were finished, within ReopenWindow of now (owner, 2026-10-30): Watched
// on a running show means caught up, and a new season or next week's episode makes it Watching
// again. Not a user's write, so it is not journaled. Returns how many items moved.
func (s *Store) ReopenAired(ctx context.Context, now time.Time) (int, error) {
	since := now.Add(-ReopenWindow)
	n, err := s.q.LibraryReopenAired(ctx, sqlc.LibraryReopenAiredParams{Now: now, Since: &since})
	return int(n), err
}

// ReopenWorker runs ReopenAired every five minutes in the API process.
type ReopenWorker struct {
	Store    *Store
	Log      *slog.Logger
	Interval time.Duration
}

// NewReopenWorker is the worker with the five-minute interval.
func NewReopenWorker(store *Store, log *slog.Logger) *ReopenWorker {
	return &ReopenWorker{Store: store, Log: log, Interval: ReopenInterval}
}

// Name is the worker's log name.
func (w *ReopenWorker) Name() string { return "library-reopen" }

// Run loops until ctx is cancelled. A failed pass is logged and the loop goes on.
func (w *ReopenWorker) Run(ctx context.Context) error {
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for ctx.Err() == nil {
		n, err := w.Store.ReopenAired(ctx, w.Store.now())
		switch {
		case err != nil && ctx.Err() != nil:
			return nil
		case err != nil:
			log.Error("Library reopen pass failed", "error", err.Error())
		case n > 0:
			log.Info("Finished shows reopened", "count", n)
		}
		select {
		case <-ctx.Done():
		case <-time.After(w.Interval):
		}
	}
	return nil
}
