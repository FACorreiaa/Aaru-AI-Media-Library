package schedule

import (
	"aaru-go-api/internal/push"
	"context"
	"log/slog"
	"time"
)

// AiringInterval is how often the airing notifier runs.
const AiringInterval = 10 * time.Minute

// AiringWorker runs the airing notifier every ten minutes in the API process (AiringNotifierService).
type AiringWorker struct {
	Notifier *push.AiringNotifier
	Log      *slog.Logger
	Interval time.Duration
}

// NewAiringWorker is the worker with Swift's interval.
func NewAiringWorker(notifier *push.AiringNotifier, log *slog.Logger) *AiringWorker {
	return &AiringWorker{Notifier: notifier, Log: log, Interval: AiringInterval}
}

// Name is the worker's log name.
func (w *AiringWorker) Name() string { return "airing-notifier" }

// Run loops until ctx is cancelled. A failed pass is logged and the loop goes on.
func (w *AiringWorker) Run(ctx context.Context) error {
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for ctx.Err() == nil {
		sent, err := w.Notifier.RunOnce(ctx)
		switch {
		case err != nil && ctx.Err() != nil:
			return nil
		case err != nil:
			log.Error("Airing notifier pass failed", "error", err.Error())
		case sent > 0:
			log.Info("Airing notifications sent", "count", sent)
		}
		select {
		case <-ctx.Done():
		case <-time.After(w.Interval):
		}
	}
	return nil
}
