package agent

import (
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/safe"
	"context"
	"log/slog"
	"sync"
	"time"
)

// ReplyWorker answers queued `@aaru` mentions in the background, off the request path. Workers
// loops (AGENT_REPLY_WORKERS, default 1) share the leased queue.
type ReplyWorker struct {
	Replies *ReplyService
	Log     *slog.Logger
	Workers int
	// Idle is the wait after an empty queue or a failed step; zero means one second.
	Idle time.Duration
}

// Name is the worker's name in logs.
func (w *ReplyWorker) Name() string { return "agent-replies" }

func (w *ReplyWorker) log() *slog.Logger {
	if w.Log != nil {
		return w.Log
	}
	return slog.Default()
}

// Run loops until ctx is cancelled.
func (w *ReplyWorker) Run(ctx context.Context) error {
	idle := w.Idle
	if idle <= 0 {
		idle = time.Second
	}
	var wg sync.WaitGroup
	for range max(1, w.Workers) {
		wg.Go(func() {
			for ctx.Err() == nil {
				// A panic outside the answer itself (claiming, bookkeeping) fails the step, not the process.
				worked, err := safe.Value(func() (bool, error) { return w.Replies.RunNext(ctx) })
				if ctx.Err() == nil {
					metrics.WorkerPass(w.Name(), err)
				}
				if err != nil && ctx.Err() == nil {
					// The job already recorded its failure; the loop must outlive one bad mention.
					w.log().Error("Agent reply step failed", "error", err, "stack", string(safe.Stack(err)))
				}
				if worked && err == nil {
					continue
				}
				select {
				case <-ctx.Done():
				case <-time.After(idle):
				}
			}
		})
	}
	wg.Wait()
	return nil
}
