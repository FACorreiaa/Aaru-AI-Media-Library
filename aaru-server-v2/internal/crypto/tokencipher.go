// Package crypto seals provider tokens (Trakt, MyAnimeList) at rest.
package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"unicode/utf8"
)

// ErrInvalidKey is a key that is not base64 of exactly 32 bytes.
var ErrInvalidKey = errors.New("token cipher: the key must be 32 bytes, base64")

// ErrOpenFailed is a sealed value that is not base64, not ours, or tampered with.
var ErrOpenFailed = errors.New("token cipher: could not open the sealed value")

const nonceSize = 12

// TokenCipher is AES-256-GCM in CryptoKit's "combined" layout, byte-compatible
// with the Swift server's TokenCipher: standard base64 of nonce (12 bytes) ||
// ciphertext || tag (16 bytes). Tokens sealed by the Swift server open here.
type TokenCipher struct {
	aead cipher.AEAD
}

// NewTokenCipher builds the cipher from a base64 32-byte key (TRAKT_TOKEN_KEY, MAL_TOKEN_KEY).
func NewTokenCipher(base64Key string) (*TokenCipher, error) {
	key, err := base64.StdEncoding.DecodeString(base64Key)
	if err != nil || len(key) != 32 {
		return nil, ErrInvalidKey
	}
	return NewTokenCipherFromKey(key)
}

// NewTokenCipherFromKey builds the cipher from the raw 32-byte key (config.OAuthProvider.TokenKey).
func NewTokenCipherFromKey(key []byte) (*TokenCipher, error) {
	if len(key) != 32 {
		return nil, ErrInvalidKey
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("token cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("token cipher: %w", err)
	}
	return &TokenCipher{aead: aead}, nil
}

// Seal encrypts plaintext with a fresh random nonce.
func (c *TokenCipher) Seal(plaintext string) (string, error) {
	nonce := make([]byte, nonceSize)
	if _, err := rand.Read(nonce); err != nil {
		return "", fmt.Errorf("token cipher: %w", err)
	}
	combined := c.aead.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(combined), nil
}

// Open decrypts a value Seal (or the Swift server) produced.
func (c *TokenCipher) Open(sealed string) (string, error) {
	data, err := base64.StdEncoding.DecodeString(sealed)
	if err != nil || len(data) < nonceSize+c.aead.Overhead() {
		return "", ErrOpenFailed
	}
	plain, err := c.aead.Open(nil, data[:nonceSize], data[nonceSize:], nil)
	if err != nil || !utf8.Valid(plain) {
		return "", ErrOpenFailed
	}
	return string(plain), nil
}
