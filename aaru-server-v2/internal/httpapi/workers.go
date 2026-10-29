package httpapi

import "context"

// Worker runs beside the HTTP server until ctx is cancelled.
type Worker interface {
	Name() string
	Run(ctx context.Context) error
}

// Workers are the background loops this server needs (imports, sweeps, refreshes, pushes).
// Each area appends its own.
func (s *Server) Workers() []Worker {
	return nil
}
