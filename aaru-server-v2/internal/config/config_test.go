package config

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTranscriptionConfig(t *testing.T) {
	base := map[string]string{"postgres.user": "u", "postgres.password": "p", "postgres.database": "d", "tmdb.api.key": "k"}

	cfg, err := Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.Nil(t, cfg.Transcription, "unset URL leaves voice off")

	base["transcription.base.url"] = "http://whisper.horus.svc.cluster.local:8000/v1"
	_, err = Load(NewReaderFrom(base))
	var missing MissingError
	require.ErrorAs(t, err, &missing)
	assert.Equal(t, "TRANSCRIPTION_MODEL", missing.Env)

	base["transcription.model"] = "  \t "
	_, err = Load(NewReaderFrom(base))
	require.ErrorAs(t, err, &missing, "blank is as missing as unset")
	assert.Equal(t, "TRANSCRIPTION_MODEL", missing.Env)

	base["transcription.model"] = "Systran/faster-whisper-small"
	cfg, err = Load(NewReaderFrom(base))
	require.NoError(t, err)
	require.NotNil(t, cfg.Transcription)
	assert.Equal(t, "/v1", cfg.Transcription.BaseURL.Path)
	assert.Equal(t, "Systran/faster-whisper-small", cfg.Transcription.Model)
}

func TestBillingAcceptSandboxIsOffUnlessSet(t *testing.T) {
	base := map[string]string{"postgres.user": "u", "postgres.password": "p", "postgres.database": "d", "tmdb.api.key": "k"}
	cfg, err := Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.False(t, cfg.AcceptSandbox)

	base["billing.accept_sandbox"] = "true"
	cfg, err = Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.True(t, cfg.AcceptSandbox)
	assert.Equal(t, "BILLING_ACCEPT_SANDBOX", envName("billing.accept_sandbox"))
}

func TestReviewAccountNeedsBothHalvesAndSixDigits(t *testing.T) {
	base := map[string]string{"postgres.user": "u", "postgres.password": "p", "postgres.database": "d", "tmdb.api.key": "k"}
	cfg, err := Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.Nil(t, cfg.Review, "unset, no address is special")

	base["review.email"] = " Review@Aaru.test "
	_, err = Load(NewReaderFrom(base))
	var missing MissingError
	require.ErrorAs(t, err, &missing, "an address with no code is refused at boot")
	assert.Equal(t, "REVIEW_CODE", missing.Env)

	for _, bad := range []string{"12345", "1234567", "12a456", "123 456"} {
		base["review.code"] = bad
		_, err = Load(NewReaderFrom(base))
		require.ErrorAs(t, err, &missing, bad)
		assert.Equal(t, "REVIEW_CODE", missing.Env)
	}

	base["review.code"] = "135790"
	cfg, err = Load(NewReaderFrom(base))
	require.NoError(t, err)
	require.NotNil(t, cfg.Review)
	assert.Equal(t, "review@aaru.test", cfg.Review.Email, "compared as sign-in normalizes it")
	assert.Equal(t, "135790", cfg.Review.Code)

	delete(base, "review.email")
	_, err = Load(NewReaderFrom(base))
	require.ErrorAs(t, err, &missing, "a code with no address is refused too")
	assert.Equal(t, "REVIEW_EMAIL", missing.Env)
}

func TestAppleSignInKeyComesWholeOrNotAtAll(t *testing.T) {
	base := map[string]string{"postgres.user": "u", "postgres.password": "p", "postgres.database": "d", "tmdb.api.key": "k"}
	cfg, err := Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.Nil(t, cfg.AppleSignIn, "unset, nothing is exchanged or revoked")

	// A throwaway key, made here: never a real one.
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	p8 := string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	tokenKey := base64.StdEncoding.EncodeToString(make([]byte, 32))

	var missing MissingError
	for name, part := range map[string]struct{ key, value, env string }{
		"only the private key": {"apple.signin.private.key", p8, "APPLE_SIGNIN_KEY_ID"},
		"only the key id":      {"apple.signin.key.id", "ABC123DEFG", "APPLE_SIGNIN_PRIVATE_KEY (a P-256 .p8)"},
		"only the sealing key": {"apple.signin.token.key", tokenKey, "APPLE_SIGNIN_KEY_ID"},
	} {
		base[part.key] = part.value
		_, err = Load(NewReaderFrom(base))
		require.ErrorAs(t, err, &missing, name)
		assert.Equal(t, part.env, missing.Env, name)
		delete(base, part.key)
	}

	base["apple.signin.key.id"] = "ABC123DEFG"
	base["apple.signin.private.key"] = p8
	_, err = Load(NewReaderFrom(base))
	require.ErrorAs(t, err, &missing, "no sealing key")
	assert.Equal(t, "APPLE_SIGNIN_TOKEN_KEY (32 bytes, base64)", missing.Env)

	base["apple.signin.token.key"] = tokenKey
	base["apple.signin.private.key"] = "not a key"
	_, err = Load(NewReaderFrom(base))
	require.ErrorAs(t, err, &missing, "a key that does not parse")
	assert.Equal(t, "APPLE_SIGNIN_PRIVATE_KEY (a P-256 .p8)", missing.Env)

	base["apple.signin.private.key"] = p8
	cfg, err = Load(NewReaderFrom(base))
	require.NoError(t, err)
	require.NotNil(t, cfg.AppleSignIn)
	assert.Equal(t, "ABC123DEFG", cfg.AppleSignIn.KeyID)
	assert.Equal(t, "84X9WYBF36", cfg.AppleSignIn.TeamID, "the APNs team unless told otherwise")
	assert.True(t, key.Equal(cfg.AppleSignIn.PrivateKey))
	assert.Equal(t, cfg.AppleAudiences, cfg.AppleSignIn.ClientIDs, "every audience, unless narrowed")
	assert.Len(t, cfg.AppleSignIn.TokenKey, 32)

	base["apple.signin.client.ids"] = "com.fernandocorreia.aaru, com.aaruapp.web"
	base["apple.signin.team.id"] = "TEAM123456"
	cfg, err = Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.Equal(t, []string{"com.fernandocorreia.aaru", "com.aaruapp.web"}, cfg.AppleSignIn.ClientIDs)
	assert.Equal(t, "TEAM123456", cfg.AppleSignIn.TeamID)
}
