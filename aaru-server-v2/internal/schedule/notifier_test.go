package schedule

import (
	"aaru-go-api/internal/push"
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAiringWorkerStopsOnCancel(t *testing.T) {
	w := NewAiringWorker(&push.AiringNotifier{}, nil)
	assert.Equal(t, AiringInterval, w.Interval)
	assert.Equal(t, "airing-notifier", w.Name())
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- w.Run(ctx) }()
	cancel()
	select {
	case err := <-done:
		require.NoError(t, err)
	case <-time.After(5 * time.Second):
		t.Fatal("the worker did not stop")
	}
}
