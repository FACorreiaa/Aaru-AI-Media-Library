package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

// Board test helpers (TestSupport+Social.swift). The social routes are not ported yet, so
// handles, friendships and blocks are written straight to the tables the social store owns.

// boardPerson is a second signed-in user with a handle (Swift's Person). id is uppercase, as the
// API writes ids.
type boardPerson struct {
	uid    uuid.UUID
	id     string
	token  string
	handle string
}

func boardFreshHandle() string {
	return "b" + strings.ReplaceAll(uuid.NewString(), "-", "")[:15]
}

// boardSetHandle gives a user a handle.
func boardSetHandle(h *harness, user uuid.UUID) string {
	h.t.Helper()
	handle := boardFreshHandle()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO profiles (user_id, handle) VALUES ($1, $2)`, user, handle)
	require.NoError(h.t, err)
	return handle
}

// boardClaimHandle gives the harness user a handle and returns it.
func (e *libEnv) boardClaimHandle() string {
	return boardSetHandle(e.harness, e.user)
}

// boardStranger is a signed-in user with a handle and no friends.
func (e *libEnv) boardStranger() boardPerson {
	e.t.Helper()
	id, token := e.signIn()
	handle := boardSetHandle(e.harness, id)
	return boardPerson{uid: id, id: strings.ToUpper(id.String()), token: token, handle: handle}
}

// boardFriend is a second user with a handle, friends with the harness user.
func (e *libEnv) boardFriend() boardPerson {
	e.t.Helper()
	p := e.boardStranger()
	boardMakeFriends(e.harness, e.user, p.uid)
	return p
}

func boardMakeFriends(h *harness, a, b uuid.UUID) {
	h.t.Helper()
	_, err := h.pool.Exec(context.Background(),
		`INSERT INTO social_friendships (user_low, user_high, created_at) VALUES (LEAST($1::uuid, $2::uuid), GREATEST($1::uuid, $2::uuid), now())`,
		a, b)
	require.NoError(h.t, err)
}

func boardUnfriend(h *harness, a, b uuid.UUID) {
	h.t.Helper()
	_, err := h.pool.Exec(context.Background(),
		`DELETE FROM social_friendships WHERE user_low = LEAST($1::uuid, $2::uuid) AND user_high = GREATEST($1::uuid, $2::uuid)`, a, b)
	require.NoError(h.t, err)
}

// boardBlock is PUT /v1/social/blocks/{id}: the block, and the friendship ends.
func boardBlock(h *harness, blocker, blocked uuid.UUID) {
	h.t.Helper()
	_, err := h.pool.Exec(context.Background(),
		`INSERT INTO social_blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, now()) ON CONFLICT DO NOTHING`, blocker, blocked)
	require.NoError(h.t, err)
	boardUnfriend(h, blocker, blocked)
}

// boardCreatePost posts free text and returns the post's id.
func (e *libEnv) boardCreatePost(body string, bearer ...string) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": body}, bearer...)
	require.Equal(e.t, http.StatusCreated, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)["id"].(string)
}

// boardGet decodes a 2xx JSON reply.
func (e *libEnv) boardGet(path string, bearer ...string) map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodGet, path, nil, bearer...)
	require.Less(e.t, rec.Code, 300, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

// boardIDs are a page's item ids.
func (e *libEnv) boardIDs(path string, bearer ...string) []string {
	e.t.Helper()
	return ids(e.boardGet(path, bearer...)["items"])
}

// boardWatch adds a show as in progress and ticks these episodes; it returns the item's id
// (GroupKindTests.watch).
func (e *libEnv) boardWatch(tmdb string, episodes [][2]int, bearer ...string) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/library/items",
		map[string]any{"mediaRef": map[string]any{"type": "show", "ids": map[string]string{"tmdb": tmdb}}, "status": "in_progress"}, bearer...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	item := decode[map[string]any](e.t, rec)["id"].(string)
	for _, ep := range episodes {
		tick := e.send(http.MethodPut, fmt.Sprintf("/v1/library/items/%s/episodes/%d/%d", item, ep[0], ep[1]),
			map[string]any{"watched": true}, bearer...)
		require.Equal(e.t, http.StatusOK, tick.Code, tick.Body.String())
	}
	return item
}
