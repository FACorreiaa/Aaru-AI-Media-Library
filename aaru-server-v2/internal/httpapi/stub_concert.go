// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetArtistConcerts(context.Context, api.GetArtistConcertsRequestObject) (api.GetArtistConcertsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetConcertsNear(context.Context, api.GetConcertsNearRequestObject) (api.GetConcertsNearResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SearchConcertPerformers(context.Context, api.SearchConcertPerformersRequestObject) (api.SearchConcertPerformersResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SearchConcertPlaces(context.Context, api.SearchConcertPlacesRequestObject) (api.SearchConcertPlacesResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SearchConcerts(context.Context, api.SearchConcertsRequestObject) (api.SearchConcertsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteConcertPlace(context.Context, api.DeleteConcertPlaceRequestObject) (api.DeleteConcertPlaceResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetConcertPlace(context.Context, api.GetConcertPlaceRequestObject) (api.GetConcertPlaceResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SaveConcertPlace(context.Context, api.SaveConcertPlaceRequestObject) (api.SaveConcertPlaceResponseObject, error) {
	return nil, errNotImplemented
}
