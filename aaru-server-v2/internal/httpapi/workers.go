package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/mal"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/safe"
	"aaru-go-api/internal/schedule"
	"aaru-go-api/internal/scrobble"
	"context"
	"fmt"
	"log/slog"
	"time"
)

// Worker runs beside the HTTP server until ctx is cancelled.
type Worker interface {
	Name() string
	Run(ctx context.Context) error
}

// Workers are the background loops this server needs (imports, sweeps, refreshes, pushes).
// Each area appends its own.
func (s *Server) Workers() []Worker {
	var workers []Worker
	if s.ProductEvents != nil {
		// Posts product events every 10 seconds and drains the queue on shutdown.
		workers = append(workers, s.ProductEvents)
	}
	if s.Catalog != nil {
		// Keeps tracked shows' episodes, genres and book page counts current.
		workers = append(workers, catalog.NewRefreshWorker(s.Catalog.Refresher, s.Log))
	}
	if s.Library != nil {
		// Moves finished shows back to in progress when a new episode airs (owner, 2026-10-30).
		workers = append(workers, library.NewReopenWorker(s.Library.Store, s.Log))
	}
	if s.Gamification != nil {
		// Evaluates dirty and never-evaluated users' badges (GamificationWorker).
		workers = append(workers, gamification.NewWorker(s.Gamification))
	}
	if s.Imports != nil {
		// Leases import jobs and plans them (JOB-001), IMPORTS_WORKERS loops.
		workers = append(workers, &imports.Worker{Imports: s.Imports, Log: s.Log, Loops: s.Config.Workers.Imports})
		// Deletes capture inputs the worker never read, an hour on (CaptureSweeper, AG-006).
		workers = append(workers, &capture.Sweeper{Store: s.Imports.CaptureStore(), Log: s.Log})
	}
	if s.MALConnect != nil && s.Imports != nil && s.Library != nil && s.Catalog != nil {
		// Reads MyAnimeList lists back and pushes anime progress every 30 seconds (MALSyncService,
		// SCR-005/SCR-010); none without MAL_CLIENT_ID.
		if w := mal.NewWorker(s.MALConnect, s.Imports, s.Library.Store, s.Catalog.Store, s.Log); w != nil {
			workers = append(workers, w)
		}
	}
	// Looks up album artists and matches them to Ticketmaster every half hour (MUS-003).
	workers = append(workers, &concerts.Worker{
		Refresher: concerts.NewRefresher(s.Concerts.Store, s.ConcertArtists, s.Concerts.Listing), Log: s.Log,
	})
	if s.Pool != nil {
		// Announces newly aired episodes every ten minutes (AiringNotifierService). Without APNs
		// or web push configured each pass sends nothing, as in Swift.
		notifier := &push.AiringNotifier{Q: s.q, Log: s.Log}
		if s.Push != nil {
			notifier.APNs, notifier.Web = s.Push.APNs, s.Push.Web
		}
		workers = append(workers, schedule.NewAiringWorker(notifier, s.Log))
	}
	if s.Model != nil && s.Groups != nil {
		// Answers queued `@aaru` mentions (GRP-011), AGENT_REPLY_WORKERS loops on a leased queue.
		workers = append(workers, &agent.ReplyWorker{
			Replies: &agent.ReplyService{Groups: s.Groups, Catalog: s.Catalog, Library: s.Library, Model: s.Model, Log: s.Log},
			Log:     s.Log, Workers: s.Config.Workers.AgentReplies,
		})
	}
	if s.Scrobble != nil && s.Scrobble.Notifier != nil {
		// Looks again every 15 s at users whose "Now playing" activity is due to change with no
		// report to say so (LiveActivitySweepService). Without APNs there is nothing to sweep.
		workers = append(workers, &scrobble.SweepWorker{Notifier: s.Scrobble.Notifier, Log: s.Log})
	}
	if s.Listens != nil && s.Catalog != nil && s.Catalog.Providers.Recordings != nil {
		// Identifies scrobbled tracks on MusicBrainz every minute (ListenResolverService, MUS-006).
		workers = append(workers, &music.ResolverWorker{
			Resolver: &music.Resolver{Store: s.Listens.Store, Recordings: s.Catalog.Providers.Recordings}, Log: s.Log,
		})
	}
	if s.Pool != nil {
		// The import and `@aaru` queues' backlog on `/metrics`, read at scrape time.
		q := s.q
		metrics.SetQueueSource(func(ctx context.Context) ([]metrics.QueueStat, error) {
			return queueStats(ctx, q)
		})
	}
	supervised := make([]Worker, len(workers))
	for i, w := range workers {
		supervised[i] = &supervisedWorker{Worker: w, log: s.Log}
	}
	return supervised
}

func queueStats(ctx context.Context, q *sqlc.Queries) ([]metrics.QueueStat, error) {
	rows, err := q.WorkerQueueStats(ctx, time.Now())
	if err != nil {
		return nil, fmt.Errorf("worker queue stats: %w", err)
	}
	out := make([]metrics.QueueStat, len(rows))
	for i, r := range rows {
		out[i] = metrics.QueueStat{
			Queue: r.Queue, Depth: r.Depth, OldestAge: time.Duration(r.OldestAgeSeconds * float64(time.Second)),
		}
	}
	return out, nil
}

// supervisedWorker is the backstop under every worker (Go audit REL-001): a panic that escapes
// Run is logged, counted as the worker's failed pass, and Run starts again a second later instead
// of the process going down with it. Workers recover their own job steps first; this catches
// what they miss on their own goroutine.
type supervisedWorker struct {
	Worker
	log *slog.Logger
}

// RestartDelay is the pause before a worker that panicked runs again.
const RestartDelay = time.Second

func (w *supervisedWorker) Run(ctx context.Context) error {
	for {
		err := safe.Step(func() error { return w.Worker.Run(ctx) })
		if !safe.IsPanic(err) {
			return err
		}
		metrics.WorkerPass(w.Name(), err)
		log := w.log
		if log == nil {
			log = slog.Default()
		}
		log.Error("Worker panicked; restarting it", "worker", w.Name(), "error", err.Error(),
			"stack", string(safe.Stack(err)))
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(RestartDelay):
		}
	}
}
