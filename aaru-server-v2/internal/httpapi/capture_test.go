package httpapi

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AG-006 · capture as an import source: links by id, text and images through the model, the
// monthly quota, and nothing written before the plan is approved (CaptureTests).

// captureCatalog is the library fake plus name search (FakeCatalog.stubSearch).
type captureCatalog struct {
	*libraryFake
	searchMu sync.Mutex
	hits     map[string][]catalog.Hit
}

func (c *captureCatalog) Search(_ context.Context, query string, mediaType core.MediaType) ([]catalog.Hit, error) {
	c.searchMu.Lock()
	defer c.searchMu.Unlock()
	var out []catalog.Hit
	for name, hits := range c.hits {
		if strings.HasPrefix(query, name) {
			for _, h := range hits {
				if h.Type == mediaType {
					out = append(out, h)
				}
			}
		}
	}
	return out, nil
}

// captureModel answers each call with the next scripted response (ScriptedModel).
type captureModel struct {
	mu        sync.Mutex
	responses []model.Response
	requests  []model.Request
}

func (m *captureModel) Model() string { return "stub" }

func (m *captureModel) Pricing() model.Pricing {
	return model.Pricing{InputPerMTok: 0.10, OutputPerMTok: 0.50}
}

func (m *captureModel) Complete(_ context.Context, req model.Request) (model.Response, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requests = append(m.requests, req)
	if len(m.responses) == 0 {
		return model.Response{}, &model.ProviderError{Status: 500}
	}
	r := m.responses[0]
	m.responses = m.responses[1:]
	return r, nil
}

// captureReport is the model calling report_titles with these films.
func captureReport(titles ...[2]any) model.Response {
	items := []map[string]any{}
	for _, t := range titles {
		item := map[string]any{"title": t[0], "type": "movie"}
		if t[1] != nil {
			item["year"] = t[1]
		}
		items = append(items, item)
	}
	block, err := json.Marshal(map[string]any{
		"type": "tool_use", "id": "toolu_1", "name": capture.ToolName, "input": map[string]any{"titles": items},
	})
	if err != nil {
		panic(err)
	}
	return model.Response{Content: []model.Block{block}, Stop: model.StopToolUse, InputTokens: 1500, OutputTokens: 101}
}

// captureUsage records the metered calls (stores.agent.recordUsage).
type captureUsage struct {
	mu    sync.Mutex
	calls []int
}

func (u *captureUsage) RecordUsage(_ context.Context, _ uuid.UUID, _ time.Time, _, _, costMicros int) error {
	u.mu.Lock()
	defer u.mu.Unlock()
	u.calls = append(u.calls, costMicros)
	return nil
}

type captureEnv struct {
	*libEnv
	search *captureCatalog
}

func newCaptureEnv(t *testing.T, m model.Provider, usage capture.UsageRecorder) *captureEnv {
	t.Helper()
	fake := &libraryFake{episodes: map[string]catalog.Episodes{}}
	search := &captureCatalog{libraryFake: fake, hits: map[string][]catalog.Hit{}}
	providers := catalog.Providers{TMDB: search, AniList: fake, OpenLibrary: fake, Music: fake}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	h.server.Imports.Capture.Model = m
	h.server.Imports.Capture.Usage = usage
	user, bearer := h.signIn()
	return &captureEnv{libEnv: &libEnv{harness: h, fake: fake, user: user, bearer: bearer}, search: search}
}

// captureFilm is a film the fake catalog finds by name, and by its numeric TMDB id.
func (e *captureEnv) captureFilm(name string) string {
	tmdb := fmt.Sprint(rand.IntN(90_000_000) + 10_000_000)
	year, runtime := 2001, 100
	hit := catalog.Hit{Type: core.MediaMovie, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}}
	e.fake.stubTitle(catalog.Record{Hit: hit, RuntimeMinutes: &runtime})
	e.search.searchMu.Lock()
	e.search.hits[name] = []catalog.Hit{hit}
	e.search.searchMu.Unlock()
	return tmdb
}

func (e *captureEnv) captureInput(id string) *capture.Input {
	e.t.Helper()
	in, err := e.server.Imports.CaptureStore().Input(context.Background(), uuid.MustParse(id))
	require.NoError(e.t, err)
	return in
}

func captureCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	return decode[map[string]any](t, rec)["code"].(string)
}

func TestCapturePastedTitlesPlanWriteNothingThenApplyAsOneUndoableAction(t *testing.T) {
	name := fmt.Sprintf("Heat %d", rand.IntN(1_000_000))
	m := &captureModel{responses: []model.Response{captureReport([2]any{name, 2001}, [2]any{"Nobody Made This " + uuid.NewString(), nil})}}
	usage := &captureUsage{}
	env := newCaptureEnv(t, m, usage)
	env.captureFilm(name)

	rec := env.send("POST", "/v1/imports/capture", map[string]any{"text": name + " (2001)\nsomething else"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	created := decode[map[string]any](t, rec)
	assert.Equal(t, "capture", created["source"])
	id := created["id"].(string)
	assert.Equal(t, strings.ToUpper(id), id)
	assert.NotNil(t, env.captureInput(id))

	env.runImports()
	job, rows := env.importDetail(id)
	assert.Equal(t, "planned", job["state"])
	require.Len(t, rows, 2)
	assert.Equal(t, []any{"create", "unmatched"}, []any{rows[0]["outcome"], rows[1]["outcome"]})
	// Read once, then gone; the model was told it is data, and forced to report.
	assert.Nil(t, env.captureInput(id))
	require.Len(t, m.requests, 1)
	assert.Equal(t, capture.ToolName, m.requests[0].ToolChoice)
	assert.Equal(t, capture.System, m.requests[0].System)
	assert.Contains(t, string(m.requests[0].Turns[0].Content[0]), name)
	// Metered: one request, with its cost (150 + 50.5, rounded up).
	assert.Equal(t, []int{201}, usage.calls)
	// Nothing in the library until the plan is approved.
	assert.Empty(t, env.json("GET", "/v1/library/items", nil)["items"])

	applied := env.json("POST", "/v1/imports/"+id+"/apply", nil)
	action := applied["actionId"].(string)
	items := env.json("GET", "/v1/library/items", nil)["items"].([]any)
	require.Len(t, items, 1)
	assert.Equal(t, "wishlist", items[0].(map[string]any)["status"])
	assert.Equal(t, http.StatusOK, env.send("POST", "/v1/actions/"+action+"/undo", nil).Code)
}

func TestCaptureImageGoesToTheModelAsOneBase64BlockWithItsType(t *testing.T) {
	m := &captureModel{responses: []model.Response{captureReport([2]any{"Poster " + uuid.NewString(), nil})}}
	env := newCaptureEnv(t, m, nil)
	png := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3}
	id := env.uploadJob("/v1/imports/capture", "image/png", png)
	assert.Equal(t, "image", env.captureInput(id).Content.Kind())
	env.runImports()
	require.Len(t, m.requests, 1)
	var block struct {
		Type   string            `json:"type"`
		Source map[string]string `json:"source"`
	}
	require.NoError(t, json.Unmarshal(m.requests[0].Turns[0].Content[0], &block))
	assert.Equal(t, "image", block.Type)
	assert.Equal(t, "image/png", block.Source["media_type"])
	assert.Equal(t, base64.StdEncoding.EncodeToString(png), block.Source["data"])
}

func TestCaptureImageOver5MBIsRefusedAndOtherTypesAreUnreadable(t *testing.T) {
	env := newCaptureEnv(t, &captureModel{}, nil)
	rec := env.upload("/v1/imports/capture", "image/jpeg", bytes.Repeat([]byte{1}, 5*1024*1024+1))
	assert.Equal(t, 413, rec.Code)
	body := decode[map[string]any](t, rec)
	assert.Equal(t, "file_too_large", body["code"])
	assert.Equal(t, "That image is larger than 5 MB.", body["message"])
	assert.Equal(t, 415, env.upload("/v1/imports/capture", "text/plain", []byte("Heat")).Code)
}

func TestCaptureNothingFoundOrDeclinedFailsTheJobAndKeepsNothing(t *testing.T) {
	refusal := model.Response{Stop: model.StopRefusal}
	m := &captureModel{responses: []model.Response{captureReport(), refusal}}
	env := newCaptureEnv(t, m, nil)
	for _, want := range []string{
		"Aaru found no film, show, anime or book in that capture.", "Aaru could not read that capture.",
	} {
		rec := env.send("POST", "/v1/imports/capture", map[string]any{"text": "just a shopping list"})
		require.Equal(t, 202, rec.Code, rec.Body.String())
		id := decode[map[string]any](t, rec)["id"].(string)
		env.runImports()
		job, _ := env.importDetail(id)
		assert.Equal(t, "failed", job["state"])
		assert.Equal(t, want, job["errorSummary"])
		assert.Nil(t, env.captureInput(id))
	}
}

func TestCaptureLinksPlanWithoutTheModelAndOtherLinksAreRefused(t *testing.T) {
	env := newCaptureEnv(t, nil, nil)
	tmdb := env.captureFilm("Linked " + uuid.NewString())
	rec := env.send("POST", "/v1/imports/capture", map[string]any{"url": "https://www.themoviedb.org/movie/" + tmdb + "-linked"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	created := decode[map[string]any](t, rec)
	assert.EqualValues(t, 1, created["rowsTotal"])
	env.runImports()
	_, rows := env.importDetail(created["id"].(string))
	require.Len(t, rows, 1)
	assert.Equal(t, "create", rows[0]["outcome"])

	letterboxd := env.send("POST", "/v1/imports/capture", map[string]any{"url": "https://letterboxd.com/me/watchlist/"})
	assert.Equal(t, 422, letterboxd.Code)
	assert.Equal(t, "capture_use_csv", captureCode(t, letterboxd))
	other := env.send("POST", "/v1/imports/capture", map[string]any{"url": "https://example.com/film"})
	assert.Equal(t, "capture_unsupported_url", captureCode(t, other))
	// No model here: text cannot be read, and says so.
	text := env.send("POST", "/v1/imports/capture", map[string]any{"text": "Heat"})
	assert.Equal(t, 503, text.Code)
	assert.Equal(t, "capture_unavailable", captureCode(t, text))
	both := env.send("POST", "/v1/imports/capture", map[string]any{"text": "Heat", "url": "https://example.com"})
	assert.Equal(t, 422, both.Code)
	assert.Equal(t, "Send text or a link, not both.", decode[map[string]any](t, both)["message"])
	neither := env.send("POST", "/v1/imports/capture", map[string]any{})
	assert.Equal(t, 422, neither.Code)
}

func TestCaptureFreeAccountGetsThreeAMonthTheFourthIs402(t *testing.T) {
	env := newCaptureEnv(t, nil, nil)
	tmdb := env.captureFilm("Quota " + uuid.NewString())
	link := map[string]any{"url": "https://www.themoviedb.org/movie/" + tmdb}
	for range 3 {
		require.Equal(t, 202, env.send("POST", "/v1/imports/capture", link).Code)
	}
	refused := env.send("POST", "/v1/imports/capture", link)
	assert.Equal(t, 402, refused.Code)
	body := decode[map[string]any](t, refused)
	assert.Equal(t, "capture_quota", body["code"])
	now := time.Now().UTC()
	next := time.Date(now.Year(), now.Month()+1, 1, 0, 0, 0, 0, time.UTC)
	assert.Equal(t, "You have used this month's 3 captures. More come on "+next.Format("January 2")+
		", or Aaru Plus lifts the limit.", body["message"])
}

func TestCapturePlusLiftsTheMonthButKeepsThirtyADay(t *testing.T) {
	env := newCaptureEnv(t, nil, nil)
	ctx := context.Background()
	now := time.Now()
	_, err := env.pool.Exec(ctx, `INSERT INTO entitlements (original_transaction_id, user_id, product_id, environment,
		expires_at, signed_at, updated_at) VALUES ($1, $2, 'plus.monthly', 'Sandbox', $3, $4, $4)`,
		uuid.NewString(), env.user, now.Add(24*time.Hour), now)
	require.NoError(t, err)
	tmdb := env.captureFilm("Plus " + uuid.NewString())
	link := map[string]any{"url": "https://www.themoviedb.org/movie/" + tmdb}
	for range 30 {
		require.Equal(t, 202, env.send("POST", "/v1/imports/capture", link).Code)
	}
	refused := env.send("POST", "/v1/imports/capture", link)
	assert.Equal(t, 429, refused.Code)
	body := decode[map[string]any](t, refused)
	assert.Equal(t, "capture_fair_use", body["code"])
	assert.Equal(t, "Aaru reads 30 captures a day. More tomorrow.", body["message"])
}

func TestCaptureSweepDeletesInputsLeftAnHour(t *testing.T) {
	env := newCaptureEnv(t, nil, nil)
	ctx := context.Background()
	store := env.server.Imports.CaptureStore()
	old, fresh := uuid.New(), uuid.New()
	require.NoError(t, store.Save(ctx, capture.Input{
		JobID: old, UserID: env.user, Content: capture.Content{Text: "Heat"}, CreatedAt: time.Now().Add(-2 * time.Hour),
	}))
	require.NoError(t, store.Save(ctx, capture.Input{
		JobID: fresh, UserID: env.user, Content: capture.Content{Image: []byte{1, 2}, MediaType: "image/jpeg"}, CreatedAt: time.Now(),
	}))
	swept, err := store.Sweep(ctx, time.Now().Add(-capture.InputLifetime))
	require.NoError(t, err)
	assert.GreaterOrEqual(t, swept, 1)
	assert.Nil(t, env.captureInput(old.String()))
	kept := env.captureInput(fresh.String())
	require.NotNil(t, kept)
	assert.Equal(t, capture.Content{Image: []byte{1, 2}, MediaType: "image/jpeg"}, kept.Content)
}
