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
