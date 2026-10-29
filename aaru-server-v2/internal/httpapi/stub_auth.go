// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) SignInWithApple(context.Context, api.SignInWithAppleRequestObject) (api.SignInWithAppleResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RequestMagicLink(context.Context, api.RequestMagicLinkRequestObject) (api.RequestMagicLinkResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) VerifyMagicLink(context.Context, api.VerifyMagicLinkRequestObject) (api.VerifyMagicLinkResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SignInWithGoogle(context.Context, api.SignInWithGoogleRequestObject) (api.SignInWithGoogleResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SignOut(context.Context, api.SignOutRequestObject) (api.SignOutResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteAccount(context.Context, api.DeleteAccountRequestObject) (api.DeleteAccountResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetMe(context.Context, api.GetMeRequestObject) (api.GetMeResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) LinkGoogle(context.Context, api.LinkGoogleRequestObject) (api.LinkGoogleResponseObject, error) {
	return nil, errNotImplemented
}
