package httpapi

import (
	"aaru-go-api/internal/telemetry"
	"encoding/json"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// InternalMetricsTests.swift: `GET /internal/metrics`, the user count facorreia.com/apps reads.

const internalMetricsSecretG6 = "shared-secret"

func internalMetricsHarnessG6(t *testing.T, secret string) *harness {
	t.Helper()
	return newHarness(t, func(d *Deps) { d.Config.MetricsSecret = secret })
}

// count
func TestInternalMetricsTheRightBearerGetsTheNumberOfAccounts(t *testing.T) {
	h := internalMetricsHarnessG6(t, internalMetricsSecretG6)
	h.signIn()
	rec := h.do(http.MethodGet, "/internal/metrics", internalMetricsSecretG6, nil)
	require.Equal(t, http.StatusOK, rec.Code)
	assert.Equal(t, "no-store", rec.Header().Get("Cache-Control"))
	var body map[string]any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	assert.Len(t, body, 1)
	assert.GreaterOrEqual(t, body["users"], 1.0)
}

// rejected (all four arguments)
func TestInternalMetricsNoWrongOrBareSecretIs401(t *testing.T) {
	h := internalMetricsHarnessG6(t, internalMetricsSecretG6)
	for _, authorization := range []string{"", "Bearer not-the-secret", "Bearer shared-secreT", "shared-secret"} {
		headers := map[string]string{}
		if authorization != "" {
			headers["Authorization"] = authorization
		}
		assert.Equal(t, http.StatusUnauthorized, h.send(http.MethodGet, "/internal/metrics", headers, "").Code, authorization)
	}
}

// sessionToken
func TestInternalMetricsASessionTokenIsNotTheSecret(t *testing.T) {
	h := internalMetricsHarnessG6(t, internalMetricsSecretG6)
	_, bearer := h.signIn()
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/internal/metrics", bearer, nil).Code)
}

// disabled
func TestInternalMetricsAnEmptySecretTurnsTheRouteOff(t *testing.T) {
	h := internalMetricsHarnessG6(t, "")
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/internal/metrics", "anything", nil).Code)
}

// MetricsTests.swift notOnTheAPI: the API port has no /metrics; it is reachable from the internet.
func TestTheAPIPortHasNoMetrics(t *testing.T) {
	h := newHarness(t)
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/metrics", "", nil).Code)
}

// TelemetryTests.swift events: creating a list counts the list and the library action, after the write.

type capturedG6 struct {
	event      telemetry.Event
	properties map[string]string
}

// recordingSinkG6 keeps what was captured, per account.
type recordingSinkG6 struct {
	mu       sync.Mutex
	captured map[uuid.UUID][]capturedG6
}

func (r *recordingSinkG6) Capture(event telemetry.Event, user uuid.UUID, properties map[string]string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.captured[user] = append(r.captured[user], capturedG6{event, properties})
}

func (r *recordingSinkG6) events(user uuid.UUID) []capturedG6 {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]capturedG6(nil), r.captured[user]...)
}

func TestCreatingAListCountsTheListAndTheLibraryAction(t *testing.T) {
	sink := &recordingSinkG6{captured: map[uuid.UUID][]capturedG6{}}
	telemetry.Install(sink)
	defer telemetry.Install(nil)
	e := newLibEnv(t)
	user := e.user
	rec := e.send(http.MethodPost, "/v1/lists", map[string]any{"name": "Weekend"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())

	events := sink.events(user)
	var listCreated, libraryAction bool
	for _, e := range events {
		if e.event == telemetry.ListCreated && len(e.properties) == 0 {
			listCreated = true
		}
		if e.event == telemetry.LibraryAction && assert.ObjectsAreEqual(map[string]string{"kind": "list", "actor": "user"}, e.properties) {
			libraryAction = true
		}
		for _, v := range e.properties {
			assert.NotEqual(t, "Weekend", v, "no names leave the server")
		}
	}
	assert.True(t, listCreated, "%v", events)
	assert.True(t, libraryAction, "%v", events)
}
