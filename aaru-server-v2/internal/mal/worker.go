package mal

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/provider"
	"context"
	"log/slog"
	"strconv"
	"time"
)

// Worker is MALSyncService: it runs the MyAnimeList read-back and push every 30 seconds in the API
// process, so a tick reaches MAL within a minute and a read a client asked for starts within one.
// Reads that are not due cost one query.
type Worker struct {
	Pusher   *Pusher
	Puller   *Puller
	Log      *slog.Logger
	Interval time.Duration
}

// NewWorker is the sync worker over a configured MyAnimeList (connect.API set); nil otherwise.
func NewWorker(connect *ConnectService, imports Applier, lib *library.Store, cat *catalog.Store, log *slog.Logger) *Worker {
	if connect == nil || connect.API == nil {
		return nil
	}
	return &Worker{
		Pusher: &Pusher{Store: connect.Store, Connect: connect, API: connect.API, Library: lib, Catalog: cat, Log: log},
		Puller: &Puller{Store: connect.Store, Connect: connect, Imports: imports, API: connect.API, Log: log},
		Log:    log,
	}
}

// Name names the worker in logs.
func (w *Worker) Name() string { return "mal-sync" }

// Run runs a pass every interval until ctx is cancelled.
func (w *Worker) Run(ctx context.Context) error {
	interval := w.Interval
	if interval <= 0 {
		interval = 30 * time.Second
	}
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for ctx.Err() == nil {
		if err := w.pass(ctx, log); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			log.Error("MyAnimeList sync pass failed", "error", err.Error())
		}
		if err := provider.Sleep(ctx, interval); err != nil {
			return nil
		}
	}
	return nil
}

func (w *Worker) pass(ctx context.Context, log *slog.Logger) error {
	read, err := w.Puller.RunOnce(ctx)
	if err != nil {
		return err
	}
	if read > 0 {
		log.Info("MyAnimeList entries read back", "titles", strconv.Itoa(read))
	}
	sent, err := w.Pusher.RunOnce(ctx)
	if err != nil {
		return err
	}
	if sent > 0 {
		log.Info("MyAnimeList entries pushed", "entries", strconv.Itoa(sent))
	}
	return nil
}
