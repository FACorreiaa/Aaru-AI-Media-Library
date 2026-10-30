package auth

import (
	"aaru-go-api/internal/token"
	"context"
	"encoding/json"
	"strings"
)

// Apple's and Google's issuers and key sets.
const (
	AppleIssuer   = "https://appleid.apple.com"
	AppleKeysURL  = "https://appleid.apple.com/auth/keys"
	GoogleKeysURL = "https://www.googleapis.com/oauth2/v3/certs"
)

var googleIssuers = map[string]bool{"https://accounts.google.com": true, "accounts.google.com": true}

// AppleIdentity is what a verified Sign in with Apple identity token says.
type AppleIdentity struct {
	// Subject is Apple's stable user id (`sub`): the only thing an account is keyed on.
	Subject        string
	Email          *string
	IsPrivateRelay bool
}

// AppleVerifying verifies a Sign in with Apple identity token. A token that
// fails any check returns ErrInvalidToken.
type AppleVerifying interface {
	Verify(ctx context.Context, identityToken, rawNonce string) (AppleIdentity, error)
}

// GoogleIdentity is a verified Google ID token (AUTH-005).
type GoogleIdentity struct {
	Subject string
	Email   *string
	Name    *string
}

// GoogleVerifying verifies a Google ID token. `nonce`, when the client sent one, must come back in it.
type GoogleVerifying interface {
	Verify(ctx context.Context, idToken string, nonce *string) (GoogleIdentity, error)
}

// ErrInvalidToken is a token whose signature, issuer, audience, expiry or nonce check failed.
var ErrInvalidToken = errInvalidToken

// AppleVerifier checks the signature against Apple's JWKS, the issuer, the
// audience (app bundle ids + web Services ID), the expiry, and the nonce.
type AppleVerifier struct {
	Audiences []string
	JWKS      *JWKSCache
}

// boolOrString: Apple sends some booleans as `true` and some as `"true"`.
type boolOrString bool

func (b *boolOrString) UnmarshalJSON(data []byte) error {
	var v bool
	if json.Unmarshal(data, &v) == nil {
		*b = boolOrString(v)
		return nil
	}
	var s string
	_ = json.Unmarshal(data, &s)
	*b = boolOrString(strings.ToLower(s) == "true")
	return nil
}

type appleClaims struct {
	registeredClaims
	Nonce          *string       `json:"nonce"`
	Email          *string       `json:"email"`
	IsPrivateEmail *boolOrString `json:"is_private_email"`
}

// Verify implements AppleVerifying.
func (v AppleVerifier) Verify(ctx context.Context, identityToken, rawNonce string) (AppleIdentity, error) {
	var claims appleClaims
	if err := v.JWKS.verifyJWT(ctx, identityToken, &claims, func() float64 { return claims.expiry() }); err != nil {
		return AppleIdentity{}, err
	}
	if !claims.complete() || *claims.Iss != AppleIssuer || !claims.Aud.any(set(v.Audiences)) {
		return AppleIdentity{}, ErrInvalidToken
	}
	// The client sends Apple sha256(rawNonce) and sends us rawNonce, so a token
	// lifted from another sign-in cannot be replayed here.
	if rawNonce == "" || claims.Nonce == nil || *claims.Nonce != token.SHA256Hex(rawNonce) {
		return AppleIdentity{}, ErrInvalidToken
	}
	identity := AppleIdentity{Subject: *claims.Sub}
	if claims.Email != nil {
		lower := strings.ToLower(*claims.Email)
		identity.Email = &lower
	}
	if claims.IsPrivateEmail != nil {
		identity.IsPrivateRelay = bool(*claims.IsPrivateEmail)
	}
	return identity, nil
}

// GoogleVerifier checks Google ID tokens against Google's published keys:
// issuer, audience (the iOS and web client ids), expiry, nonce. Keyed on `sub`, never on email.
type GoogleVerifier struct {
	Audiences []string
	JWKS      *JWKSCache
}

type googleClaims struct {
	registeredClaims
	Email         *string `json:"email"`
	EmailVerified *bool   `json:"email_verified"`
	Name          *string `json:"name"`
	Nonce         *string `json:"nonce"`
}

// Verify implements GoogleVerifying.
func (v GoogleVerifier) Verify(ctx context.Context, idToken string, nonce *string) (GoogleIdentity, error) {
	var claims googleClaims
	if err := v.JWKS.verifyJWT(ctx, idToken, &claims, func() float64 { return claims.expiry() }); err != nil {
		return GoogleIdentity{}, err
	}
	if !claims.complete() || !googleIssuers[*claims.Iss] || !claims.Aud.any(set(v.Audiences)) {
		return GoogleIdentity{}, ErrInvalidToken
	}
	if nonce != nil && (claims.Nonce == nil || *claims.Nonce != *nonce) {
		return GoogleIdentity{}, ErrInvalidToken
	}
	identity := GoogleIdentity{Subject: *claims.Sub, Name: claims.Name}
	// An unverified Google email is not an email we may write to.
	if claims.EmailVerified != nil && *claims.EmailVerified && claims.Email != nil {
		lower := strings.ToLower(*claims.Email)
		identity.Email = &lower
	}
	return identity, nil
}
