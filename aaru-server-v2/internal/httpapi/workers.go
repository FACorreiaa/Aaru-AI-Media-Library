package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/gamification"
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
	return workers
}
