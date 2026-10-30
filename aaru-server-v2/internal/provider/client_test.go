package provider

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type sleepLog struct {
	mu     sync.Mutex
	values []time.Duration
}

func (s *sleepLog) sleep(_ context.Context, d time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.values = append(s.values, d)
	return nil
}

func testClient(t TransportFunc, sleeps *sleepLog) *Client {
	c := NewClient("test", t, NewPacer(1000, 100))
	if sleeps == nil {
		sleeps = &sleepLog{}
	}
	c.Sleep = sleeps.sleep
	return c
}

func respond(status int, body string, header ...string) *Response {
	h := http.Header{}
	for i := 0; i+1 < len(header); i += 2 {
		h.Set(header[i], header[i+1])
	}
	return &Response{Status: status, Body: []byte(body), Header: h}
}

func counting(calls *atomic.Int32, f func(n int32) *Response) TransportFunc {
	return func(context.Context, Request) (*Response, error) {
		return f(calls.Add(1) - 1), nil
	}
}

func TestRetriesRateLimitsWithBackoff(t *testing.T) {
	var calls atomic.Int32
	sleeps := &sleepLog{}
	body, err := testClient(counting(&calls, func(n int32) *Response {
		if n < 2 {
			return respond(429, "")
		}
		return respond(200, "ok")
	}), sleeps).Data(context.Background(), Request{URL: "https://provider.test/x"})
	require.NoError(t, err)
	assert.Equal(t, "ok", string(body))
	assert.Equal(t, int32(3), calls.Load())
	assert.Equal(t, []time.Duration{250 * time.Millisecond, 500 * time.Millisecond}, sleeps.values)
}

func TestGivesUpAfterThreeAttemptsAndNever404(t *testing.T) {
	var calls atomic.Int32
	_, err := testClient(counting(&calls, func(int32) *Response { return respond(503, "") }), nil).
		Data(context.Background(), Request{URL: "x"})
	assert.ErrorIs(t, err, NewError("test", KindUnavailable))
	assert.Equal(t, int32(3), calls.Load())

	var missing atomic.Int32
	_, err = testClient(counting(&missing, func(int32) *Response { return respond(404, "") }), nil).
		Data(context.Background(), Request{URL: "x"})
	assert.ErrorIs(t, err, NewError("test", KindNotFound))
	assert.Equal(t, int32(1), missing.Load())
}

func TestHonoursRetryAfter(t *testing.T) {
	var calls atomic.Int32
	sleeps := &sleepLog{}
	_, err := testClient(counting(&calls, func(n int32) *Response {
		if n < 1 {
			return respond(429, "", "retry-after", "7")
		}
		return respond(200, "ok")
	}), sleeps).Data(context.Background(), Request{URL: "x"})
	require.NoError(t, err)
	assert.Equal(t, []time.Duration{7 * time.Second}, sleeps.values)

	var long atomic.Int32
	_, err = testClient(counting(&long, func(int32) *Response { return respond(429, "", "Retry-After", "3600") }), nil).
		Data(context.Background(), Request{URL: "x"})
	assert.ErrorIs(t, err, NewError("test", KindUnavailable))
	assert.Equal(t, int32(1), long.Load())

	var refused atomic.Int32
	_, err = testClient(counting(&refused, func(int32) *Response { return respond(420, "") }), nil).
		Data(context.Background(), Request{URL: "x"})
	assert.ErrorIs(t, err, &Error{Provider: "test", Kind: KindRefused, Status: 420})
	assert.Equal(t, int32(1), refused.Load())

	_, err = testClient(func(context.Context, Request) (*Response, error) { return respond(401, ""), nil }, nil).
		Data(context.Background(), Request{URL: "x"})
	assert.ErrorIs(t, err, NewError("test", KindUnauthorized))
}

func TestCancellationPropagates(t *testing.T) {
	started := make(chan struct{})
	cancelled := make(chan struct{})
	client := NewClient("test", TransportFunc(func(ctx context.Context, _ Request) (*Response, error) {
		close(started)
		<-ctx.Done()
		close(cancelled)
		return nil, ctx.Err()
	}), NewPacer(10, 1))
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error)
	go func() {
		_, err := client.Data(ctx, Request{URL: "x"})
		done <- err
	}()
	<-started
	cancel()
	assert.ErrorIs(t, <-done, context.Canceled)
	<-cancelled
}

func TestClassifyRunsFirst(t *testing.T) {
	c := testClient(func(context.Context, Request) (*Response, error) { return respond(403, "x"), nil }, nil)
	c.Classify = func(*Response) (ErrorKind, bool) { return KindUnavailable, true }
	_, err := c.Data(context.Background(), Request{URL: "x"})
	assert.ErrorIs(t, err, NewError("test", KindUnavailable))
}

func TestHTTPTransportAgainstAServer(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ua" {
			assert.Equal(t, "Aaru test", r.Header.Get("User-Agent"))
		}
		w.Header().Set("X-Pagination-Page-Count", "2")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer server.Close()
	client := NewClient("test", NewHTTPTransport(), NewPacer(100, 10))
	var body struct{ OK bool }
	require.NoError(t, client.DecodeJSON(context.Background(), Request{URL: server.URL + "/ua", Headers: [][2]string{{"User-Agent", "Aaru test"}}}, &body))
	assert.True(t, body.OK)

	small := &HTTPTransport{MaxBodyBytes: 4}
	_, err := small.Send(context.Background(), Request{URL: server.URL})
	assert.True(t, errors.Is(err, ErrBodyTooLarge))

	malformed := NewClient("tmdb", TransportFunc(func(context.Context, Request) (*Response, error) { return respond(200, "<html>"), nil }), nil)
	err = malformed.DecodeJSON(context.Background(), Request{URL: "x"}, &body)
	assert.ErrorIs(t, err, NewError("tmdb", KindMalformed))
}

func TestErrorRendersAsProviderUnavailable(t *testing.T) {
	app := NewError("openlibrary", KindNotFound).AppError()
	assert.Equal(t, http.StatusBadGateway, app.Status)
	assert.Equal(t, "provider_unavailable", app.Code)
	assert.Equal(t, "Open Library is unavailable right now. Try again later.", app.Message)
	assert.Equal(t, map[string]string{"provider": "openlibrary"}, app.Details)
	assert.Equal(t, "musicbrainz", NewError("musicbrainz", KindMalformed).DisplayName())
	assert.True(t, NewError("anilist", KindMalformed).IsAniListOutage())
	assert.False(t, NewError("anilist", KindNotFound).IsAniListOutage())
}

func TestJSONValue(t *testing.T) {
	v, err := EncodeJSONValue(map[string]any{"a": 1, "b": []string{"x"}})
	require.NoError(t, err)
	assert.InDelta(t, 1.0, JSONObject(v)["a"], 0)
	type input struct {
		A int `json:"a"`
	}
	got, err := DecodeJSONValue[input](v)
	require.NoError(t, err)
	assert.Equal(t, 1, got.A)
}
