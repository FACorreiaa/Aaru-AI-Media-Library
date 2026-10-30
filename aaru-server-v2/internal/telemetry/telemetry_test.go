package telemetry

import (
	"aaru-go-api/internal/middleware"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testDSN = "https://publickey@o1.ingest.de.sentry.io/42"

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

func TestDSNBecomesTheEnvelopeEndpoint(t *testing.T) {
	for dsn, endpoint := range map[string]string{
		"":                                  "",
		"not a dsn":                         "",
		"https://o1.ingest.de.sentry.io/42": "",
		"https://publickey@o1.ingest.de.sentry.io/": "",
		testDSN:                      "https://o1.ingest.de.sentry.io/api/42/envelope/",
		"https://k@localhost:9000/7": "https://localhost:9000/api/7/envelope/",
	} {
		s := NewSentry(dsn, "test", nil, nil, quiet)
		if endpoint == "" {
			assert.Nil(t, s, dsn)
			continue
		}
		require.NotNil(t, s, dsn)
		assert.Equal(t, endpoint, s.Endpoint)
	}
}

// recorder is a stub HTTP endpoint keeping what it was sent.
type recorder struct {
	mu       sync.Mutex
	requests []*http.Request
	bodies   []string
}

func (r *recorder) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	data, _ := io.ReadAll(req.Body)
	r.mu.Lock()
	r.requests = append(r.requests, req)
	r.bodies = append(r.bodies, string(data))
	r.mu.Unlock()
	w.WriteHeader(http.StatusOK)
}

type leaky struct{}

func (leaky) Error() string { return "secret-text from the user" }

func TestServerErrorReachesSentryWithNothingFromTheRequest(t *testing.T) {
	rec := &recorder{}
	stub := httptest.NewServer(rec)
	defer stub.Close()
	release := "abc123"
	sentry := NewSentry("http://publickey@"+strings.TrimPrefix(stub.URL, "http://")+"/42", "test", &release, stub.Client(), quiet)
	require.NotNil(t, sentry)

	e := echo.New()
	e.Use(middleware.Errors(quiet, sentry))
	e.GET("/v1/titles/:id", func(echo.Context) error { return leaky{} })
	e.GET("/v1/missing", func(echo.Context) error { return echo.ErrNotFound })
	for _, path := range []string{"/v1/missing", "/v1/titles/0b6a2f63-id?q=private"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Header.Set("Authorization", "Bearer session-token")
		req.Header.Set("Cookie", "aaru_session=cookie")
		e.ServeHTTP(httptest.NewRecorder(), req)
	}
	sentry.Wait()

	require.Len(t, rec.requests, 1, "a 404 is not reported")
	sent := rec.requests[0]
	assert.Equal(t, "/api/42/envelope/", sent.URL.Path)
	assert.Equal(t, "application/x-sentry-envelope", sent.Header.Get("content-type"))
	assert.Contains(t, sent.Header.Get("x-sentry-auth"), "sentry_key=publickey")
	body := rec.bodies[0]
	for _, leak := range []string{"0b6a2f63", "private", "session-token", "cookie", "secret-text"} {
		assert.NotContains(t, body, leak, "%s left the server", leak)
	}
	lines := strings.Split(body, "\n")
	require.Len(t, lines, 3)
	assert.JSONEq(t, `{"type":"event"}`, lines[1])
	var event map[string]any
	require.NoError(t, json.Unmarshal([]byte(lines[2]), &event))
	assert.NotContains(t, event, "user")
	assert.NotContains(t, event, "request")
	assert.Equal(t, "abc123", event["release"])
	assert.Equal(t, "test", event["environment"])
	assert.Equal(t, "GET /v1/titles/{id}", event["transaction"])
	tags := event["tags"].(map[string]any)
	assert.Equal(t, "/v1/titles/{id}", tags["http.route"])
	assert.Equal(t, "500", tags["http.status_code"])
	assert.Equal(t, "internal", tags["code"])
	exception := event["exception"].(map[string]any)["values"].([]any)[0].(map[string]any)
	assert.Equal(t, "500 internal", exception["value"])
}

func TestPostHogGetsTheEventTheAccountAndOnlyTheAllowedProperties(t *testing.T) {
	rec := &recorder{}
	stub := httptest.NewServer(rec)
	defer stub.Close()
	host, _ := url.Parse(stub.URL)
	client := NewPostHog("phc_test", host, stub.Client(), quiet)
	user := uuid.New()
	client.Capture(AccountCreated, user, map[string]string{"provider": "apple"})
	client.Flush(context.Background())
	assert.Zero(t, client.Pending())

	require.Len(t, rec.requests, 1)
	assert.Equal(t, "/batch/", rec.requests[0].URL.Path)
	var body struct {
		APIKey string           `json:"api_key"`
		Batch  []map[string]any `json:"batch"`
	}
	require.NoError(t, json.Unmarshal([]byte(rec.bodies[0]), &body))
	assert.Equal(t, "phc_test", body.APIKey)
	require.Len(t, body.Batch, 1)
	event := body.Batch[0]
	assert.Equal(t, "account_created", event["event"])
	assert.Equal(t, strings.ToLower(user.String()), event["distinct_id"])
	_, err := time.Parse(time.RFC3339Nano, event["timestamp"].(string))
	require.NoError(t, err)
	assert.Equal(t, map[string]any{
		"provider": "apple", "$process_person_profile": false, "$geoip_disable": true, "$lib": "aaru-server",
	}, event["properties"])
}

func TestPostHogBatchesAndDrainsOnShutdown(t *testing.T) {
	rec := &recorder{}
	stub := httptest.NewServer(rec)
	defer stub.Close()
	host, _ := url.Parse(stub.URL)
	client := NewPostHog("phc_test", host, stub.Client(), quiet)
	for range 2100 {
		client.Capture(ListCreated, uuid.New(), nil)
	}
	assert.Equal(t, 2000, client.Pending(), "the queue holds at most 2000")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	require.NoError(t, client.Run(ctx))
	assert.Zero(t, client.Pending())
	assert.Len(t, rec.requests, 20, "batches of 100")
}

func TestCaptureGoesToTheInstalledSinkOnly(t *testing.T) {
	Capture(ListCreated, uuid.New(), nil) // nothing installed: a no-op
	sink := &countingSink{}
	Install(sink)
	defer Install(nil)
	Capture(ListCreated, uuid.New(), nil)
	assert.Equal(t, 1, sink.n)
	Install(nil)
	Capture(ListCreated, uuid.New(), nil)
	assert.Equal(t, 1, sink.n)
	var nilSentry *Sentry
	nilSentry.Report(middleware.Failure{})
	nilSentry.Wait()
}

type countingSink struct{ n int }

func (c *countingSink) Capture(Event, uuid.UUID, map[string]string) { c.n++ }
