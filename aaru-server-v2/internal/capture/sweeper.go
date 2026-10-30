package capture

import (
	"context"
	"log/slog"
	"time"
)

// Sweeper deletes capture inputs the worker never read (a job deleted first, a crash), an hour
// on (CaptureSweeper). One pass every five minutes.
type Sweeper struct {
	Store *Store
	Log   *slog.Logger
	// Every defaults to five minutes.
	Every time.Duration
	Now   func() time.Time
}

// Name is the worker's name in logs.
func (w *Sweeper) Name() string { return "capture-sweeper" }

// Run sweeps until ctx is cancelled. A failed pass is logged and the next one tried.
func (w *Sweeper) Run(ctx context.Context) error {
	every := w.Every
	if every <= 0 {
		every = 5 * time.Minute
	}
	now := time.Now
	if w.Now != nil {
		now = w.Now
	}
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for {
		if _, err := w.Store.Sweep(ctx, now().Add(-InputLifetime)); err != nil && ctx.Err() == nil {
			log.Error("Capture sweep failed", "error", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(every):
		}
	}
}
