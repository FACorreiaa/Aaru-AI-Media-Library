package concerts

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/provider"
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

func quietCache[V any]() *Cache[V] {
	c := NewCache[V]()
	c.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	return c
}

func (c *Cache[V]) flights() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.inFlight)
}

func TestCacheSurvivesAPanickingFetch(t *testing.T) {
	cache := quietCache[int]()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	now := time.Now()
	_, ok := cache.Value(ctx, "k", now, func(context.Context) (int, error) { panic("boom") })
	assert.False(t, ok)
	require.NoError(t, ctx.Err(), "the caller was woken, not left waiting")
	assert.Zero(t, cache.flights())

	var calls atomic.Int32
	v, ok := cache.Value(ctx, "k", now.Add(cacheRetryAfter), func(context.Context) (int, error) {
		calls.Add(1)
		return 3, nil
	})
	assert.True(t, ok)
	assert.Equal(t, 3, v)
	assert.EqualValues(t, 1, calls.Load(), "a new fetch ran")
}

func TestDetachedFetchesAreBoundedAndDrain(t *testing.T) {
	cache := quietCache[int]()
	cache.FetchTimeout = 50 * time.Millisecond
	var running atomic.Int32
	gone, cancel := context.WithCancel(context.Background())
	cancel()
	for i := range 50 {
		_, ok := cache.Value(gone, "search:"+strconv.Itoa(i), time.Now(), func(ctx context.Context) (int, error) {
			running.Add(1)
			defer running.Add(-1)
			<-ctx.Done() // a provider that never answers
			return 0, ctx.Err()
		})
		assert.False(t, ok)
	}
	assert.Eventually(t, func() bool { return cache.flights() == 0 && running.Load() == 0 }, 5*time.Second, 10*time.Millisecond)
}

func TestCacheEvictsTheLeastRecentlyUsedInBatches(t *testing.T) {
	cache := quietCache[int]()
	now := time.Now()
	ctx := context.Background()
	fetch := func(context.Context) (int, error) { return 1, nil }
	for i := range cacheMaxEntries {
		cache.Value(ctx, strconv.Itoa(i), now, fetch)
	}
	cache.Value(ctx, "0", now, fetch) // used again: the newest use
	cache.Value(ctx, "extra", now, fetch)
	cache.mu.Lock()
	defer cache.mu.Unlock()
	assert.Len(t, cache.entries, cacheEvictTo)
	assert.Contains(t, cache.entries, "0")
	assert.Contains(t, cache.entries, "extra")
	assert.NotContains(t, cache.entries, "1")
}

func TestABudgetIsChargedPerHTTPAttempt(t *testing.T) {
	var calls atomic.Int32
	transport := provider.TransportFunc(func(context.Context, provider.Request) (*provider.Response, error) {
		calls.Add(1)
		return &provider.Response{Status: 503}, nil
	})
	client := provider.NewClient("ticketmaster", transport, provider.NewPacer(1000, 100))
	client.Sleep = func(context.Context, time.Duration) error { return nil }
	budget := NewCallBudget(5)
	tm := &Ticketmaster{Client: client, APIKey: "test-key", Budget: budget, BaseURL: "https://tm.test"}
	_, err := tm.Attractions(context.Background(), "Radiohead")
	require.Error(t, err)
	assert.EqualValues(t, 3, calls.Load())
	assert.Equal(t, 3, budget.used, "three attempts, three calls of the day")

	// Two left: the third attempt is refused by the budget, not sent.
	_, err = tm.Attractions(context.Background(), "Radiohead")
	assert.ErrorIs(t, err, provider.NewError("ticketmaster", provider.KindUnavailable))
	assert.EqualValues(t, 5, calls.Load())
	assert.False(t, budget.Has(time.Now()))
}

func TestConcertLookupsAreLimitedPerUser(t *testing.T) {
	s := NewService(nil, nil, nil)
	ana, kai := uuid.New(), uuid.New()
	for range LookupsPerMinute {
		require.NoError(t, s.AllowLookup(ana))
	}
	err := s.AllowLookup(ana)
	require.Error(t, err)
	require.NotNil(t, apperr.From(err))
	assert.Equal(t, http.StatusTooManyRequests, apperr.From(err).Status)
	assert.Equal(t, "rate_limited", apperr.From(err).Code)
	assert.NoError(t, s.AllowLookup(kai))
}
