package trakt

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/token"
	"context"
	"net/http"
	"time"

	"github.com/google/uuid"
)

// RequestLifetime is how long a sign-in may take.
const RequestLifetime = 10 * time.Minute

// ConnectService is IMP-002: connect a Trakt account with PKCE. The verifier never leaves the
// server; the tokens are stored sealed; the browser only ever carries a one-time `state` and `code`.
type ConnectService struct {
	Store *Store
	// Settings and API are nil when Trakt is not configured: connect answers 503.
	Settings *Settings
	API      *API
	Now      func() time.Time
}

// Status is the user's connection as Settings shows it.
type Status struct {
	Connected   bool
	Username    *string
	ConnectedAt *time.Time
}

func (s *ConnectService) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s *ConnectService) enabled() (*Settings, *API, error) {
	if s.Settings == nil || s.API == nil {
		return nil, nil, apperr.New(http.StatusServiceUnavailable, "trakt_unavailable", "Trakt is not available on this server yet.")
	}
	return s.Settings, s.API, nil
}

// ReturnNotAllowed is the answer to a return address that is not Aaru's (Trakt and MAL).
func ReturnNotAllowed() *apperr.Error {
	return apperr.New(http.StatusUnprocessableEntity, "validation_failed", "That return address is not allowed.").
		WithDetails(map[string]string{"returnTo": "Not an Aaru address."})
}

// Start starts a sign-in and returns where to send the browser.
func (s *ConnectService) Start(ctx context.Context, user uuid.UUID, returnTo string) (string, error) {
	settings, _, err := s.enabled()
	if err != nil {
		return "", err
	}
	if !AllowsReturn(settings.ReturnPrefixes, returnTo) {
		return "", ReturnNotAllowed()
	}
	state := token.Generate()
	verifier := PKCEVerifier()
	if err := s.Store.CreateAuthRequest(ctx, token.Hash(state),
		AuthRequest{UserID: user, CodeVerifier: verifier, ReturnTo: returnTo}, s.now().Add(RequestLifetime)); err != nil {
		return "", err
	}
	return AuthorizeURL + "?" + QueryString([][2]string{
		{"response_type", "code"},
		{"client_id", settings.ClientID},
		{"redirect_uri", settings.RedirectURI},
		{"state", state},
		{"code_challenge", PKCEChallenge(verifier)},
		{"code_challenge_method", "S256"},
	}), nil
}

// Callback is Trakt's redirect back. It returns where to send the browser next, with `trakt=`
// telling the app how it went. An unknown or expired `state` is refused outright. A nil value is
// a query parameter that was not sent.
func (s *ConnectService) Callback(ctx context.Context, code, state, errParam *string) (string, error) {
	settings, api, err := s.enabled()
	if err != nil {
		return "", err
	}
	var request *AuthRequest
	if state != nil {
		if request, err = s.Store.ConsumeAuthRequest(ctx, token.Hash(*state), s.now()); err != nil {
			return "", err
		}
	}
	if request == nil {
		return "", apperr.New(http.StatusBadRequest, "trakt_state_invalid",
			"This Trakt sign-in expired or was already used. Start again from Aaru.")
	}
	if errParam != nil || code == nil {
		return Returning(request.ReturnTo, "trakt", "denied"), nil
	}
	tokens, err := api.Exchange(ctx, *code, request.CodeVerifier)
	if err == nil {
		username, _ := api.Username(ctx, tokens.AccessToken)
		err = s.save(ctx, tokens, username, request.UserID, settings)
	}
	if err != nil {
		return Returning(request.ReturnTo, "trakt", "failed"), nil
	}
	return Returning(request.ReturnTo, "trakt", "connected"), nil
}

// Status is whether the user has connected Trakt.
func (s *ConnectService) Status(ctx context.Context, user uuid.UUID) (Status, error) {
	c, err := s.Store.Connection(ctx, user)
	if err != nil || c == nil {
		return Status{}, err
	}
	connectedAt := c.ConnectedAt
	return Status{Connected: true, Username: c.Username, ConnectedAt: &connectedAt}, nil
}

// Disconnect revokes the tokens on Trakt first, which frees one of the user's Trakt app slots
// (free accounts get two). Best effort: forgetting the tokens here is what disconnects.
func (s *ConnectService) Disconnect(ctx context.Context, user uuid.UUID) error {
	if s.Settings != nil && s.API != nil {
		c, err := s.Store.Connection(ctx, user)
		if err != nil {
			return err
		}
		if c != nil {
			if access, err := s.Settings.Cipher.Open(c.SealedAccessToken); err == nil {
				_ = s.API.Revoke(ctx, access)
			}
		}
	}
	return s.Store.DeleteConnection(ctx, user)
}

// AccessToken is a usable access token, refreshed first when it expires within the hour. nil when
// the user has not connected Trakt. Trakt's refresh tokens are single use, so the refresh runs with
// the connection locked and a caller that waited reuses the token the first one got. A refresh
// Trakt refuses means the user must connect again (provider.KindUnauthorized).
func (s *ConnectService) AccessToken(ctx context.Context, user uuid.UUID) (*string, error) {
	settings, api, err := s.enabled()
	if err != nil {
		return nil, err
	}
	c, err := s.Store.Connection(ctx, user)
	if err != nil || c == nil {
		return nil, err
	}
	if s.isFresh(c.ExpiresAt) {
		return open(settings, c.SealedAccessToken)
	}
	refreshed, err := s.Store.RefreshConnection(ctx, user, func(current Connection) (Connection, bool, error) {
		if s.isFresh(current.ExpiresAt) {
			return current, false, nil
		}
		refreshToken, err := settings.Cipher.Open(current.SealedRefreshToken)
		if err != nil {
			return Connection{}, false, err
		}
		tokens, err := api.Refresh(ctx, refreshToken)
		if p, ok := provider.AsError(err); ok && p.Kind == provider.KindRefused && p.Status == http.StatusBadRequest {
			return Connection{}, false, provider.NewError(p.Provider, provider.KindUnauthorized) // invalid_grant
		}
		if err != nil {
			return Connection{}, false, err
		}
		next, err := s.record(tokens, current.Username, current.ConnectedAt, settings)
		return next, true, err
	})
	if err != nil || refreshed == nil {
		return nil, err
	}
	return open(settings, refreshed.SealedAccessToken)
}

func open(settings *Settings, sealed string) (*string, error) {
	plain, err := settings.Cipher.Open(sealed)
	if err != nil {
		return nil, err
	}
	return &plain, nil
}

func (s *ConnectService) isFresh(expiresAt time.Time) bool {
	return expiresAt.After(s.now().Add(time.Hour))
}

func (s *ConnectService) save(ctx context.Context, tokens Tokens, username *string, user uuid.UUID, settings *Settings) error {
	c, err := s.record(tokens, username, s.now(), settings)
	if err != nil {
		return err
	}
	return s.Store.SaveConnection(ctx, c, user)
}

// record seals the tokens. Trakt says how long the token lives (24 hours or 7 days, it has
// changed); trust that.
func (s *ConnectService) record(tokens Tokens, username *string, connectedAt time.Time, settings *Settings) (Connection, error) {
	access, err := settings.Cipher.Seal(tokens.AccessToken)
	if err != nil {
		return Connection{}, err
	}
	refresh, err := settings.Cipher.Seal(tokens.RefreshToken)
	if err != nil {
		return Connection{}, err
	}
	return Connection{
		SealedAccessToken: access, SealedRefreshToken: refresh,
		ExpiresAt: s.now().Add(time.Duration(tokens.ExpiresIn) * time.Second),
		Username:  username, ConnectedAt: connectedAt,
	}, nil
}
