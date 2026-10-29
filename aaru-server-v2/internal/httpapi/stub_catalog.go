// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetDiscover(context.Context, api.GetDiscoverRequestObject) (api.GetDiscoverResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetDiscoverOnAir(context.Context, api.GetDiscoverOnAirRequestObject) (api.GetDiscoverOnAirResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetDiscoverSeason(context.Context, api.GetDiscoverSeasonRequestObject) (api.GetDiscoverSeasonResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SearchCatalog(context.Context, api.SearchCatalogRequestObject) (api.SearchCatalogResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ResolveTitle(context.Context, api.ResolveTitleRequestObject) (api.ResolveTitleResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetTitle(context.Context, api.GetTitleRequestObject) (api.GetTitleResponseObject, error) {
	return nil, errNotImplemented
}
