package catalog

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"runtime/debug"
	"sync"
	"time"
)

// FetchTimeout bounds one detached cache fetch: a fetch nobody waits for any more must
// still end, so it cannot hold a provider's pacer (and the next caller) forever.
const FetchTimeout = time.Minute

// errFetchPanicked is a fetch that panicked: the cache records it as a failure.
var errFetchPanicked = errors.New("cache fetch panicked")

// recovered turns a panic in a detached goroutine into an error, logging it with its
// stack; nil when there was none. Call it from a deferred function.
func recovered(log *slog.Logger, where string, r any) error {
	if r == nil {
		return nil
	}
	if log == nil {
		log = slog.Default()
	}
	log.Error("Recovered a panic", "where", where, "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
	return errFetchPanicked
}

// sharedCache is a list or page cache shared by every user. The API runs one
// replica, so memory is enough; a second replica would only fetch its own copy.
//
// Fresh values are served from memory; a stale or missing one is refetched once,
// shared by every concurrent caller. A failed refetch serves the stale copy (none
// when there is none) and is not retried for retryAfter.
type sharedCache[K comparable, V any] struct {
	mu       sync.Mutex
	entries  map[K]*cacheEntry[V]
	failedAt map[K]time.Time
	inFlight map[K]*flight[V]
	// capacity bounds the entries (0: unbounded); the least recently used go first.
	capacity   int
	retryAfter time.Duration
	// timeout bounds one fetch (FetchTimeout when zero).
	timeout time.Duration
	log     *slog.Logger
	failure string
}

type cacheEntry[V any] struct {
	value     V
	fetchedAt time.Time
	usedAt    time.Time
}

type flight[V any] struct {
	done  chan struct{}
	value V
	err   error
}

func newSharedCache[K comparable, V any](capacity int, failure string) *sharedCache[K, V] {
	return &sharedCache[K, V]{
		entries: map[K]*cacheEntry[V]{}, failedAt: map[K]time.Time{}, inFlight: map[K]*flight[V]{},
		capacity: capacity, retryAfter: DiscoverRetryAfter, failure: failure,
	}
}

// get is the cached value or a shared refetch; false when there is nothing to serve.
// ttl reads the freshness window for a value. The fetch runs detached from ctx: one
// caller disconnecting must not cancel everyone's fetch.
func (c *sharedCache[K, V]) get(
	ctx context.Context, key K, now time.Time, ttl func(V) time.Duration,
	fetch func(context.Context) (V, error),
) (V, bool) {
	c.mu.Lock()
	cached := c.entries[key]
	if cached != nil {
		cached.usedAt = now
		if now.Sub(cached.fetchedAt) < ttl(cached.value) {
			c.mu.Unlock()
			return cached.value, true
		}
	}
	if failed, ok := c.failedAt[key]; ok && now.Sub(failed) < c.retryAfter {
		c.mu.Unlock()
		return stale(cached)
	}
	f := c.inFlight[key]
	if f == nil {
		f = &flight[V]{done: make(chan struct{})}
		c.inFlight[key] = f
		go c.run(context.WithoutCancel(ctx), key, now, f, fetch)
	}
	c.mu.Unlock()
	select {
	case <-f.done:
	case <-ctx.Done():
		c.mu.Lock()
		defer c.mu.Unlock()
		return stale(c.entries[key])
	}
	if f.err == nil {
		return f.value, true
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if latest := c.entries[key]; latest != nil {
		return latest.value, true
	}
	return stale(cached)
}

func (c *sharedCache[K, V]) run(ctx context.Context, key K, now time.Time, f *flight[V], fetch func(context.Context) (V, error)) {
	// Registered before the fetch: a panicking fetch still settles the flight, so later
	// callers never wait on a flight that cannot finish.
	defer func() {
		if err := recovered(c.log, c.failure, recover()); err != nil {
			var zero V
			f.value, f.err = zero, err
		}
		c.settle(key, now, f)
	}()
	timeout := c.timeout
	if timeout <= 0 {
		timeout = FetchTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	f.value, f.err = fetch(ctx)
}

// settle records the flight's outcome and wakes its waiters.
func (c *sharedCache[K, V]) settle(key K, now time.Time, f *flight[V]) {
	c.mu.Lock()
	defer c.mu.Unlock()
	defer close(f.done)
	if c.inFlight[key] != f {
		return
	}
	delete(c.inFlight, key)
	if f.err != nil {
		c.failedAt[key] = now
		log := c.log
		if log == nil {
			log = slog.Default()
		}
		log.Warn(c.failure, "key", key, "error", f.err.Error())
		c.pruneFailures(now)
		return
	}
	delete(c.failedAt, key)
	c.entries[key] = &cacheEntry[V]{value: f.value, fetchedAt: now, usedAt: now}
	for c.capacity > 0 && len(c.entries) > c.capacity {
		var oldest K
		var oldestAt time.Time
		first := true
		for k, e := range c.entries {
			if first || e.usedAt.Before(oldestAt) {
				oldest, oldestAt, first = k, e.usedAt, false
			}
		}
		delete(c.entries, oldest)
	}
}

// pruneFailures forgets failures past retryAfter once there are more of them than entries
// allowed, so failing keys cannot grow the map for the life of the process.
func (c *sharedCache[K, V]) pruneFailures(now time.Time) {
	if c.capacity <= 0 || len(c.failedAt) <= c.capacity {
		return
	}
	for k, at := range c.failedAt {
		if now.Sub(at) >= c.retryAfter {
			delete(c.failedAt, k)
		}
	}
}

// stale is the entry's value, served past its window; false when there is none.
func stale[V any](e *cacheEntry[V]) (V, bool) {
	if e == nil {
		var zero V
		return zero, false
	}
	return e.value, true
}
