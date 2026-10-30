package concerts

import (
	"context"
	"log/slog"
	"sort"
	"strings"
	"sync"
	"time"
)

// Cache holds concert answers by key for six hours (Ticketmaster's terms allow short caching).
// A failed refresh serves the stale copy and is not retried for five minutes. Bounded: the
// oldest entries go first. One fetch per key at a time; it runs detached from the caller, so
// one caller disconnecting does not cancel everyone's fetch.
type Cache[V any] struct {
	// Log defaults to slog.Default().
	Log *slog.Logger

	mu       sync.Mutex
	entries  map[string]cacheEntry[V]
	failedAt map[string]time.Time
	inFlight map[string]*flight[V]
}

const (
	cacheTTL        = 6 * time.Hour
	cacheRetryAfter = 5 * time.Minute
	cacheMaxEntries = 500
)

type cacheEntry[V any] struct {
	value     V
	fetchedAt time.Time
}

type flight[V any] struct {
	done  chan struct{}
	value V
	err   error
}

// NewCache is an empty cache.
func NewCache[V any]() *Cache[V] {
	return &Cache[V]{
		entries: map[string]cacheEntry[V]{}, failedAt: map[string]time.Time{}, inFlight: map[string]*flight[V]{},
	}
}

// Value is the fresh answer for key, fetching it when needed, or the stale copy when the fetch
// fails. ok is false when there is nothing to serve.
func (c *Cache[V]) Value(ctx context.Context, key string, now time.Time, fetch func(context.Context) (V, error)) (value V, ok bool) {
	c.mu.Lock()
	cached, hasCached := c.entries[key]
	if hasCached && now.Sub(cached.fetchedAt) < cacheTTL {
		c.mu.Unlock()
		return cached.value, true
	}
	if failed, hasFailed := c.failedAt[key]; hasFailed && now.Sub(failed) < cacheRetryAfter {
		c.mu.Unlock()
		return cached.value, hasCached
	}
	f, running := c.inFlight[key]
	if !running {
		f = &flight[V]{done: make(chan struct{})}
		c.inFlight[key] = f
		go c.run(context.WithoutCancel(ctx), key, now, f, fetch)
	}
	c.mu.Unlock()

	select {
	case <-f.done:
	case <-ctx.Done():
		return cached.value, hasCached
	}
	if f.err == nil {
		return f.value, true
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if e, has := c.entries[key]; has {
		return e.value, true
	}
	return cached.value, hasCached
}

func (c *Cache[V]) run(ctx context.Context, key string, now time.Time, f *flight[V], fetch func(context.Context) (V, error)) {
	defer close(f.done)
	f.value, f.err = fetch(ctx)
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.inFlight, key)
	if f.err != nil {
		c.failedAt[key] = now
		log := c.Log
		if log == nil {
			log = slog.Default()
		}
		// The key holds a location cell; the log names only the kind of query.
		query, _, _ := strings.Cut(key, ":")
		log.Warn("Concert list failed", "query", query, "error", f.err.Error())
		return
	}
	delete(c.failedAt, key)
	c.entries[key] = cacheEntry[V]{value: f.value, fetchedAt: now}
	c.trim(now)
}

func (c *Cache[V]) trim(now time.Time) {
	for k, at := range c.failedAt {
		if now.Sub(at) >= cacheRetryAfter {
			delete(c.failedAt, k)
		}
	}
	if len(c.entries) <= cacheMaxEntries {
		return
	}
	keys := make([]string, 0, len(c.entries))
	for k := range c.entries {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(a, b int) bool { return c.entries[keys[a]].fetchedAt.Before(c.entries[keys[b]].fetchedAt) })
	for _, k := range keys[:len(keys)-cacheMaxEntries] {
		delete(c.entries, k)
	}
}
