package sports

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

// Cache is SPT-001's sports answers by key, each with its own freshness (livescores 90 s, a
// schedule 30 min, a team a day). Shared by every user: two fans of one team cost one call. A
// failed refresh keeps the stale copy and is not retried for a minute. Fetches are detached on
// purpose: a caller giving up (a deadline, a disconnect) never cancels them, so the next request
// finds the answer; FetchTimeout still bounds each one. Bounded: the least recently used entries
// go first.
type Cache struct {
	// Log defaults to slog.Default().
	Log *slog.Logger
	// FetchTimeout bounds one fetch; zero means FetchTimeout.
	FetchTimeout time.Duration

	mu       sync.Mutex
	entries  map[string]*cacheEntry
	failedAt map[string]time.Time
	inFlight map[string]*flight
	// uses counts reads and writes; an entry's usedAt is the count at its last one.
	uses uint64
}

const (
	cacheRetryAfter = time.Minute
	cacheMaxEntries = 3000
	// cacheEvictTo is where a full cache is trimmed down to, so the sort runs once per many
	// inserts instead of on every one.
	cacheEvictTo = cacheMaxEntries * 9 / 10
	// FetchTimeout bounds one detached fetch.
	FetchTimeout = 30 * time.Second
)

// errFetchPanicked is a fetch that panicked: recorded as a failed fetch.
var errFetchPanicked = errors.New("sports fetch panicked")

type cacheEntry struct {
	value     any
	fetchedAt time.Time
	ttl       time.Duration
	usedAt    uint64
}

type flight struct {
	done  chan struct{}
	value any
	err   error
}

// NewCache is an empty cache.
func NewCache() *Cache {
	return &Cache{entries: map[string]*cacheEntry{}, failedAt: map[string]time.Time{}, inFlight: map[string]*flight{}}
}

func (c *Cache) log() *slog.Logger {
	if c.Log == nil {
		return slog.Default()
	}
	return c.Log
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
	// Registered before the fetch: a panicking fetch still settles the flight, so later
	// callers (and Settle) never wait on a flight that cannot finish.
	defer func() {
		if r := recover(); r != nil {
			c.log().Error("Recovered a panic", "where", "sports cache", "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
			f.value, f.err = nil, errFetchPanicked
		}
		c.settle(key, ttl, now, f)
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
func (c *Cache) settle(key string, ttl time.Duration, now time.Time, f *flight) {
	c.mu.Lock()
	defer c.mu.Unlock()
	defer close(f.done)
	delete(c.inFlight, key)
	if f.err != nil {
		c.failedAt[key] = now
		query, _, _ := strings.Cut(key, ":")
		c.log().Warn("Sports lookup failed", "query", query, "error", f.err.Error())
		c.pruneFailures(now)
		return
	}
	delete(c.failedAt, key)
	c.uses++
	c.entries[key] = &cacheEntry{value: f.value, fetchedAt: now, ttl: ttl, usedAt: c.uses}
	c.trim()
}

// pruneFailures forgets expired failures once there are more than entries allowed, so failing
// keys (an unknown id, a provider outage) cannot grow the map without bound; the caller holds mu.
func (c *Cache) pruneFailures(now time.Time) {
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
func (c *Cache) trim() {
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
	if !ok {
		return nil, false
	}
	c.uses++
	e.usedAt = c.uses
	return e.value, true
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

// logPanic logs (and stops) a panic; use it as `defer logPanic(where)` in a spawned goroutine.
func logPanic(where string) {
	if r := recover(); r != nil {
		slog.Default().Error("Recovered a panic", "where", where, "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
	}
}

// goSafe runs f on its own goroutine, logging (not crashing on) a panic. recovered runs after a
// panic, before the goroutine ends, so a waiter is never left hanging.
func goSafe(where string, f func(), recovered func()) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				slog.Default().Error("Recovered a panic", "where", where, "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
				if recovered != nil {
					recovered()
				}
			}
		}()
		f()
	}()
}
