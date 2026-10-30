package crypto

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Key bytes 0…31; the sealed value was produced by CryptoKit's
// `AES.GCM.seal(_:using:).combined.base64EncodedString()`, exactly as the Swift
// server's TokenCipher seals Trakt and MyAnimeList tokens.
const (
	swiftKey    = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
	swiftSealed = "RCSxPdbYyZqmg1x00CVXYwKHBkpkmwtDUYgW74QgM/lHUqn50HAMJj4YvKk4DXa9lQ=="
	swiftPlain  = "trakt-access-token-é"
)

func TestOpensWhatSwiftSealed(t *testing.T) {
	c, err := NewTokenCipher(swiftKey)
	require.NoError(t, err)
	plain, err := c.Open(swiftSealed)
	require.NoError(t, err)
	assert.Equal(t, swiftPlain, plain)
}

func TestSealRoundTripsWithAFreshNonce(t *testing.T) {
	c, err := NewTokenCipher(swiftKey)
	require.NoError(t, err)
	a, err := c.Seal("secret")
	require.NoError(t, err)
	b, err := c.Seal("secret")
	require.NoError(t, err)
	assert.NotEqual(t, a, b)
	plain, err := c.Open(a)
	require.NoError(t, err)
	assert.Equal(t, "secret", plain)
}

func TestRefusesBadKeysAndTampering(t *testing.T) {
	_, err := NewTokenCipher("c2hvcnQ=")
	require.ErrorIs(t, err, ErrInvalidKey)
	_, err = NewTokenCipher("not base64!")
	require.ErrorIs(t, err, ErrInvalidKey)

	c, err := NewTokenCipher(swiftKey)
	require.NoError(t, err)
	tampered := []byte(swiftSealed)
	tampered[20] ^= 1
	_, err = c.Open(string(tampered))
	require.ErrorIs(t, err, ErrOpenFailed)
	_, err = c.Open("%%%")
	require.ErrorIs(t, err, ErrOpenFailed)
	_, err = c.Open("AAAA")
	require.ErrorIs(t, err, ErrOpenFailed)
}
