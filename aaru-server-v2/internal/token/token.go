// Package token makes and hashes the opaque bearer secrets (sessions, magic
// links, agent tokens). The secret is shown to the client once; Postgres stores
// only its SHA-256, so a database dump cannot sign anyone in.
package token

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"
)

// Generate is 32 random bytes, base64url without padding.
func Generate() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(fmt.Sprintf("crypto/rand: %v", err))
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// Hash is the stored form of a token: lowercase hex SHA-256.
func Hash(token string) string {
	return SHA256Hex(token)
}

// SHA256Hex hashes a string to lowercase hex.
func SHA256Hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// EmailCode is the 6-digit code in a sign-in email.
func EmailCode() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		panic(fmt.Sprintf("crypto/rand: %v", err))
	}
	return fmt.Sprintf("%06d", n.Int64())
}

// EmailCodeHash binds a code to its email, so a code alone matches nothing.
func EmailCodeHash(code, email string) string {
	return SHA256Hex(email + ":" + code)
}

// NormalizeEmailCode keeps digits only ("123 456", "123-456"); "" unless exactly six remain.
func NormalizeEmailCode(raw string) string {
	var b strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	if b.Len() != 6 {
		return ""
	}
	return b.String()
}
