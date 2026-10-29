// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListSportFollows(context.Context, api.ListSportFollowsRequestObject) (api.ListSportFollowsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UnfollowSport(context.Context, api.UnfollowSportRequestObject) (api.UnfollowSportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) FollowSport(context.Context, api.FollowSportRequestObject) (api.FollowSportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSportSettings(context.Context, api.GetSportSettingsRequestObject) (api.GetSportSettingsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SaveSportSettings(context.Context, api.SaveSportSettingsRequestObject) (api.SaveSportSettingsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSportEvent(context.Context, api.GetSportEventRequestObject) (api.GetSportEventResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSportFavorites(context.Context, api.GetSportFavoritesRequestObject) (api.GetSportFavoritesResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSportSchedule(context.Context, api.GetSportScheduleRequestObject) (api.GetSportScheduleResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SearchSports(context.Context, api.SearchSportsRequestObject) (api.SearchSportsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSportSuggestions(context.Context, api.GetSportSuggestionsRequestObject) (api.GetSportSuggestionsResponseObject, error) {
	return nil, errNotImplemented
}
