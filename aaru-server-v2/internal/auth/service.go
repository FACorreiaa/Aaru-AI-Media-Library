// Package auth is sign-in, sign-out and account deletion (M2): Sign in with
// Apple, Google, the email magic link and its 6-digit code, sessions; plus the
// agent tokens outside callers use (OUT-001). Handlers call it; it owns the rules.
//
// For other areas: transports that take an agent token (MCP, Stremio, scrobble,
// ListenBrainz) call `Deps.AgentTokens.Authenticate(ctx, secret, auth.GroupMCP |
// GroupStremio | GroupScrobble | GroupMusic)` → AgentCaller{UserID, Token{ID,
// Kind, Scopes}}, check `caller.Has(auth.ScopeLibraryWrite)` etc., and
// `Deps.AgentTokens.Allow(caller)` for the 120-a-minute budget. MCP's
// `WWW-Authenticate` points at `Deps.OAuth.ResourceMetadataURL()`. Account
// deletion's group hand-over is `auth.LeaveGroups`; `httpapi.MeDTO` maps a profile
// to `Me`. Provider tokens are sealed with `crypto.TokenCipher`.
package auth

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/token"
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
)

// Lifetimes and limits, as the Swift AuthService had them.
const (
	SessionLifetime   = 90 * 24 * time.Hour
	MagicLinkLifetime = 15 * time.Minute
	MaxCodeAttempts   = 5
)

// NewSession is a freshly issued session. Token is returned to the client once and never stored.
type NewSession struct {
	Token     string
	UserID    uuid.UUID
	ExpiresAt time.Time
}

// MagicLinks is email sign-in's configuration; nil on the Service turns it off (no RESEND_API_KEY).
type MagicLinks struct {
	Sender MagicLinkSending
	// LinkBaseURL is where the emailed link points; the token is appended as `?token=`.
	LinkBaseURL *url.URL
}

// Service is AuthService.
type Service struct {
	Store *Store
	Apple AppleVerifying
	// MagicLinks is nil when email sign-in is not configured.
	MagicLinks *MagicLinks
	// Google is nil when Google sign-in is not configured (no GOOGLE_CLIENT_IDS).
	Google GoogleVerifying
	// OnAccountCreated, when set, hears of every new account (the `account_created`
	// product event). Never fails a sign-in.
	OnAccountCreated func(ctx context.Context, userID uuid.UUID, provider Provider)
	Now              func() time.Time

	perEmail  *ratelimit.FixedWindow
	perClient *ratelimit.FixedWindow
}

// NewService builds the service; the per-email and per-client sign-in email limits start empty.
func NewService(store *Store, apple AppleVerifying, magicLinks *MagicLinks, google GoogleVerifying) *Service {
	return &Service{
		Store: store, Apple: apple, MagicLinks: magicLinks, Google: google, Now: time.Now,
		perEmail:  ratelimit.New(5, time.Hour),
		perClient: ratelimit.New(20, time.Hour),
	}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// SignInWithApple is AUTH-002.
func (s *Service) SignInWithApple(ctx context.Context, identityToken, rawNonce string, displayName *string) (NewSession, error) {
	identity, err := s.Apple.Verify(ctx, identityToken, rawNonce)
	if err != nil {
		if errors.Is(err, ErrInvalidToken) {
			return NewSession{}, apperr.Unauthorized("The Apple sign-in could not be verified.")
		}
		return NewSession{}, err
	}
	// Keyed on `sub`, never on email: relay addresses and changed emails must not
	// fork an account. The name arrives only on the first authorization.
	userID, err := s.findOrCreateUser(ctx, Identity{Provider: ProviderApple, Subject: identity.Subject, Email: identity.Email}, displayName)
	if err != nil {
		return NewSession{}, err
	}
	return s.issueSession(ctx, userID)
}

// SignInWithGoogle is AUTH-005.
func (s *Service) SignInWithGoogle(ctx context.Context, idToken string, nonce *string) (NewSession, error) {
	identity, err := s.verifyGoogle(ctx, idToken, nonce)
	if err != nil {
		return NewSession{}, err
	}
	userID, err := s.findOrCreateUser(ctx, Identity{Provider: ProviderGoogle, Subject: identity.Subject, Email: identity.Email}, identity.Name)
	if err != nil {
		return NewSession{}, err
	}
	return s.issueSession(ctx, userID)
}

// LinkGoogle adds Google to the signed-in account, so one person signing in with
// Apple and with Google has one library. A Google account already on another Aaru
// account is refused, never merged.
func (s *Service) LinkGoogle(ctx context.Context, userID uuid.UUID, idToken string, nonce *string) error {
	identity, err := s.verifyGoogle(ctx, idToken, nonce)
	if err != nil {
		return err
	}
	owner, found, err := s.Store.userFor(ctx, ProviderGoogle, identity.Subject)
	if err != nil {
		return err
	}
	if found {
		if owner == userID {
			return nil
		}
		return apperr.New(http.StatusConflict, "identity_taken", "That Google account already signs in to a different Aaru account.")
	}
	err = s.Store.addIdentity(ctx, Identity{Provider: ProviderGoogle, Subject: identity.Subject, Email: identity.Email}, userID)
	var conflict storeConflict
	if errors.As(err, &conflict) {
		return apperr.Conflict(conflict.message)
	}
	return err
}

func (s *Service) verifyGoogle(ctx context.Context, idToken string, nonce *string) (GoogleIdentity, error) {
	if s.Google == nil {
		return GoogleIdentity{}, apperr.Unavailable("google_unavailable", "Sign in with Google is not available yet.")
	}
	identity, err := s.Google.Verify(ctx, idToken, nonce)
	if err != nil {
		if errors.Is(err, ErrInvalidToken) {
			return GoogleIdentity{}, apperr.Unauthorized("The Google sign-in could not be verified.")
		}
		return GoogleIdentity{}, err
	}
	return identity, nil
}

// RequestMagicLink sends a sign-in link (AUTH-003). The response is the same
// whether or not the address has an account: verifying the link is what creates one.
func (s *Service) RequestMagicLink(ctx context.Context, rawEmail, clientAddress string) error {
	if s.MagicLinks == nil {
		return apperr.Unavailable("email_unavailable", "Email sign-in is not available yet.")
	}
	email, err := NormalizedEmail(rawEmail)
	if err != nil {
		return err
	}
	now := s.now()
	if !s.perClient.Allow(clientAddress, now) || !s.perEmail.Allow(email, now) {
		return apperr.RateLimited("Too many sign-in emails. Try again later.")
	}
	secret := token.Generate()
	code := token.EmailCode()
	if err := s.Store.CreateMagicLink(ctx, email, token.Hash(secret), token.EmailCodeHash(code, email), now.Add(MagicLinkLifetime)); err != nil {
		return err
	}
	link := *s.MagicLinks.LinkBaseURL
	// Appended after any query the base URL has; the token is base64url, so it needs no escaping.
	if link.RawQuery != "" {
		link.RawQuery += "&"
	}
	link.RawQuery += "token=" + secret
	return s.MagicLinks.Sender.Send(ctx, email, link.String(), code)
}

// VerifyMagicLink signs in with the emailed link's token.
func (s *Service) VerifyMagicLink(ctx context.Context, secret string) (NewSession, error) {
	email, ok, err := s.Store.ConsumeMagicLink(ctx, token.Hash(secret), s.now())
	if err != nil {
		return NewSession{}, err
	}
	if !ok {
		return NewSession{}, apperr.Unauthorized("This sign-in link is invalid, expired, or already used.")
	}
	return s.signInEmail(ctx, email)
}

// VerifyEmailCode is the app's path while the link cannot open it (APP-002): the email plus its 6-digit code.
func (s *Service) VerifyEmailCode(ctx context.Context, rawEmail, rawCode string) (NewSession, error) {
	email, err := NormalizedEmail(rawEmail)
	if err != nil {
		return NewSession{}, err
	}
	code := token.NormalizeEmailCode(rawCode)
	if code == "" {
		return NewSession{}, (&apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed", Message: "The code is six digits.",
		}).WithDetails(map[string]string{"code": "Six digits."})
	}
	ok, err := s.Store.consumeCode(ctx, email, token.EmailCodeHash(code, email), MaxCodeAttempts, s.now())
	if err != nil {
		return NewSession{}, err
	}
	if !ok {
		return NewSession{}, apperr.Unauthorized("This code is wrong, expired, or already used.")
	}
	return s.signInEmail(ctx, email)
}

func (s *Service) signInEmail(ctx context.Context, email string) (NewSession, error) {
	userID, err := s.findOrCreateUser(ctx, Identity{Provider: ProviderEmail, Subject: email, Email: &email}, nil)
	if err != nil {
		return NewSession{}, err
	}
	return s.issueSession(ctx, userID)
}

// SignOut deletes exactly the presented session (AUTH-004).
func (s *Service) SignOut(ctx context.Context, tokenHash string) error {
	return s.Store.deleteSession(ctx, tokenHash)
}

// DeleteAccount deletes the user and everything that is theirs (AUTH-004).
func (s *Service) DeleteAccount(ctx context.Context, userID uuid.UUID) error {
	return s.Store.deleteUser(ctx, userID)
}

func (s *Service) findOrCreateUser(ctx context.Context, identity Identity, displayName *string) (uuid.UUID, error) {
	if id, found, err := s.Store.userFor(ctx, identity.Provider, identity.Subject); err != nil || found {
		return id, err
	}
	var name *string
	if displayName != nil {
		if trimmed := strings.TrimSpace(*displayName); trimmed != "" {
			name = &trimmed
		}
	}
	id, err := s.Store.createUser(ctx, identity, name)
	if err == nil {
		if s.OnAccountCreated != nil {
			s.OnAccountCreated(ctx, id, identity.Provider)
		}
		return id, nil
	}
	var conflict storeConflict
	if !errors.As(err, &conflict) {
		return uuid.Nil, err
	}
	// A concurrent sign-in created it first.
	id, found, err := s.Store.userFor(ctx, identity.Provider, identity.Subject)
	if err != nil {
		return uuid.Nil, err
	}
	if !found {
		return uuid.Nil, apperr.Internal()
	}
	return id, nil
}

func (s *Service) issueSession(ctx context.Context, userID uuid.UUID) (NewSession, error) {
	secret := token.Generate()
	expiresAt := s.now().Add(SessionLifetime)
	if err := s.Store.createSession(ctx, userID, token.Hash(secret), expiresAt); err != nil {
		return NewSession{}, err
	}
	return NewSession{Token: secret, UserID: userID, ExpiresAt: expiresAt}, nil
}

// NormalizedEmail trims and lowercases, and refuses anything that is not one plausible address.
func NormalizedEmail(raw string) (string, error) {
	email := strings.ToLower(strings.TrimSpace(raw))
	local, domain, ok := strings.Cut(email, "@")
	if core.Length(email) > 254 || !ok || strings.Contains(domain, "@") || local == "" ||
		!strings.Contains(domain, ".") || strings.ContainsFunc(email, unicode.IsSpace) {
		return "", (&apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed", Message: "That email address is not valid.",
		}).WithDetails(map[string]string{"email": "Not a valid email address."})
	}
	return email, nil
}
