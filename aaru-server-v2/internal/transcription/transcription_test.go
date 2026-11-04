package transcription

import (
	"aaru-go-api/internal/provider"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func client(t *testing.T, h http.HandlerFunc) *OpenAICompatible {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	base, err := url.Parse(srv.URL + "/v1")
	require.NoError(t, err)
	return &OpenAICompatible{BaseURL: base, Model: "Systran/faster-whisper-small", Transport: provider.NewHTTPTransport()}
}

func TestMultipartShape(t *testing.T) {
	audio := []byte("RIFFfake-audio-bytes")
	c := client(t, func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, http.MethodPost, r.Method)
		assert.Equal(t, "/v1/audio/transcriptions", r.URL.Path)
		assert.Empty(t, r.Header.Get("Authorization"))
		require.NoError(t, r.ParseMultipartForm(1<<20))
		assert.Equal(t, "Systran/faster-whisper-small", r.FormValue("model"))
		assert.Equal(t, "Dune, Frieren", r.FormValue("prompt"))
		assert.Equal(t, "verbose_json", r.FormValue("response_format"))
		_, hasLang := r.MultipartForm.Value["language"]
		assert.False(t, hasLang)
		f, hdr, err := r.FormFile("file")
		require.NoError(t, err)
		assert.Equal(t, "audio.m4a", hdr.Filename)
		got, _ := io.ReadAll(f)
		assert.Equal(t, audio, got)
		_, _ = w.Write([]byte(`{"text":"hi","language":"en"}`))
	})
	_, err := c.Transcribe(context.Background(), audio, "audio/mp4", "Dune, Frieren")
	require.NoError(t, err)
}

func TestResult(t *testing.T) {
	c := client(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"text":" Hello ","language":"pt"}`))
	})
	res, err := c.Transcribe(context.Background(), []byte("a"), "audio/webm", "")
	require.NoError(t, err)
	assert.Equal(t, Result{Text: "Hello", Language: "pt"}, res)
}

func TestEmpty(t *testing.T) {
	c := client(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"text":"  \n"}`))
	})
	_, err := c.Transcribe(context.Background(), []byte("a"), "audio/webm", "")
	assert.ErrorIs(t, err, ErrEmpty)
}

func TestServerError(t *testing.T) {
	c := client(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("boom"))
	})
	audio := []byte("SECRET-AUDIO-BYTES")
	_, err := c.Transcribe(context.Background(), audio, "audio/webm", "")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "500")
	assert.NotContains(t, err.Error(), string(audio))
}

func TestFilenameByContentType(t *testing.T) {
	assert.Equal(t, "audio.m4a", filename("audio/m4a"))
	assert.Equal(t, "audio.m4a", filename("audio/mp4"))
	assert.Equal(t, "audio.webm", filename("audio/webm"))
	assert.Equal(t, "audio.ogg", filename("audio/ogg; codecs=opus"))
}
