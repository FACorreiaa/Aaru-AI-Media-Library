package httpapi

import (
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Board upvotes (BoardTests+Upvotes.swift, BOARD-001).

func (e *libEnv) boardUpvotes(post string) float64 {
	e.t.Helper()
	n, ok := e.boardGet("/v1/board/posts/" + post)["upvotes"].(float64)
	if !ok {
		return -1
	}
	return n
}

func TestBoardUpvoteTwiceCountsOnceRemovingTwiceIsFine(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("hello", ana.token)
	path := "/v1/board/posts/" + post + "/upvote"

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPut, path, nil).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPut, path, nil).Code)
	assert.InDelta(t, 1, env.boardUpvotes(post), 0)
	assert.Equal(t, true, env.boardGet("/v1/board/posts/" + post)["upvotedByMe"])

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, path, nil).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, path, nil).Code)
	assert.InDelta(t, 0, env.boardUpvotes(post), 0)
}

func TestBoardUpvotingAHiddenOrDeletedPostIsTheMissing404(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("hello", ana.token)
	stranger := env.boardStranger()
	path := "/v1/board/posts/" + post + "/upvote"

	hidden := env.send(http.MethodPut, path, nil, stranger.token)
	missing := env.send(http.MethodPut, "/v1/board/posts/"+uuid.NewString()+"/upvote", nil, stranger.token)
	assert.Equal(t, http.StatusNotFound, hidden.Code)
	assert.Equal(t, missing.Body.String(), hidden.Body.String())
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodDelete, path, nil, stranger.token).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/board/posts/"+post+"/upvotes", nil, stranger.token).Code)

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/board/posts/"+post, nil, ana.token).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPut, path, nil).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPut, "/v1/board/posts/nope/upvote", nil).Code)
}

func TestBoardUpvotersListHidesBlockedPeople(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	bob := env.boardFriend()
	cara := env.boardFriend()
	post := env.boardCreatePost("mine")
	for _, who := range []boardPerson{ana, bob, cara} {
		assert.Equal(t, http.StatusNoContent, env.send(http.MethodPut, "/v1/board/posts/"+post+"/upvote", nil, who.token).Code)
	}
	handles := func() []string {
		items, _ := env.boardGet("/v1/board/posts/" + post + "/upvotes")["items"].([]any)
		var out []string
		for _, it := range items {
			out = append(out, it.(map[string]any)["handle"].(string))
		}
		return out
	}
	require.ElementsMatch(t, []string{ana.handle, bob.handle, cara.handle}, handles())

	// I blocked ana; cara blocked me.
	boardBlock(env.harness, env.user, ana.uid)
	boardBlock(env.harness, cara.uid, env.user)
	assert.Equal(t, []string{bob.handle}, handles())
}
