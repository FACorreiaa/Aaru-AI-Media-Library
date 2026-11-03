package sports

import (
	"aaru-go-api/internal/apperr"
	"context"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func quietCache() *Cache {
	c := NewCache()
	c.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	return c
}

func (c *Cache) flights() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.inFlight)
}

func TestCacheSurvivesAPanickingFetch(t *testing.T) {
	cache := quietCache()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	now := time.Now()
	_, ok := Value(ctx, cache, "event:1", time.Hour, now, func(context.Context) (*Event, error) { panic("boom") })
	assert.False(t, ok)
	require.NoError(t, ctx.Err(), "the caller was woken, not left waiting")
	assert.Zero(t, cache.flights())
	cache.Settle(ctx, []string{"event:1"}, time.Second)

	var calls atomic.Int32
	v, ok := Value(ctx, cache, "event:1", time.Hour, now.Add(cacheRetryAfter), func(context.Context) (string, error) {
		calls.Add(1)
		return "ok", nil
	})
	assert.True(t, ok)
	assert.Equal(t, "ok", v)
	assert.EqualValues(t, 1, calls.Load(), "a new fetch ran")
}

func TestDetachedFetchesAreBoundedAndDrain(t *testing.T) {
	cache := quietCache()
	cache.FetchTimeout = 50 * time.Millisecond
	var running atomic.Int32
	gone, cancel := context.WithCancel(context.Background())
	cancel()
	for i := range 50 {
		_, ok := Value(gone, cache, "search:team:"+strconv.Itoa(i), time.Hour, time.Now(), func(ctx context.Context) ([]Entity, error) {
			running.Add(1)
			defer running.Add(-1)
			<-ctx.Done() // a provider that never answers
			return nil, ctx.Err()
		})
		assert.False(t, ok)
	}
	assert.Eventually(t, func() bool { return cache.flights() == 0 && running.Load() == 0 }, 5*time.Second, 10*time.Millisecond)
}

func TestCacheEvictsTheLeastRecentlyUsedAndPrunesFailures(t *testing.T) {
	cache := quietCache()
	now := time.Now()
	ctx := context.Background()
	fetch := func(context.Context) (int, error) { return 1, nil }
	for i := range cacheMaxEntries {
		Value(ctx, cache, strconv.Itoa(i), time.Hour, now, fetch)
	}
	_, ok := Cached[int](cache, "0") // read again: the newest use
	require.True(t, ok)
	Value(ctx, cache, "extra", time.Hour, now, fetch)
	cache.mu.Lock()
	assert.Len(t, cache.entries, cacheEvictTo)
	assert.Contains(t, cache.entries, "0")
	assert.Contains(t, cache.entries, "extra")
	assert.NotContains(t, cache.entries, "1")
	cache.mu.Unlock()

	fail := func(context.Context) (int, error) { return 0, context.DeadlineExceeded }
	for i := range cacheMaxEntries {
		Value(ctx, cache, "bad:"+strconv.Itoa(i), time.Hour, now, fail)
	}
	later := now.Add(cacheRetryAfter)
	Value(ctx, cache, "bad:last", time.Hour, later, fail)
	cache.mu.Lock()
	defer cache.mu.Unlock()
	assert.Len(t, cache.failedAt, 1, "expired failures are pruned")
}

func TestSportsLookupsAreLimitedPerUser(t *testing.T) {
	s := NewService(nil, nil)
	ana, kai := uuid.New(), uuid.New()
	for range SearchesPerMinute {
		require.NoError(t, s.AllowSearch(ana))
	}
	err := s.AllowSearch(ana)
	require.NotNil(t, apperr.From(err))
	assert.Equal(t, http.StatusTooManyRequests, apperr.From(err).Status)
	assert.NoError(t, s.AllowSearch(kai))
	for range EventsPerMinute {
		require.NoError(t, s.AllowEvent(ana))
	}
	assert.Error(t, s.AllowEvent(ana))
}
