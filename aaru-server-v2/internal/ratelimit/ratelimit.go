// Package ratelimit is the in-process fixed-window counter the Swift server
// used (FixedWindowRateLimiter). The API runs one replica (see the infra
// values); move to Valkey when that changes.
package ratelimit

import (
	"sync"
	"time"
)

type window struct {
	start time.Time
	count int
}

// FixedWindow counts attempts per key in fixed windows.
type FixedWindow struct {
	limit   int
	window  time.Duration
	mu      sync.Mutex
	windows map[string]window
}

// New allows limit attempts per key per window.
func New(limit int, w time.Duration) *FixedWindow {
	return &FixedWindow{limit: limit, window: w, windows: map[string]window{}}
}

// Allow records one attempt for key and reports whether it is within the limit.
func (l *FixedWindow) Allow(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.windows) > 10000 {
		for k, e := range l.windows {
			if now.Sub(e.start) >= l.window {
				delete(l.windows, k)
			}
		}
	}
	entry, ok := l.windows[key]
	if !ok || now.Sub(entry.start) >= l.window {
		entry = window{start: now}
	}
	entry.count++
	l.windows[key] = entry
	return entry.count <= l.limit
}
