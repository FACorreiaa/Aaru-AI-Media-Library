// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) DeleteAvatar(context.Context, api.DeleteAvatarRequestObject) (api.DeleteAvatarResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UploadAvatar(context.Context, api.UploadAvatarRequestObject) (api.UploadAvatarResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetUserAvatar(context.Context, api.GetUserAvatarRequestObject) (api.GetUserAvatarResponseObject, error) {
	return nil, errNotImplemented
}
