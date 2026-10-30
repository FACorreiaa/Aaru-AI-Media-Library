package imports

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"
)

// Worker is JOB-001's in-process import worker (ImportWorker). Jobs are leased, so a crash
// mid-job leaves the job re-runnable once its lease expires. Loops (IMPORTS_WORKERS, default 1)
// share the queue.
type Worker struct {
	Imports *Service
	Log     *slog.Logger
	Loops   int
	// Idle is how long an idle loop sleeps before asking again (2 s).
	Idle time.Duration
}

// Name names the worker in logs.
func (w *Worker) Name() string { return "imports" }

// Run runs the loops until ctx is cancelled.
func (w *Worker) Run(ctx context.Context) error {
	idle := w.Idle
	if idle <= 0 {
		idle = 2 * time.Second
	}
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	Loops(ctx, max(1, w.Loops), idle, func(ctx context.Context) (bool, error) {
		return w.Imports.RunNext(ctx, nil)
	}, func(err error) {
		// The job already recorded its failure; the loop must outlive one bad job.
		log.Error("Import worker step failed", "error", err)
	})
	return nil
}

// Loops runs count copies of one queue's loop, each taking the next job until ctx is cancelled.
// step returns whether it did work; an idle loop sleeps idle before asking again (workerLoops).
func Loops(ctx context.Context, count int, idle time.Duration, step func(context.Context) (bool, error), failed func(error)) {
	var wg sync.WaitGroup
	for range count {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for ctx.Err() == nil {
				worked, err := step(ctx)
				if err != nil {
					if errors.Is(err, context.Canceled) && ctx.Err() != nil {
						return
					}
					failed(err)
				} else if worked {
					continue
				}
				select {
				case <-ctx.Done():
					return
				case <-time.After(idle):
				}
			}
		}()
	}
	wg.Wait()
}
