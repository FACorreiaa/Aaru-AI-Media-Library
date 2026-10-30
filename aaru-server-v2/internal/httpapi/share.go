package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/shares"
	"context"

	"github.com/google/uuid"
)

// ShareHandlers.swift: SHR-002 share links.

// CreateShare makes a link to a title, sport event or concert.
func (s *Server) CreateShare(ctx context.Context, req api.CreateShareRequestObject) (api.CreateShareResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	target := req.Body.Target
	request := shares.Request{Kind: shares.Kind(target.Kind)}
	switch target.Kind {
	case api.ShareKindTitle:
		if target.Ref == nil {
			return nil, shares.Invalid("Say which title to share.")
		}
		request.Ref = MediaRefFromAPI(*target.Ref)
	case api.ShareKindSportEvent:
		if target.Id == nil {
			return nil, shares.Invalid("Say which event to share.")
		}
		request.ID = *target.Id
	case api.ShareKindConcert:
		if target.Id == nil {
			return nil, shares.Invalid("Say which concert to share.")
		}
		request.ID = *target.Id
	default:
		return nil, apperr.BadRequest()
	}
	share, err := s.Shares.Create(ctx, viewer, request, req.Body.Note)
	if err != nil {
		return nil, err
	}
	return api.CreateShare200JSONResponse(api.ShareLink{Code: share.Code, Url: s.Shares.URL(share)}), nil
}

// GetSharePreview is public: what the link shows, signed in or out.
func (s *Server) GetSharePreview(ctx context.Context, req api.GetSharePreviewRequestObject) (api.GetSharePreviewResponseObject, error) {
	var viewer *uuid.UUID
	if id, ok := reqctx.UserID(ctx); ok {
		viewer = &id
	}
	preview, err := s.Shares.Preview(ctx, req.Code, viewer, reqctx.ClientAddress(ctx))
	if err != nil {
		return nil, err
	}
	out := api.SharePreview{Kind: api.ShareKind(preview.Share.Target.Kind), Unavailable: preview.Unavailable}
	if preview.Title != nil {
		title := TitleDetailDTO(*preview.Title)
		out.Title = &title
	}
	if preview.SportEvent != nil {
		event := sportEventDTO(*preview.SportEvent, false)
		out.SportEvent = &event
	}
	if preview.Concert != nil {
		concert := concertDTO(*preview.Concert)
		out.Concert = &concert
	}
	if preview.From != nil {
		out.From = &api.ShareSender{User: SocialUserDTO(preview.From.User), Note: preview.From.Note}
	}
	if item := preview.ViewerItem; item != nil {
		id := apiid.From(item.Item.ID)
		status := api.LibraryStatus(item.Item.Status)
		out.LibraryItemId, out.Status = &id, &status
	}
	return api.GetSharePreview200JSONResponse(out), nil
}
