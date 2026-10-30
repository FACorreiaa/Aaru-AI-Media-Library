package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/social"
	"bytes"
	"context"
	"io"
	"net/http"

	"github.com/google/uuid"
)

// AvatarHandlers.swift: SOC-001b avatars. Profile data like `PUT /v1/me/profile`: never journaled.

var errAvatarTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That photo is larger than 1 MB.")

// UploadAvatar replaces the viewer's avatar with one JPEG of at most 1 MB.
func (s *Server) UploadAvatar(ctx context.Context, req api.UploadAvatarRequestObject) (api.UploadAvatarResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	image, err := io.ReadAll(io.LimitReader(req.Body, social.MaxAvatarBytes+1))
	if err != nil || len(image) > social.MaxAvatarBytes {
		return nil, errAvatarTooLarge
	}
	profile, err := s.Social.SaveAvatar(ctx, viewer, image)
	if err != nil {
		return nil, err
	}
	return api.UploadAvatar200JSONResponse(MeDTO(profile)), nil
}

// DeleteAvatar removes the viewer's avatar; the monogram shows again.
func (s *Server) DeleteAvatar(ctx context.Context, _ api.DeleteAvatarRequestObject) (api.DeleteAvatarResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	profile, err := s.Social.RemoveAvatar(ctx, viewer)
	if err != nil {
		return nil, err
	}
	return api.DeleteAvatar200JSONResponse(MeDTO(profile)), nil
}

// GetUserAvatar answers someone's avatar to any signed-in account. middleware.AvatarCache sets
// Cache-Control.
func (s *Server) GetUserAvatar(ctx context.Context, req api.GetUserAvatarRequestObject) (api.GetUserAvatarResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.UserId.ID() == uuid.Nil {
		return nil, social.ErrNoAvatar
	}
	image, err := s.Social.Avatar(ctx, req.UserId.ID(), viewer)
	if err != nil {
		return nil, err
	}
	return api.GetUserAvatar200ImagejpegResponse{Body: bytes.NewReader(image), ContentLength: int64(len(image))}, nil
}
