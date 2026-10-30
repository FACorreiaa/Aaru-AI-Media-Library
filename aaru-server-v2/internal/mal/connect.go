package mal

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/token"
	"aaru-go-api/internal/trakt"
	"context"
	"net/http"
	"time"

	"github.com/google/uuid"
)

// RequestLifetime is how long a sign-in may take.
const RequestLifetime = 10 * time.Minute

// ConnectService is SCR-005: connect a MyAnimeList account. The same flow as Trakt's, except MAL
// accepts only the `plain` PKCE method: the challenge is the verifier itself. The tokens are
// stored sealed; the browser only ever carries a one-time `state` and `code`.
type ConnectService struct {
	Store *Store
	// Settings and API are nil when MyAnimeList is not configured: connect answers 503.
	Settings *Settings
	API      *API
	Now      func() time.Time
}

// Status is the user's connection as Settings shows it.
type Status struct {
	Connected   bool
	Username    *string
	ConnectedAt *time.Time
	// NeedsReconnect: MAL refused the tokens; the user must connect again before anything is pushed.
	NeedsReconnect bool
	// PulledAt is when the list was last read back (SCR-010).
	PulledAt *time.Time
	// Removed are entries removed on MAL that Aaru keeps.
	Removed []RemovedEntry
}

func (s *ConnectService) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s *ConnectService) enabled() (*Settings, *API, error) {
	if s.Settings == nil || s.API == nil {
		return nil, nil, apperr.New(http.StatusServiceUnavailable, "mal_unavailable", "MyAnimeList is not available on this server yet.")
	}
	return s.Settings, s.API, nil
}

// Start starts a sign-in and returns where to send the browser.
func (s *ConnectService) Start(ctx context.Context, user uuid.UUID, returnTo string) (string, error) {
	settings, _, err := s.enabled()
	if err != nil {
		return "", err
	}
	if !trakt.AllowsReturn(settings.ReturnPrefixes, returnTo) {
		return "", trakt.ReturnNotAllowed()
	}
	state := token.Generate()
	verifier := trakt.PKCEVerifier()
	if err := s.Store.CreateAuthRequest(ctx, token.Hash(state),
		AuthRequest{UserID: user, CodeVerifier: verifier, ReturnTo: returnTo}, s.now().Add(RequestLifetime)); err != nil {
		return "", err
	}
	return AuthorizeURL + "?" + trakt.QueryString([][2]string{
		{"response_type", "code"},
		{"client_id", settings.ClientID},
		{"redirect_uri", settings.RedirectURI},
		{"state", state},
		{"code_challenge", verifier},
		{"code_challenge_method", "plain"},
	}), nil
}

// Callback is MAL's redirect back. It returns where to send the browser next, with `mal=` telling
// the app how it went. An unknown or expired `state` is refused outright. A nil value is a query
// parameter that was not sent.
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
		return "", apperr.New(http.StatusBadRequest, "mal_state_invalid",
			"This MyAnimeList sign-in expired or was already used. Start again from Aaru.")
	}
	if errParam != nil || code == nil {
		return trakt.Returning(request.ReturnTo, "mal", "denied"), nil
	}
	tokens, err := api.Exchange(ctx, *code, request.CodeVerifier)
	if err == nil {
		username, _ := api.Username(ctx, tokens.AccessToken)
		var c Connection
		if c, err = s.record(tokens, username, s.now(), settings); err == nil {
			// Only writes from now on go out: connecting never overwrites the MAL list with the
			// library as it was.
			err = s.Store.SaveConnection(ctx, c, s.now(), request.UserID)
		}
	}
	if err != nil {
		return trakt.Returning(request.ReturnTo, "mal", "failed"), nil
	}
	return trakt.Returning(request.ReturnTo, "mal", "connected"), nil
}

// Status is the user's connection, what it last read and what MAL removed.
func (s *ConnectService) Status(ctx context.Context, user uuid.UUID) (Status, error) {
	c, err := s.Store.Connection(ctx, user)
	if err != nil || c == nil {
		return Status{Removed: []RemovedEntry{}}, err
	}
	removed, err := s.Store.RemovedEntries(ctx, user)
	if err != nil {
		return Status{}, err
	}
	connectedAt := c.ConnectedAt
	return Status{
		Connected: true, Username: c.Username, ConnectedAt: &connectedAt, NeedsReconnect: c.RevokedAt != nil,
		PulledAt: c.PulledAt, Removed: removed,
	}, nil
}

// RequestPull is a client opening Aaru (SCR-010): read this user's list on the next sync pass,
// unless it was read in the last 10 minutes. False when nothing was asked.
func (s *ConnectService) RequestPull(ctx context.Context, user uuid.UUID) (bool, error) {
	now := s.now()
	return s.Store.RequestPull(ctx, user, now, now.Add(-10*time.Minute))
}

// Disconnect forgets the tokens: MAL has no revoke endpoint. The user can also remove Aaru under
// MAL's Account Settings → API.
func (s *ConnectService) Disconnect(ctx context.Context, user uuid.UUID) error {
	return s.Store.DeleteConnection(ctx, user)
}

// AccessToken is a usable access token, refreshed first when it expires within the hour. nil when
// the user has not connected MAL or MAL refused the tokens. A refresh MAL refuses marks the
// connection for reconnecting (provider.KindUnauthorized).
func (s *ConnectService) AccessToken(ctx context.Context, user uuid.UUID) (*string, error) {
	settings, api, err := s.enabled()
	if err != nil {
		return nil, err
	}
	c, err := s.Store.Connection(ctx, user)
	if err != nil || c == nil || c.RevokedAt != nil {
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
		next.RevokedAt = current.RevokedAt
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

// record seals the tokens. MAL says how long the token lives (31 days today, though its docs say
// an hour); trust that.
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
