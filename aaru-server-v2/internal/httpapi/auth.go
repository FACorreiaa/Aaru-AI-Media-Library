package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/reqctx"
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/google/uuid"
)

func sessionDTO(s auth.NewSession) api.Session {
	return api.Session{Token: s.Token, UserId: apiid.From(s.UserID), ExpiresAt: apitime.From(s.ExpiresAt)}
}

// SignInWithApple is `POST /v1/auth/apple` (AUTH-002).
func (s *Server) SignInWithApple(ctx context.Context, req api.SignInWithAppleRequestObject) (api.SignInWithAppleResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	session, err := s.Auth.SignInWithApple(ctx, req.Body.IdentityToken, req.Body.Nonce, req.Body.DisplayName)
	if err != nil {
		return nil, err
	}
	return api.SignInWithApple200JSONResponse(sessionDTO(session)), nil
}

// SignInWithGoogle is `POST /v1/auth/google` (AUTH-005).
func (s *Server) SignInWithGoogle(ctx context.Context, req api.SignInWithGoogleRequestObject) (api.SignInWithGoogleResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	session, err := s.Auth.SignInWithGoogle(ctx, req.Body.IdToken, req.Body.Nonce)
	if err != nil {
		return nil, err
	}
	return api.SignInWithGoogle200JSONResponse(sessionDTO(session)), nil
}

// LinkGoogle is `POST /v1/me/identities/google`.
func (s *Server) LinkGoogle(ctx context.Context, req api.LinkGoogleRequestObject) (api.LinkGoogleResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Auth.LinkGoogle(ctx, userID, req.Body.IdToken, req.Body.Nonce); err != nil {
		return nil, err
	}
	me, err := s.me(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.LinkGoogle200JSONResponse(me), nil
}

// RequestMagicLink is `POST /v1/auth/email/link` (AUTH-003).
func (s *Server) RequestMagicLink(ctx context.Context, req api.RequestMagicLinkRequestObject) (api.RequestMagicLinkResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	if err := s.Auth.RequestMagicLink(ctx, req.Body.Email, reqctx.ClientAddress(ctx)); err != nil {
		return nil, err
	}
	return api.RequestMagicLink202Response{}, nil
}

// VerifyMagicLink is `POST /v1/auth/email/verify`: the link's token, or the email and its code (APP-002).
func (s *Server) VerifyMagicLink(ctx context.Context, req api.VerifyMagicLinkRequestObject) (api.VerifyMagicLinkResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	var (
		session auth.NewSession
		err     error
	)
	switch body := req.Body; {
	case body.Token != nil:
		session, err = s.Auth.VerifyMagicLink(ctx, *body.Token)
	case body.Email != nil && body.Code != nil:
		session, err = s.Auth.VerifyEmailCode(ctx, *body.Email, *body.Code)
	default:
		return nil, (&apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed",
			Message: "Send the link's token, or the email and its code.",
		}).WithDetails(map[string]string{"token": "Or email and code."}) //nolint:gosec // a field name, not a credential
	}
	if err != nil {
		return nil, err
	}
	return api.VerifyMagicLink200JSONResponse(sessionDTO(session)), nil
}

// SignOut is `DELETE /v1/auth/session`: deletes exactly the presented session.
func (s *Server) SignOut(ctx context.Context, _ api.SignOutRequestObject) (api.SignOutResponseObject, error) {
	hash := reqctx.SessionTokenHash(ctx)
	if hash == "" {
		return nil, apperr.Unauthorized()
	}
	if err := s.Auth.SignOut(ctx, hash); err != nil {
		return nil, err
	}
	return api.SignOut204Response{}, nil
}

// GetMe is `GET /v1/me`.
func (s *Server) GetMe(ctx context.Context, _ api.GetMeRequestObject) (api.GetMeResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	me, err := s.me(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetMe200JSONResponse(me), nil
}

// DeleteAccount is `DELETE /v1/me` (AUTH-004).
func (s *Server) DeleteAccount(ctx context.Context, _ api.DeleteAccountRequestObject) (api.DeleteAccountResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Auth.DeleteAccount(ctx, userID); err != nil {
		return nil, err
	}
	return api.DeleteAccount204Response{}, nil
}

// me is the signed-in user's `Me`; 401 when the account is gone.
func (s *Server) me(ctx context.Context, userID uuid.UUID) (api.Me, error) {
	profile, found, err := s.Auth.Store.Profile(ctx, userID)
	if err != nil {
		return api.Me{}, err
	}
	if !found {
		return api.Me{}, apperr.Unauthorized()
	}
	return MeDTO(profile), nil
}

// MeDTO maps a profile to `Me`; other areas that answer `Me` (profile edits, avatars) reuse it.
func MeDTO(p auth.Profile) api.Me {
	providers := make([]api.MeProviders, 0, len(p.Providers))
	for _, provider := range p.Providers {
		providers = append(providers, api.MeProviders(provider))
	}
	shareable := p.EmailShareable()
	me := api.Me{
		UserId:         apiid.From(p.ID),
		DisplayName:    p.DisplayName(),
		FirstName:      p.FirstName,
		LastName:       p.LastName,
		Handle:         p.Handle,
		Providers:      providers,
		Email:          p.Email,
		EmailShareable: &shareable,
	}
	if p.AvatarVersion != nil {
		path := AvatarPath(p.ID, *p.AvatarVersion)
		me.AvatarUrl = &path
	}
	return me
}

// AvatarPath is where an avatar is read, with the version so caches never serve
// an old one. The id is uppercase, as Swift's UUID.uuidString printed it.
func AvatarPath(id uuid.UUID, version int64) string {
	return fmt.Sprintf("/v1/users/%s/avatar?v=%d", strings.ToUpper(id.String()), version)
}
