// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetCalendar(context.Context, api.GetCalendarRequestObject) (api.GetCalendarResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListWatching(context.Context, api.ListWatchingRequestObject) (api.ListWatchingResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetUpNext(context.Context, api.GetUpNextRequestObject) (api.GetUpNextResponseObject, error) {
	return nil, errNotImplemented
}
