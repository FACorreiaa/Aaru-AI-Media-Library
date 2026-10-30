package httpapi

import (
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
	if s.Gamification != nil {
		// Evaluates dirty and never-evaluated users' badges (GamificationWorker).
		workers = append(workers, gamification.NewWorker(s.Gamification))
	}
	return workers
}
