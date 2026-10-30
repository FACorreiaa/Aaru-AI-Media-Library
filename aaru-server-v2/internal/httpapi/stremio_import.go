package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"context"
)

// ImportHandlers.swift's Stremio history import (IMP-016): a link code, then polls.

func (s *Server) StartStremioLink(ctx context.Context, _ api.StartStremioLinkRequestObject) (api.StartStremioLinkResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	link, err := s.Imports.StartStremioLink(ctx, user)
	if err != nil {
		return nil, err
	}
	return api.StartStremioLink200JSONResponse{
		Code: link.Code, Link: link.Link, Qrcode: link.QRCode, ExpiresAt: apitime.From(link.ExpiresAt),
	}, nil
}

func (s *Server) PollStremioLink(ctx context.Context, req api.PollStremioLinkRequestObject) (api.PollStremioLinkResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	job, err := s.Imports.PollStremioLink(ctx, req.Code, user)
	if err != nil {
		return nil, err
	}
	if job == nil {
		return api.PollStremioLink204Response{}, nil
	}
	return api.PollStremioLink202JSONResponse(ImportJobDTO(*job)), nil
}
