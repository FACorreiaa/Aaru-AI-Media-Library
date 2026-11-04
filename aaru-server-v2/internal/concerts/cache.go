package concerts

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"runtime/debug"
	"sort"
	"strings"
	"sync"
	"time"
)

// Cache holds concert answers by key for six hours (Ticketmaster's terms allow short caching).
// A failed refresh serves the stale copy and is not retried for five minutes. Bounded: the
// least recently used entries go first. One fetch per key at a time; it runs detached from the
// caller, so one caller disconnecting does not cancel everyone's fetch, but it is bounded by
// FetchTimeout so a fetch nobody waits for still ends.
type Cache[V any] struct {
	// Log defaults to slog.Default().
	Log *slog.Logger
	// FetchTimeout bounds one fetch; zero means FetchTimeout.
	FetchTimeout time.Duration

	mu       sync.Mutex
	entries  map[string]*cacheEntry[V]
	failedAt map[string]time.Time
	inFlight map[string]*flight[V]
	// uses counts reads and writes; an entry's usedAt is the count at its last one.
	uses uint64
}

const (
	cacheTTL        = 6 * time.Hour
	cacheRetryAfter = 5 * time.Minute
	cacheMaxEntries = 500
	// cacheEvictTo is where a full cache is trimmed down to, so the sort runs once per many
	// inserts instead of on every one.
	cacheEvictTo = cacheMaxEntries * 9 / 10
	// FetchTimeout bounds one detached fetch.
	FetchTimeout = 30 * time.Second
)

// errFetchPanicked is a fetch that panicked: recorded as a failed fetch.
var errFetchPanicked = errors.New("concert fetch panicked")

type cacheEntry[V any] struct {
	value     V
	fetchedAt time.Time
	usedAt    uint64
}

type flight[V any] struct {
	done  chan struct{}
	value V
	err   error
}

// NewCache is an empty cache.
func NewCache[V any]() *Cache[V] {
	return &Cache[V]{
		entries: map[string]*cacheEntry[V]{}, failedAt: map[string]time.Time{}, inFlight: map[string]*flight[V]{},
	}
}

func (c *Cache[V]) log() *slog.Logger {
	if c.Log == nil {
		return slog.Default()
	}
	return c.Log
}

// Value is the fresh answer for key, fetching it when needed, or the stale copy when the fetch
// fails. ok is false when there is nothing to serve.
func (c *Cache[V]) Value(ctx context.Context, key string, now time.Time, fetch func(context.Context) (V, error)) (value V, ok bool) {
	c.mu.Lock()
	var cachedValue V
	cached, hasCached := c.entries[key]
	if hasCached {
		c.uses++
		cached.usedAt = c.uses
		cachedValue = cached.value
		if now.Sub(cached.fetchedAt) < cacheTTL {
			c.mu.Unlock()
			return cachedValue, true
		}
	}
	if failed, hasFailed := c.failedAt[key]; hasFailed && now.Sub(failed) < cacheRetryAfter {
		c.mu.Unlock()
		return cachedValue, hasCached
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
		return cachedValue, hasCached
	}
	if f.err == nil {
		return f.value, true
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if e, has := c.entries[key]; has {
		return e.value, true
	}
	return cachedValue, hasCached
}

func (c *Cache[V]) run(ctx context.Context, key string, now time.Time, f *flight[V], fetch func(context.Context) (V, error)) {
	// Registered before the fetch: a panicking fetch still settles the flight, so later
	// callers never wait on a flight that cannot finish.
	defer func() {
		if r := recover(); r != nil {
			c.log().Error("Recovered a panic", "where", "concert cache", "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
			var zero V
			f.value, f.err = zero, errFetchPanicked
		}
		c.settle(key, now, f)
	}()
	timeout := c.FetchTimeout
	if timeout <= 0 {
		timeout = FetchTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	f.value, f.err = fetch(ctx)
}

// settle records the flight's outcome and wakes its waiters.
func (c *Cache[V]) settle(key string, now time.Time, f *flight[V]) {
	c.mu.Lock()
	defer c.mu.Unlock()
	defer close(f.done)
	delete(c.inFlight, key)
	if f.err != nil {
		c.failedAt[key] = now
		// The key holds a location cell; the log names only the kind of query.
		query, _, _ := strings.Cut(key, ":")
		c.log().Warn("Concert list failed", "query", query, "error", f.err.Error())
		c.pruneFailures(now)
		return
	}
	delete(c.failedAt, key)
	c.uses++
	c.entries[key] = &cacheEntry[V]{value: f.value, fetchedAt: now, usedAt: c.uses}
	c.trim()
}

// pruneFailures forgets expired failures once there are more than entries allowed; the
// caller holds mu.
func (c *Cache[V]) pruneFailures(now time.Time) {
	if len(c.failedAt) <= cacheMaxEntries {
		return
	}
	for k, at := range c.failedAt {
		if now.Sub(at) >= cacheRetryAfter {
			delete(c.failedAt, k)
		}
	}
}

// trim evicts the least recently used entries down to cacheEvictTo once the cache is over
// cacheMaxEntries; the caller holds mu.
func (c *Cache[V]) trim() {
	if len(c.entries) <= cacheMaxEntries {
		return
	}
	keys := make([]string, 0, len(c.entries))
	for k := range c.entries {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(a, b int) bool { return c.entries[keys[a]].usedAt < c.entries[keys[b]].usedAt })
	for _, k := range keys[:len(keys)-cacheEvictTo] {
		delete(c.entries, k)
	}
}
