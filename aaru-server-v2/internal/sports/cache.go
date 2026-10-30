package sports

import (
	"context"
	"log/slog"
	"sort"
	"strings"
	"sync"
	"time"
)

// Cache is SPT-001's sports answers by key, each with its own freshness (livescores 90 s, a
// schedule 30 min, a team a day). Shared by every user: two fans of one team cost one call. A
// failed refresh keeps the stale copy and is not retried for a minute. Fetches are detached on
// purpose: a caller giving up (a deadline, a disconnect) never cancels them, so the next request
// finds the answer. Bounded: the oldest entries go first.
type Cache struct {
	// Log defaults to slog.Default().
	Log *slog.Logger

	mu       sync.Mutex
	entries  map[string]cacheEntry
	failedAt map[string]time.Time
	inFlight map[string]*flight
}

const (
	cacheRetryAfter = time.Minute
	cacheMaxEntries = 3000
)

type cacheEntry struct {
	value     any
	fetchedAt time.Time
	ttl       time.Duration
}

type flight struct {
	done  chan struct{}
	value any
	err   error
}

// NewCache is an empty cache.
func NewCache() *Cache {
	return &Cache{entries: map[string]cacheEntry{}, failedAt: map[string]time.Time{}, inFlight: map[string]*flight{}}
}

// prime starts a fetch when the key is missing or expired, unless one is running or just
// failed. It returns the running fetch, if any.
func (c *Cache) prime(ctx context.Context, key string, ttl time.Duration, now time.Time, fetch func(context.Context) (any, error)) *flight {
	c.mu.Lock()
	defer c.mu.Unlock()
	if e, ok := c.entries[key]; ok && now.Sub(e.fetchedAt) < e.ttl {
		return nil
	}
	if running, ok := c.inFlight[key]; ok {
		return running
	}
	if failed, ok := c.failedAt[key]; ok && now.Sub(failed) < cacheRetryAfter {
		return nil
	}
	f := &flight{done: make(chan struct{})}
	c.inFlight[key] = f
	go c.run(context.WithoutCancel(ctx), key, ttl, now, f, fetch)
	return f
}

func (c *Cache) run(ctx context.Context, key string, ttl time.Duration, now time.Time, f *flight, fetch func(context.Context) (any, error)) {
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
		query, _, _ := strings.Cut(key, ":")
		log.Warn("Sports lookup failed", "query", query, "error", f.err.Error())
		return
	}
	delete(c.failedAt, key)
	c.entries[key] = cacheEntry{value: f.value, fetchedAt: now, ttl: ttl}
	c.trim()
}

func (c *Cache) trim() {
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

// Has is whether the key has ever been answered (stale counts).
func (c *Cache) Has(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	_, ok := c.entries[key]
	return ok
}

func (c *Cache) cachedAny(key string) (any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	return e.value, ok
}

// Settle waits until none of keys is being fetched, or timeout passes.
func (c *Cache) Settle(ctx context.Context, keys []string, timeout time.Duration) {
	c.mu.Lock()
	var waiting []*flight
	for _, k := range keys {
		if f, ok := c.inFlight[k]; ok {
			waiting = append(waiting, f)
		}
	}
	c.mu.Unlock()
	if len(waiting) == 0 {
		return
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	for _, f := range waiting {
		select {
		case <-f.done:
		case <-timer.C:
			return
		case <-ctx.Done():
			return
		}
	}
}

// Cached is whatever is held for the key, fresh or stale.
func Cached[T any](c *Cache, key string) (T, bool) {
	v, ok := c.cachedAny(key)
	if !ok {
		var zero T
		return zero, false
	}
	t, ok := v.(T)
	return t, ok
}

// Value is the fresh answer, fetching it if needed; a stale copy when the fetch fails.
func Value[T any](ctx context.Context, c *Cache, key string, ttl time.Duration, now time.Time, fetch func(context.Context) (T, error)) (T, bool) {
	f := c.prime(ctx, key, ttl, now, func(ctx context.Context) (any, error) { return fetch(ctx) })
	if f == nil {
		return Cached[T](c, key)
	}
	select {
	case <-f.done:
	case <-ctx.Done():
		return Cached[T](c, key)
	}
	if f.err == nil {
		if t, ok := f.value.(T); ok {
			return t, true
		}
	}
	return Cached[T](c, key)
}
