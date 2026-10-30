package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"context"
)

// CreateCATFeedImport is `POST /v1/imports/cat/feed`: the user's CAT iCal link, read once now and
// never kept (IMP-010).
func (s *Server) CreateCATFeedImport(ctx context.Context, req api.CreateCATFeedImportRequestObject) (api.CreateCATFeedImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	job, err := s.Imports.CreateCATFeedImport(ctx, user, req.Body.Url)
	if err != nil {
		return nil, err
	}
	return api.CreateCATFeedImport202JSONResponse(ImportJobDTO(job)), nil
}
