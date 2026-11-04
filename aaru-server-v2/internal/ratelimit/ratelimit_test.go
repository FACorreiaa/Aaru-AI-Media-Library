package ratelimit

import (
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestAKeyIsLimitedPerWindow(t *testing.T) {
	l := New(2, time.Minute)
	now := time.Now()
	assert.True(t, l.Allow("a", now))
	assert.True(t, l.Allow("a", now))
	assert.False(t, l.Allow("a", now))
	assert.True(t, l.Allow("b", now))
	assert.True(t, l.Allow("a", now.Add(time.Minute)))
}

// HTTP-007: above sweepAbove live keys, expired windows are swept at most once per window, not
// on every call.
func TestExpiredWindowsAreSweptAtMostOncePerWindow(t *testing.T) {
	l := New(1, time.Minute)
	start := time.Now()
	fill := func(prefix string, at time.Time) {
		for i := range sweepAbove + 1 {
			l.Allow(prefix+strconv.Itoa(i), at)
		}
	}
	fill("old-", start)
	// The first call over the threshold sweeps; nothing has expired yet.
	l.Allow("x", start.Add(time.Second))
	assert.Equal(t, start.Add(time.Second), l.swept)

	// A window later every old key has expired; this call sweeps them.
	later := start.Add(time.Minute + 2*time.Second)
	fill("new-", later)
	assert.Equal(t, later, l.swept, "swept once, by the first call a window after the last sweep")
	assert.LessOrEqual(t, len(l.windows), sweepAbove+2)

	// Within the same window no call sweeps again, however many keys there are.
	l.Allow("y", later.Add(30*time.Second))
	assert.Equal(t, later, l.swept)
}
