package httpapi

import (
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/sports"
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ShareTests+Limits.providerBudgets: share lookups that miss the cache stop at their own budget,
// not the whole provider's.
func TestShareLookupsStopAtTheirOwnBudget(t *testing.T) {
	co := newFakeConcerts()
	co.eventsByID["Z1"] = sampleConcert("Z1", "2026-11-02", nil)
	co.eventsByID["Z2"] = sampleConcert("Z2", "2026-11-03", nil)
	sp := sportsProvider()
	sp.events["1"] = sampleMatch("1", "a", "b", "", "2026-10-18T14:00:00Z", "", nil, nil)
	sp.events["2"] = sampleMatch("2", "c", "d", "", "2026-10-18T14:00:00Z", "", nil, nil)
	e := newSocialEnv(t, withConcerts(co), withSports(sp))
	ctx := context.Background()

	e.server.Concerts.ShareLookups = concerts.NewCallBudget(1)
	assert.NotNil(t, e.server.Concerts.Concert(ctx, "Z1"))
	assert.NotNil(t, e.server.Concerts.Concert(ctx, "Z1"), "a cached concert costs nothing")
	assert.Nil(t, e.server.Concerts.Concert(ctx, "Z2"), "over the share budget")
	assert.Equal(t, []string{"Z1"}, co.eventCalls)

	e.server.Sports.ShareLookups = ratelimit.New(1, time.Minute)
	first, err := e.server.Sports.PublicEvent(ctx, "1")
	require.NoError(t, err)
	second, err := e.server.Sports.PublicEvent(ctx, "2")
	require.NoError(t, err)
	assert.NotNil(t, first)
	assert.Nil(t, second, "over the share budget")

	assert.Equal(t, 1000, concerts.ShareCallsPerDay)
	assert.Equal(t, 20, sports.ShareCallsPerMinute)
}
