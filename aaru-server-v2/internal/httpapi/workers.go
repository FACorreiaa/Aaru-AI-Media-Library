package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/mal"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/schedule"
	"aaru-go-api/internal/scrobble"
	"context"
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
		notifier := &push.AiringNotifier{Q: s.q}
		if s.Push != nil {
			notifier.APNs, notifier.Web = s.Push.APNs, s.Push.Web
		}
		workers = append(workers, schedule.NewAiringWorker(notifier, s.Log))
	}
	if s.Model != nil && s.Groups != nil {
		// Answers queued `@aaru` mentions (GRP-011), AGENT_REPLY_WORKERS loops on a leased queue.
		workers = append(workers, &agent.ReplyWorker{
			Replies: &agent.ReplyService{Groups: s.Groups, Catalog: s.Catalog, Library: s.Library, Model: s.Model},
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
	return workers
}
