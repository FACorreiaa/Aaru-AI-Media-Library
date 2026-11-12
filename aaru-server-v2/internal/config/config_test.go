package config

import (
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
