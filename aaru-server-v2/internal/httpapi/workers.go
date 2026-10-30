package httpapi

import (
	"aaru-go-api/internal/concerts"
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
	// Looks up album artists and matches them to Ticketmaster every half hour (MUS-003).
	workers = append(workers, &concerts.Worker{
		Refresher: concerts.NewRefresher(s.Concerts.Store, s.ConcertArtists, s.Concerts.Listing), Log: s.Log,
	})
	return workers
}
