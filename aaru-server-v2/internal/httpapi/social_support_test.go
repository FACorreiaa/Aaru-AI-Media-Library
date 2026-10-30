package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/token"
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

// TestSupport+Social.swift: people with handles, friends made by requests or invites.

// signedOut is a bearer no session holds, so the request is signed out.
const signedOut = "signed-out"

// person is a second signed-in user.
type person struct {
	id     uuid.UUID
	token  string
	handle string
}

// idString is the id as Swift printed it.
func (p person) idString() string { return strings.ToUpper(p.id.String()) }

// freshHandle is a handle no other test has used.
func freshHandle() string {
	return "t" + strings.ReplaceAll(uuid.NewString(), "-", "")[:15]
}

// newSocialEnv is the library harness with Deps tweaks (sports, concerts) applied after the catalog.
func newSocialEnv(t *testing.T, tweak ...func(*Deps)) *libEnv {
	t.Helper()
	fake := &libraryFake{episodes: map[string]catalog.Episodes{}}
	providers := catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}
	all := append([]func(*Deps){func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) }}, tweak...)
	h := newHarness(t, all...)
	user, bearer := h.signIn()
	return &libEnv{harness: h, fake: fake, user: user, bearer: bearer}
}

// claimHandle gives the harness user a handle and returns it.
func (e *libEnv) claimHandle() string {
	e.t.Helper()
	handle := freshHandle()
	rec := e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": handle})
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return handle
}

// friendlyUser is a second signed-in user with a claimed handle.
func (e *libEnv) friendlyUser() person {
	e.t.Helper()
	id, bearer := e.signIn()
	handle := freshHandle()
	rec := e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": handle}, bearer)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return person{id: id, token: bearer, handle: handle}
}

// befriend makes the harness user (holding mine) and p friends by asking each other.
func (e *libEnv) befriend(mine string, p person) {
	e.t.Helper()
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": p.handle})
	rec := e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, p.token)
	require.Equal(e.t, "friend", decode[map[string]any](e.t, rec)["relationship"])
}

// friendByRequest is a second user with a handle, friends with the harness user (holding mine).
func (e *libEnv) friendByRequest(mine string) person {
	e.t.Helper()
	p := e.friendlyUser()
	e.befriend(mine, p)
	return p
}

// friendsByInvite gives the harness user a handle and makes a second user their friend by an invite.
func (e *libEnv) friendsByInvite() person {
	e.t.Helper()
	e.claimHandle()
	ana := e.friendlyUser()
	code := e.json(http.MethodPost, "/v1/social/invites", map[string]any{})["code"].(string)
	rec := e.send(http.MethodPost, "/v1/social/invites/"+code+"/redeem", map[string]any{"addTitle": false}, ana.token)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return ana
}

// addItem adds a title to someone's library and returns the item id.
func (e *libEnv) addItem(typ, tmdb, status string, bearer ...string) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/library/items", map[string]any{
		"mediaRef": map[string]any{"type": typ, "ids": map[string]string{"tmdb": tmdb}}, "status": status,
	}, bearer...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)["id"].(string)
}

// get decodes a 2xx JSON answer for bearer (the harness user when empty).
func (e *libEnv) get(path string, bearer ...string) map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodGet, path, nil, bearer...)
	require.Less(e.t, rec.Code, 300, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

// userWithEmail is a signed-in user whose only sign-in has this email.
func (e *libEnv) userWithEmail(provider, email string) string {
	e.t.Helper()
	ctx := context.Background()
	id := uuid.New()
	_, err := e.pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, id)
	require.NoError(e.t, err)
	_, err = e.pool.Exec(ctx, `INSERT INTO auth_identities (id, user_id, provider, provider_subject, email) VALUES ($1, $2, $3, $4, $5)`,
		uuid.New(), id, provider, uuid.NewString(), email)
	require.NoError(e.t, err)
	bearer := token.Generate()
	_, err = e.pool.Exec(ctx, `INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, $4)`,
		uuid.New(), id, token.Hash(bearer), time.Now().Add(time.Hour))
	require.NoError(e.t, err)
	return bearer
}

// uploadAvatar sends raw bytes as the avatar.
func (e *libEnv) uploadAvatar(body []byte, contentType string, bearer ...string) *httptest.ResponseRecorder {
	e.t.Helper()
	tok := e.bearer
	if len(bearer) > 0 {
		tok = bearer[0]
	}
	req := httptest.NewRequest(http.MethodPut, "/v1/me/avatar", bytes.NewReader(body))
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Authorization", "Bearer "+tok)
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

func relationshipOf(t *testing.T, rec *httptest.ResponseRecorder) any {
	t.Helper()
	return decode[map[string]any](t, rec)["relationship"]
}

// handlesOf are the handles in a list of users under key.
func handlesOf(body map[string]any, key string) []string {
	out := []string{}
	list, _ := body[key].([]any)
	for _, item := range list {
		if m, ok := item.(map[string]any); ok {
			if h, ok := m["handle"].(string); ok {
				out = append(out, h)
			}
		}
	}
	return out
}

// titleNames are the `title` of each item's `title` object.
func titleNames(value any) []string {
	out := []string{}
	list, _ := value.([]any)
	for _, item := range list {
		if m, ok := item.(map[string]any); ok {
			if t, ok := m["title"].(map[string]any); ok {
				out = append(out, t["title"].(string))
			}
		}
	}
	return out
}

// names are each summary's `title`.
func names(value any) []string {
	out := []string{}
	list, _ := value.([]any)
	for _, item := range list {
		if m, ok := item.(map[string]any); ok {
			out = append(out, m["title"].(string))
		}
	}
	return out
}
