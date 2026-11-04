package app

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/model"
	"log/slog"
	"net/url"
	"testing"

	"github.com/stretchr/testify/assert"
)

// A provider that is not a Streamer silently delivers a Chat turn's reply as one delta.
func TestTheWiredModelStreams(t *testing.T) {
	base, err := url.Parse("http://127.0.0.1:1")
	assert.NoError(t, err)
	provider := makeModel(&config.Anthropic{APIKey: "test", Model: "test", BaseURL: base}, slog.New(slog.DiscardHandler))
	_, streams := provider.(model.Streamer)
	assert.True(t, streams)
}
