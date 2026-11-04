package auth

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestJWKSLeaderDisconnectingDoesNotFailTheOthers(t *testing.T) {
	jwks := newStubJWKS(t, jwkFor(t, "kid", rsaKey(t)))
	cache := NewJWKSCacheWith(jwks.server.Client(), jwks.server.URL, 12*time.Hour, time.Minute)
	jwks.mu.Lock() // the provider is slow until released
	released := false
	release := func() {
		if !released {
			released = true
			jwks.mu.Unlock()
		}
	}
	t.Cleanup(release)

	leaderCtx, cancelLeader := context.WithCancel(context.Background())
	leader := make(chan error, 1)
	go func() {
		_, err := cache.key(leaderCtx, "kid")
		leader <- err
	}()
	require.Eventually(t, func() bool { return jwks.requests.Load() == 1 }, 5*time.Second, 5*time.Millisecond)
	follower := make(chan error, 1)
	go func() {
		_, err := cache.key(context.Background(), "kid")
		follower <- err
	}()
	cancelLeader()
	assert.ErrorIs(t, <-leader, context.Canceled)
	release()
	assert.NoError(t, <-follower, "the shared fetch outlived the caller that started it")
	assert.EqualValues(t, 1, jwks.requests.Load())
}

func TestJWKSFailedFetchBacksOffBeforeTryingAgain(t *testing.T) {
	jwks := newStubJWKS(t, jwkFor(t, "kid", rsaKey(t)))
	jwks.setStatus(http.StatusServiceUnavailable)
	clock := time.Now()
	cache := NewJWKSCacheWith(jwks.server.Client(), jwks.server.URL, 12*time.Hour, time.Minute)
	cache.now = func() time.Time { return clock }

	_, err := cache.key(context.Background(), "kid")
	require.ErrorIs(t, err, errProviderUnavailable)
	_, err = cache.key(context.Background(), "kid")
	require.ErrorIs(t, err, errProviderUnavailable, "fails at once inside the back-off")
	assert.EqualValues(t, 1, jwks.requests.Load())

	jwks.setStatus(http.StatusOK)
	clock = clock.Add(maxFailureBackoff)
	k, err := cache.key(context.Background(), "kid")
	require.NoError(t, err)
	assert.NotNil(t, k)
	assert.EqualValues(t, 2, jwks.requests.Load())
}
