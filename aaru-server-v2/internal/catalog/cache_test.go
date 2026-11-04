package catalog

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func quietCache[K comparable, V any](capacity int) *sharedCache[K, V] {
	c := newSharedCache[K, V](capacity, "test")
	c.log = slog.New(slog.NewTextHandler(io.Discard, nil))
	return c
}

func TestSharedCacheSurvivesAPanickingFetch(t *testing.T) {
	cache := quietCache[string, int](10)
	ttl := func(int) time.Duration { return time.Hour }
	now := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, ok := cache.get(ctx, "k", now, ttl, func(context.Context) (int, error) { panic("boom") })
	assert.False(t, ok)
	require.NoError(t, ctx.Err(), "the caller was woken, not left waiting")
	cache.mu.Lock()
	assert.Empty(t, cache.inFlight)
	cache.mu.Unlock()

	// After the retry window a new fetch runs and answers.
	var calls atomic.Int32
	v, ok := cache.get(ctx, "k", now.Add(DiscoverRetryAfter), ttl, func(context.Context) (int, error) {
		calls.Add(1)
		return 7, nil
	})
	assert.True(t, ok)
	assert.Equal(t, 7, v)
	assert.EqualValues(t, 1, calls.Load())
}

func TestSharedCacheDetachedFetchIsBounded(t *testing.T) {
	cache := quietCache[string, int](10)
	cache.timeout = 50 * time.Millisecond
	ttl := func(int) time.Duration { return time.Hour }
	ended := make(chan error, 1)
	caller, cancel := context.WithCancel(context.Background())
	cancel() // the caller is gone before the fetch ends
	_, ok := cache.get(caller, "k", time.Now(), ttl, func(ctx context.Context) (int, error) {
		<-ctx.Done()
		ended <- ctx.Err()
		return 0, ctx.Err()
	})
	assert.False(t, ok)
	select {
	case err := <-ended:
		assert.True(t, errors.Is(err, context.DeadlineExceeded))
	case <-time.After(5 * time.Second):
		t.Fatal("the detached fetch never ended")
	}
	assert.Eventually(t, func() bool {
		cache.mu.Lock()
		defer cache.mu.Unlock()
		return len(cache.inFlight) == 0
	}, 5*time.Second, 10*time.Millisecond)
}

func TestOnAirCacheSurvivesAPanickingFetch(t *testing.T) {
	cache := &onAirCache{log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	now := time.Now()
	refine := func(_ context.Context, shows []OnAirShow) []OnAirShow { return shows }
	got := cache.shows(ctx, now, func(context.Context) ([]OnAirShow, error) { panic("boom") }, refine)
	assert.Nil(t, got)
	require.NoError(t, ctx.Err(), "the caller was woken, not left waiting")

	got = cache.shows(ctx, now.Add(DiscoverRetryAfter), func(context.Context) ([]OnAirShow, error) {
		return []OnAirShow{{}}, nil
	}, func(context.Context, []OnAirShow) []OnAirShow { panic("refine boom") })
	require.NotNil(t, got)
	assert.Len(t, got.shows, 1)
}

func TestWithinSurvivesAPanickingOp(t *testing.T) {
	_, err := Within(context.Background(), time.Second, "anilist", func(context.Context) (int, error) { panic("boom") })
	assert.ErrorIs(t, err, errFetchPanicked)
}
