// Package transcription is speech to text over the OpenAI
// `POST /v1/audio/transcriptions` shape, served in-cluster by the shared whisper
// service. The client is named for the wire format, not a vendor, so moving between
// the in-cluster service and a hosted one is configuration. Audio is held in memory
// only and never appears in an error or a log line.
package transcription

import (
	"aaru-go-api/internal/provider"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"mime"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"strings"
	"time"
)

// ErrEmpty is a transcript with no words in it.
var ErrEmpty = errors.New("transcription is empty")

// DefaultTimeout bounds one call: a CPU-only server is slower than a hosted one.
const DefaultTimeout = 60 * time.Second

// Result is one transcript.
type Result struct {
	Text     string
	Language string
}

// OpenAICompatible calls an OpenAI-shaped transcription endpoint. BaseURL ends at
// the API root (…/v1). The self-hosted service takes no key, so none is sent.
type OpenAICompatible struct {
	BaseURL   *url.URL
	Model     string
	Transport provider.Transport
	// Timeout defaults to DefaultTimeout.
	Timeout time.Duration
}

// Transcribe sends the audio and returns the trimmed text and the detected language.
// prompt biases decoding toward titles and names; blank sends none. No language is
// forced, so the service detects it.
func (c *OpenAICompatible) Transcribe(ctx context.Context, audio []byte, contentType, prompt string) (Result, error) {
	body, formType, err := buildBody(audio, contentType, c.Model, prompt)
	if err != nil {
		return Result{}, err
	}
	timeout := c.Timeout
	if timeout <= 0 {
		timeout = DefaultTimeout
	}
	endpoint := c.BaseURL.JoinPath("audio", "transcriptions").String()
	resp, err := c.Transport.Send(ctx, provider.Request{
		Method:  http.MethodPost,
		URL:     endpoint,
		Headers: [][2]string{{"Content-Type", formType}},
		Body:    body,
		Timeout: timeout,
	})
	if err != nil {
		return Result{}, fmt.Errorf("transcription request: %w", err)
	}
	if resp.Status != http.StatusOK {
		return Result{}, fmt.Errorf("transcription service answered %d", resp.Status)
	}
	var out struct {
		Text     string `json:"text"`
		Language string `json:"language"`
	}
	if err := json.Unmarshal(resp.Body, &out); err != nil {
		return Result{}, fmt.Errorf("decode transcription: %w", err)
	}
	text := strings.TrimSpace(out.Text)
	if text == "" {
		return Result{}, ErrEmpty
	}
	return Result{Text: text, Language: strings.TrimSpace(out.Language)}, nil
}

func buildBody(audio []byte, contentType, model, prompt string) ([]byte, string, error) {
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	fields := [][2]string{{"model", model}, {"response_format", "verbose_json"}}
	if strings.TrimSpace(prompt) != "" {
		fields = append(fields, [2]string{"prompt", prompt})
	}
	for _, f := range fields {
		if err := w.WriteField(f[0], f[1]); err != nil {
			return nil, "", fmt.Errorf("build transcription form: %w", err)
		}
	}
	h := textproto.MIMEHeader{}
	h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename=%q`, filename(contentType)))
	h.Set("Content-Type", "application/octet-stream")
	part, err := w.CreatePart(h)
	if err != nil {
		return nil, "", fmt.Errorf("build transcription form: %w", err)
	}
	if _, err := part.Write(audio); err != nil {
		return nil, "", fmt.Errorf("build transcription form: %w", err)
	}
	if err := w.Close(); err != nil {
		return nil, "", fmt.Errorf("build transcription form: %w", err)
	}
	return buf.Bytes(), w.FormDataContentType(), nil
}

// filename names the upload so the service can tell the container from the extension.
func filename(contentType string) string {
	base, _, err := mime.ParseMediaType(contentType)
	if err != nil {
		base = strings.ToLower(strings.TrimSpace(contentType))
	}
	switch base {
	case "audio/mp4", "audio/m4a", "audio/x-m4a":
		return "audio.m4a"
	case "audio/webm":
		return "audio.webm"
	case "audio/mpeg", "audio/mp3":
		return "audio.mp3"
	case "audio/wav", "audio/x-wav":
		return "audio.wav"
	}
	return "audio.ogg"
}
