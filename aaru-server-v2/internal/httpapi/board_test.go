package httpapi

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Board posts over HTTP (BoardTests.swift, BOARD-001).

func TestBoardFriendsSeePostsStrangersAndExFriendsGetTheMissing404(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("hello", ana.token)

	assert.Contains(t, env.boardIDs("/v1/board"), post)

	stranger := env.boardStranger()
	hidden := env.send(http.MethodGet, "/v1/board/posts/"+post, nil, stranger.token)
	missing := env.send(http.MethodGet, "/v1/board/posts/"+uuid.NewString(), nil, stranger.token)
	assert.Equal(t, http.StatusNotFound, hidden.Code)
	assert.Equal(t, missing.Body.String(), hidden.Body.String())
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/board/posts/nope", nil, stranger.token).Code)

	assert.Equal(t, http.StatusOK, env.send(http.MethodGet, "/v1/board/posts/"+post, nil).Code)
	boardUnfriend(env.harness, env.user, ana.uid)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/board/posts/"+post, nil).Code)
	assert.NotContains(t, env.boardIDs("/v1/board"), post)
}

func TestBoardBlockedAuthorsPostsVanish(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("hello", ana.token)
	boardBlock(env.harness, env.user, ana.uid)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/board/posts/"+post, nil).Code)
	assert.NotContains(t, env.boardIDs("/v1/board"), post)
}

func TestBoardPostValidation(t *testing.T) {
	env := newLibEnv(t)
	noHandle := env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": "hi"})
	assert.Equal(t, http.StatusUnprocessableEntity, noHandle.Code)
	assert.Equal(t, "handle_required", decode[map[string]any](t, noHandle)["code"])

	env.boardClaimHandle()
	blank := env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": "   "})
	assert.Equal(t, http.StatusUnprocessableEntity, blank.Code)
	long := env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": strings.Repeat("a", 4001)})
	assert.Equal(t, http.StatusUnprocessableEntity, long.Code)
	lonely := env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": "hi", "rating": 8})
	assert.Equal(t, http.StatusUnprocessableEntity, lonely.Code)
	details, _ := decode[map[string]any](t, lonely)["details"].(map[string]any)
	assert.Contains(t, details, "rating")

	created := env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": " fine "})
	require.Equal(t, http.StatusCreated, created.Code, created.Body.String())
	json := decode[map[string]any](t, created)
	assert.Equal(t, "fine", json["body"])
	assert.Equal(t, true, json["mine"])
	assert.InDelta(t, 0, json["upvotes"], 0)
	assert.Equal(t, false, json["veiled"])
}

func TestBoardOnlyTheAuthorEditsOrDeletes(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("mine")
	path := "/v1/board/posts/" + post

	assert.Equal(t, http.StatusForbidden, env.send(http.MethodPatch, path, map[string]any{"body": "hijack"}, ana.token).Code)
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodDelete, path, nil, ana.token).Code)

	edited := env.send(http.MethodPatch, path, map[string]any{"body": "better"})
	require.Equal(t, http.StatusOK, edited.Code, edited.Body.String())
	json := decode[map[string]any](t, edited)
	assert.Equal(t, "better", json["body"])
	assert.NotNil(t, json["editedAt"])

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, path, nil).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, path, nil).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodDelete, path, nil, ana.token).Code)
}

func TestBoardTopThisWeek(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	quiet := env.boardCreatePost("quiet")
	loud := env.boardCreatePost("loud", ana.token)
	mid := env.boardCreatePost("mid")
	ctx := context.Background()
	store := env.server.Boards.Store
	require.NoError(t, store.SetUpvote(ctx, uuid.MustParse(loud), env.user, true))
	require.NoError(t, store.SetUpvote(ctx, uuid.MustParse(loud), ana.uid, true))
	require.NoError(t, store.SetUpvote(ctx, uuid.MustParse(mid), ana.uid, true))

	reply := env.boardGet("/v1/board?sort=top")
	assert.Equal(t, []string{loud, mid, quiet}, ids(reply["items"]))
	first := reply["items"].([]any)[0].(map[string]any)
	assert.InDelta(t, 2, first["upvotes"], 0)
	assert.Equal(t, true, first["upvotedByMe"])

	assert.Equal(t, []string{mid, loud}, env.boardIDs("/v1/board?limit=2"))
}
