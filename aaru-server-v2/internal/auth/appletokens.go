package auth

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/crypto"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Apple's token endpoints (AUTH-006).
const (
	AppleTokenURL  = "https://appleid.apple.com/auth/token" //nolint:gosec // a URL, not a credential
	AppleRevokeURL = "https://appleid.apple.com/auth/revoke"
)

const (
	// appleSecretLifetime is how long one client secret is good for. Each call signs its own.
	appleSecretLifetime = 5 * time.Minute
	// appleCallTimeout bounds one call to Apple, so a slow Apple delays a sign-in or an account
	// deletion by this much at most and never fails either.
	appleCallTimeout = 8 * time.Second
)

// AppleTokens keeps and revokes Sign in with Apple refresh tokens (AUTH-006, App Store rule
// 5.1.1(v)). A sign-in that carries an authorization code has it exchanged for a refresh token,
// stored sealed; deleting the account revokes it with Apple. Nil on the Service turns both off.
type AppleTokens struct {
	Client    *http.Client
	TokenURL  string
	RevokeURL string
	KeyID     string
	TeamID    string
	Key       *ecdsa.PrivateKey
	// ClientIDs are the client ids Key may sign for.
	ClientIDs []string
	Cipher    *crypto.TokenCipher
	Now       func() time.Time
}

// NewAppleTokens builds it from config; nil when the Sign in with Apple key is not configured.
func NewAppleTokens(cfg *config.AppleSignIn, client *http.Client) (*AppleTokens, error) {
	if cfg == nil {
		return nil, nil // unset turns revocation off
	}
	cipher, err := crypto.NewTokenCipherFromKey(cfg.TokenKey)
	if err != nil {
		return nil, fmt.Errorf("apple sign-in token key: %w", err)
	}
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	return &AppleTokens{
		Client: client, TokenURL: AppleTokenURL, RevokeURL: AppleRevokeURL,
		KeyID: cfg.KeyID, TeamID: cfg.TeamID, Key: cfg.PrivateKey, ClientIDs: cfg.ClientIDs,
		Cipher: cipher, Now: time.Now,
	}, nil
}

// appleRefusal is Apple saying no: its HTTP status and the `error` code of its JSON body
// (`invalid_grant`, `invalid_client`). Both are safe to log; neither names a person.
type appleRefusal struct {
	status int
	reason string
}

func (e appleRefusal) Error() string {
	return fmt.Sprintf("apple answered %d %s", e.status, e.reason)
}

// errAppleSubject: the code belonged to a different Apple user than the identity token.
var errAppleSubject = errors.New("apple: the authorization code is another user's")

// clientSecret is the ES256 JWT Apple takes as `client_secret`: issued by the team, about the
// client id, for Apple, and short-lived.
func (a *AppleTokens) clientSecret(clientID string) (string, error) {
	now := a.Now()
	header, err := json.Marshal(map[string]string{"alg": "ES256", "kid": a.KeyID})
	if err != nil {
		return "", fmt.Errorf("apple client secret: %w", err)
	}
	claims, err := json.Marshal(map[string]any{
		"iss": a.TeamID, "iat": now.Unix(), "exp": now.Add(appleSecretLifetime).Unix(),
		"aud": AppleIssuer, "sub": clientID,
	})
	if err != nil {
		return "", fmt.Errorf("apple client secret: %w", err)
	}
	enc := base64.RawURLEncoding
	message := enc.EncodeToString(header) + "." + enc.EncodeToString(claims)
	digest := sha256.Sum256([]byte(message))
	r, s, err := ecdsa.Sign(rand.Reader, a.Key, digest[:])
	if err != nil {
		return "", fmt.Errorf("apple client secret: %w", err)
	}
	// JWS wants the 64-byte r||s form, not ASN.1.
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return message + "." + enc.EncodeToString(sig), nil
}

// post sends a form to Apple and returns the body of a 200; anything else is an appleRefusal.
func (a *AppleTokens) post(ctx context.Context, endpoint, clientID string, form url.Values) ([]byte, error) {
	secret, err := a.clientSecret(clientID)
	if err != nil {
		return nil, err
	}
	form.Set("client_id", clientID)
	form.Set("client_secret", secret)
	ctx, cancel := context.WithTimeout(ctx, appleCallTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, fmt.Errorf("apple request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := a.Client.Do(req)
	if err != nil {
		// The error's text is the URL and the transport's reason: no form field is in it.
		return nil, fmt.Errorf("apple request: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return nil, fmt.Errorf("apple response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		var refusal struct {
			Error string `json:"error"`
		}
		_ = json.Unmarshal(body, &refusal) // a body that is not JSON leaves the reason empty
		return nil, appleRefusal{status: resp.StatusCode, reason: refusal.Error}
	}
	return body, nil
}

// exchange trades a sign-in's authorization code for a refresh token. subject is the verified
// identity token's `sub`: a code that turns out to be another Apple user's is refused. Apple
// wants redirectURI back only when the authorization had one (the web).
func (a *AppleTokens) exchange(ctx context.Context, clientID, code, redirectURI, subject string) (string, error) {
	form := url.Values{"grant_type": {"authorization_code"}, "code": {code}}
	if redirectURI != "" {
		form.Set("redirect_uri", redirectURI)
	}
	body, err := a.post(ctx, a.TokenURL, clientID, form)
	if err != nil {
		return "", err
	}
	var answer struct {
		RefreshToken string `json:"refresh_token"`
		IDToken      string `json:"id_token"`
	}
	if err := json.Unmarshal(body, &answer); err != nil || answer.RefreshToken == "" {
		return "", errors.New("apple: the token response had no refresh token")
	}
	// The id_token came straight from Apple over TLS, so its claims are read without checking
	// the signature again.
	if sub, ok := unverifiedSubject(answer.IDToken); !ok || sub != subject {
		return "", errAppleSubject
	}
	return answer.RefreshToken, nil
}

func unverifiedSubject(jwt string) (string, bool) {
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		return "", false
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", false
	}
	var claims struct {
		Sub string `json:"sub"`
	}
	if json.Unmarshal(payload, &claims) != nil || claims.Sub == "" {
		return "", false
	}
	return claims.Sub, true
}

// revoke ends the user's Sign in with Apple authorization for clientID. Apple answers 200 for a
// token it no longer knows too, so revoking twice is harmless.
func (a *AppleTokens) revoke(ctx context.Context, clientID, refreshToken string) error {
	_, err := a.post(ctx, a.RevokeURL, clientID, url.Values{
		"token": {refreshToken}, "token_type_hint": {"refresh_token"},
	})
	return err
}

func (a *AppleTokens) signsFor(clientID string) bool {
	for _, id := range a.ClientIDs {
		if id == clientID {
			return true
		}
	}
	return false
}

// appleFailure is what a failed call to Apple logs: Apple's status and reason, or that Apple
// was not reached. Never the token, the code or an email.
func appleFailure(err error) []any {
	var refusal appleRefusal
	if errors.As(err, &refusal) {
		return []any{"status", refusal.status, "reason", refusal.reason}
	}
	if errors.Is(err, errAppleSubject) {
		return []any{"reason", "subject_mismatch"}
	}
	var netErr interface{ Timeout() bool }
	if errors.As(err, &netErr) && netErr.Timeout() {
		return []any{"reason", "timeout"}
	}
	return []any{"reason", "unreachable"}
}

// keepAppleToken exchanges the sign-in's authorization code and stores the refresh token
// sealed. It never fails the sign-in: whatever goes wrong is logged, and that account's
// deletion then has nothing to revoke for this client.
func (s *Service) keepAppleToken(ctx context.Context, userID uuid.UUID, identity AppleIdentity, in AppleSignIn) {
	if s.AppleTokens == nil || in.AuthorizationCode == "" {
		return
	}
	clientID := identity.Audience
	if !s.AppleTokens.signsFor(clientID) {
		slog.WarnContext(ctx, "Apple sign-in code not exchanged: the key does not sign for this client", "clientId", clientID)
		return
	}
	refresh, err := s.AppleTokens.exchange(ctx, clientID, in.AuthorizationCode, in.RedirectURI, identity.Subject)
	if err != nil {
		slog.WarnContext(ctx, "Apple sign-in code not exchanged", append(appleFailure(err), "clientId", clientID)...)
		return
	}
	sealed, err := s.AppleTokens.Cipher.Seal(refresh)
	if err != nil {
		slog.ErrorContext(ctx, "Apple refresh token not sealed", "error", err.Error())
		return
	}
	if err := s.Store.keepAppleRefreshToken(ctx, userID, clientID, sealed); err != nil {
		slog.ErrorContext(ctx, "Apple refresh token not stored", "error", err.Error())
	}
}

// revokeAppleTokens revokes every Sign in with Apple token kept for the user, one per client
// id. It never stops the deletion: a failure is a warning with Apple's status.
func (s *Service) revokeAppleTokens(ctx context.Context, userID uuid.UUID) {
	if s.AppleTokens == nil {
		return
	}
	rows, err := s.Store.appleRefreshTokens(ctx, userID)
	if err != nil {
		slog.ErrorContext(ctx, "Apple refresh tokens not read for revocation", "error", err.Error())
		return
	}
	for _, row := range rows {
		refresh, err := s.AppleTokens.Cipher.Open(row.RefreshToken)
		if err != nil {
			slog.ErrorContext(ctx, "Apple refresh token not opened for revocation", "clientId", row.ClientID)
			continue
		}
		if err := s.AppleTokens.revoke(ctx, row.ClientID, refresh); err != nil {
			slog.WarnContext(ctx, "Apple sign-in not revoked on account deletion",
				append(appleFailure(err), "clientId", row.ClientID)...)
		}
	}
}

func (s *Store) keepAppleRefreshToken(ctx context.Context, userID uuid.UUID, clientID, sealed string) error {
	err := s.q.KeepAppleRefreshToken(ctx, sqlc.KeepAppleRefreshTokenParams{UserID: userID, ClientID: clientID, RefreshToken: sealed})
	if err != nil {
		return fmt.Errorf("keep apple refresh token: %w", err)
	}
	return nil
}

func (s *Store) appleRefreshTokens(ctx context.Context, userID uuid.UUID) ([]sqlc.AppleRefreshTokensRow, error) {
	rows, err := s.q.AppleRefreshTokens(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("apple refresh tokens: %w", err)
	}
	return rows, nil
}
