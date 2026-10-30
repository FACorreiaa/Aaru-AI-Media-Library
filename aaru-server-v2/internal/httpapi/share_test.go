package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/shares"
	"aaru-go-api/internal/social"
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ShareTests.swift, ShareTests+Limits.swift, ShareStoreTests.swift: share links (SHR-002).

type shared struct {
	handle, code, tmdb string
}

// shareArrival gives the harness user a handle and shares Arrival with a note.
func shareArrival(t *testing.T, e *libEnv, note *string) shared {
	t.Helper()
	mine := freshHandle()
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": mine, "displayName": "Fern"})
	tmdb := e.stubMovie("Arrival")
	body := map[string]any{"target": map[string]any{"kind": "title", "ref": film(tmdb)}}
	if note != nil {
		body["note"] = *note
	}
	created := e.send(http.MethodPost, "/v1/shares", body)
	require.Equal(t, http.StatusOK, created.Code, created.Body.String())
	return shared{handle: mine, code: decode[map[string]any](t, created)["code"].(string), tmdb: tmdb}
}

func watchThis() *string { s := "watch this"; return &s }

// sportsWith is a sports provider that knows these event ids.
func sportsWith(ids ...string) *fakeSports {
	f := sportsProvider()
	for _, id := range ids {
		f.events[id] = sampleMatch(id, "a"+id, "b"+id, "", "2026-10-18T14:00:00Z", "", nil, nil)
	}
	return f
}

func shareCode(t *testing.T, e *libEnv, body map[string]any) string {
	t.Helper()
	rec := e.send(http.MethodPost, "/v1/shares", body)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](t, rec)["code"].(string)
}

func TestAShareIsAReusableLinkThatShowsItsTitleSignedOut(t *testing.T) {
	e := newSocialEnv(t)
	code := shareArrival(t, e, watchThis()).code
	assert.Len(t, code, shares.CodeLength)
	again := e.send(http.MethodGet, "/v1/shares/"+code, nil, signedOut)
	require.Equal(t, http.StatusOK, again.Code, again.Body.String())
	preview := decode[map[string]any](t, again)
	assert.Equal(t, "title", preview["kind"])
	assert.Equal(t, false, preview["unavailable"])
	assert.Equal(t, "Arrival", preview["title"].(map[string]any)["title"])
	assert.Nil(t, preview["from"])
	assert.Nil(t, preview["libraryItemId"])
	assert.Nil(t, preview["status"])
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/shares/"+code, nil, signedOut).Code, "reusable")
}

func TestTheShareURLIsTheWebPage(t *testing.T) {
	e := newSocialEnv(t, withSports(sportsWith("42")))
	created := e.json(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "sport_event", "id": "42"}})
	assert.Equal(t, "https://aaruapp.com/s/"+created["code"].(string), created["url"])
}

func TestTheSameTargetAndNoteReuseOneLink(t *testing.T) {
	e := newSocialEnv(t, withSports(sportsWith("42")))
	target := map[string]any{"kind": "sport_event", "id": "42"}
	first := shareCode(t, e, map[string]any{"target": target, "note": "hi"})
	same := shareCode(t, e, map[string]any{"target": target, "note": "  hi "})
	other := shareCode(t, e, map[string]any{"target": target, "note": "yo"})
	bare := shareCode(t, e, map[string]any{"target": target})
	blank := shareCode(t, e, map[string]any{"target": target, "note": "   "})
	assert.Equal(t, first, same)
	assert.NotEqual(t, first, other)
	assert.NotEqual(t, first, bare)
	assert.Equal(t, bare, blank)
}

func TestAFriendSeesWhoSentItAndTheNoteAStrangerDoesNot(t *testing.T) {
	e := newSocialEnv(t)
	s := shareArrival(t, e, watchThis())
	ana := e.friendByRequest(s.handle)
	seen := decode[map[string]any](t, e.send(http.MethodGet, "/v1/shares/"+s.code, nil, ana.token))["from"].(map[string]any)
	assert.Equal(t, s.handle, seen["user"].(map[string]any)["handle"])
	assert.Equal(t, "watch this", seen["note"])

	kai := e.friendlyUser()
	assert.Nil(t, decode[map[string]any](t, e.send(http.MethodGet, "/v1/shares/"+s.code, nil, kai.token))["from"])
	// The sender sees their own name on their link.
	own := e.get("/v1/shares/" + s.code)["from"].(map[string]any)
	assert.Equal(t, s.handle, own["user"].(map[string]any)["handle"])
}

func TestABlockShowsTheContentAndHidesTheSender(t *testing.T) {
	e := newSocialEnv(t)
	s := shareArrival(t, e, watchThis())
	ana := e.friendByRequest(s.handle)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/social/blocks/"+strings.ToUpper(e.user.String()), nil, ana.token).Code)
	blocked := e.send(http.MethodGet, "/v1/shares/"+s.code, nil, ana.token)
	require.Equal(t, http.StatusOK, blocked.Code)
	body := decode[map[string]any](t, blocked)
	assert.Equal(t, "Arrival", body["title"].(map[string]any)["title"])
	assert.Nil(t, body["from"])
}

func TestASignedInOpenerWhoHasTheTitleGetsTheirItemAndStatus(t *testing.T) {
	e := newSocialEnv(t)
	s := shareArrival(t, e, watchThis())
	ana := e.friendlyUser()
	e.addItem("movie", s.tmdb, "wishlist", ana.token)
	preview := e.get("/v1/shares/"+s.code, ana.token)
	assert.IsType(t, "", preview["libraryItemId"])
	assert.Equal(t, "wishlist", preview["status"])
}

func TestASharedMatchShowsItsResultToAnyone(t *testing.T) {
	sp := sportsProvider()
	sp.events["42"] = sampleMatch("42", "133604", "133615", "", "2026-10-18T14:00:00Z", "", ip(2), ip(1))
	e := newSocialEnv(t, withSports(sp))
	code := shareCode(t, e, map[string]any{"target": map[string]any{"kind": "sport_event", "id": "42"}})
	preview := decode[map[string]any](t, e.send(http.MethodGet, "/v1/shares/"+code, nil, signedOut))
	assert.Equal(t, "sport_event", preview["kind"])
	event := preview["sportEvent"].(map[string]any)
	assert.InDelta(t, 2, event["home"].(map[string]any)["score"], 0)
	assert.InDelta(t, 1, event["away"].(map[string]any)["score"], 0)
	assert.Equal(t, false, preview["unavailable"])
}

func TestASharedConcertShowsOrSaysUnavailable(t *testing.T) {
	co := newFakeConcerts()
	co.eventsByID["Z1"] = sampleConcert("Z1", "2026-11-02", nil)
	e := newSocialEnv(t, withConcerts(co))
	first := shareCode(t, e, map[string]any{"target": map[string]any{"kind": "concert", "id": "Z1"}})
	shown := decode[map[string]any](t, e.send(http.MethodGet, "/v1/shares/"+first, nil, signedOut))
	assert.Equal(t, "Show Z1", shown["concert"].(map[string]any)["name"])

	// A link made while the concert existed; by the time it opens, Ticketmaster has none.
	second := social.NewCode()
	sender := e.user
	require.NoError(t, e.server.Shares.Save(context.Background(), shares.Share{
		Code: second, Sender: &sender, Target: shares.Target{Kind: shares.KindConcert, EventID: "Z2"}, CreatedAt: time.Now(),
	}))
	co.fail(true)
	gone := e.send(http.MethodGet, "/v1/shares/"+second, nil, signedOut)
	require.Equal(t, http.StatusOK, gone.Code)
	body := decode[map[string]any](t, gone)
	assert.Equal(t, true, body["unavailable"])
	assert.Nil(t, body["concert"])
}

func TestBadShareTargetsAndNotesAreRefused(t *testing.T) {
	e := newSocialEnv(t, withSports(sportsWith("42")))
	refused := []map[string]any{
		{"target": map[string]any{"kind": "sport_event", "id": "abc"}},
		{"target": map[string]any{"kind": "concert", "id": "../x"}},
		{"target": map[string]any{"kind": "title"}},
		{"target": map[string]any{"kind": "sport_event"}},
		{"target": map[string]any{"kind": "sport_event", "id": "42"}, "note": strings.Repeat("a", 141)},
		// A note is measured as the database measures it, so a long emoji note is a 422, not a 500.
		{"target": map[string]any{"kind": "sport_event", "id": "42"}, "note": strings.Repeat("👍🏽", 100)},
	}
	for i, body := range refused {
		assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, "/v1/shares", body).Code, i)
	}
	fine := map[string]any{"target": map[string]any{"kind": "sport_event", "id": "42"}, "note": strings.Repeat("a", 140)}
	assert.Equal(t, http.StatusOK, e.send(http.MethodPost, "/v1/shares", fine).Code)
	anonymous := e.send(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "sport_event", "id": "42"}}, signedOut)
	assert.Equal(t, http.StatusUnauthorized, anonymous.Code)
}

func TestAnUnknownShareCodeIsOne404(t *testing.T) {
	e := newSocialEnv(t)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/shares/nope12345678", nil, signedOut).Code)
}

func TestMakingLinksIsLimitedPerUser(t *testing.T) {
	co := newFakeConcerts()
	for id := 1; id <= shares.CreatesPerHour; id++ {
		co.eventsByID[fmt.Sprintf("C%d", id)] = sampleConcert(fmt.Sprintf("C%d", id), "2026-11-02", nil)
	}
	e := newSocialEnv(t, withConcerts(co))
	for id := 1; id <= shares.CreatesPerHour; id++ {
		require.Equal(t, http.StatusOK, e.send(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "concert", "id": fmt.Sprintf("C%d", id)}}).Code)
	}
	over := e.send(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "concert", "id": "C1"}})
	assert.Equal(t, http.StatusTooManyRequests, over.Code)
	assert.Equal(t, 60, shares.CreatesPerHour)
	assert.Equal(t, 600, shares.PreviewsPerHour)
}

// downTMDB answers every title and episode lookup with an outage.
type downTMDB struct{ *libraryFake }

func (downTMDB) Hydrate(context.Context, core.ExternalIDs, core.MediaType) (*catalog.Record, error) {
	return nil, provider.NewError("tmdb", provider.KindUnavailable)
}

func (downTMDB) Episodes(context.Context, core.ExternalIDs) (*catalog.Episodes, error) {
	return nil, provider.NewError("tmdb", provider.KindUnavailable)
}

func TestASharedShowOpensFromTheCatalogRowAloneWhileTheCatalogIsDown(t *testing.T) {
	e := newSocialEnv(t)
	tmdb := e.stubShow("Severance", catalog.StatusReturning, 1, 2, false)
	code := shareCode(t, e, map[string]any{"target": map[string]any{"kind": "title", "ref": map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}}}})
	e.server.Catalog.Providers.TMDB = downTMDB{e.fake}
	reply := e.send(http.MethodGet, "/v1/shares/"+code, nil, signedOut)
	require.Equal(t, http.StatusOK, reply.Code, reply.Body.String())
	title := decode[map[string]any](t, reply)["title"].(map[string]any)
	assert.Equal(t, "Severance", title["title"])
	assert.Nil(t, title["seasons"], "no episode list on a public page")
}

func TestAnEventTheProviderDoesNotKnowCannotBeShared(t *testing.T) {
	e := newSocialEnv(t, withSports(sportsProvider()), withConcerts(newFakeConcerts()))
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "sport_event", "id": "777"}}).Code)
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "concert", "id": "Z404"}}).Code)

	off := newSocialEnv(t)
	assert.Equal(t, http.StatusUnprocessableEntity, off.send(http.MethodPost, "/v1/shares", map[string]any{"target": map[string]any{"kind": "sport_event", "id": "42"}}).Code, "sports off: nothing to share")
}

// MARK: Store (ShareStoreTests.swift)

func TestEachShareTargetRoundTripsAndATakenCodeConflicts(t *testing.T) {
	e := newSocialEnv(t)
	ctx := context.Background()
	titleID := uuid.New()
	_, err := e.pool.Exec(ctx, `INSERT INTO titles (id, type, title) VALUES ($1, 'movie', 'Arrival')`, titleID)
	require.NoError(t, err)
	note := "watch this"
	sender := e.user
	for _, target := range []shares.Target{
		{Kind: shares.KindTitle, TitleID: titleID}, {Kind: shares.KindSportEvent, EventID: "2052711"},
		{Kind: shares.KindConcert, EventID: "Z7r9jZ1A7jx"},
	} {
		made := shares.Share{Code: social.NewCode(), Sender: &sender, Target: target, Note: &note, CreatedAt: time.Unix(1_800_000_000, 0).UTC()}
		require.NoError(t, e.server.Shares.Save(ctx, made))
		got, err := e.server.Shares.Share(ctx, made.Code)
		require.NoError(t, err)
		require.NotNil(t, got)
		assert.Equal(t, made.Target, got.Target)
		assert.Equal(t, note, *got.Note)
		assert.Equal(t, sender, *got.Sender)
		assert.True(t, made.CreatedAt.Equal(got.CreatedAt))
		assert.Error(t, e.server.Shares.Save(ctx, shares.Share{Code: made.Code, Sender: &sender, Target: target, CreatedAt: time.Now()}))
	}
	none, err := e.server.Shares.Share(ctx, "nope12345678")
	require.NoError(t, err)
	assert.Nil(t, none)
}

func TestDeletingTheSendersAccountKeepsTheLinkAndDropsTheirNameAndNote(t *testing.T) {
	e := newSocialEnv(t)
	ctx := context.Background()
	note := "secret"
	sender := e.user
	made := shares.Share{Code: social.NewCode(), Sender: &sender, Target: shares.Target{Kind: shares.KindConcert, EventID: "Z7r9jZ1A7jx"}, Note: &note, CreatedAt: time.Now()}
	require.NoError(t, e.server.Shares.Save(ctx, made))
	require.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/me", nil).Code)
	kept, err := e.server.Shares.Share(ctx, made.Code)
	require.NoError(t, err)
	require.NotNil(t, kept)
	assert.Nil(t, kept.Sender)
	assert.Nil(t, kept.Note)
	assert.Equal(t, made.Target, kept.Target)
}
