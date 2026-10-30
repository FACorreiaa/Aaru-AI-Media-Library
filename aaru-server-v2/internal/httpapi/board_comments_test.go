package httpapi

import (
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Board comments (BoardTests+Comments.swift, BOARD-001).

func (e *libEnv) boardComment(post, body string, replyTo string, bearer ...string) map[string]any {
	e.t.Helper()
	json := map[string]any{"body": body}
	if replyTo != "" {
		json["replyTo"] = replyTo
	}
	rec := e.send(http.MethodPost, "/v1/board/posts/"+post+"/comments", json, bearer...)
	require.Equal(e.t, http.StatusCreated, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

func (e *libEnv) boardComments(post string, bearer ...string) []map[string]any {
	e.t.Helper()
	items, _ := e.boardGet("/v1/board/posts/"+post+"/comments", bearer...)["items"].([]any)
	out := make([]map[string]any, len(items))
	for i, it := range items {
		out[i], _ = it.(map[string]any)
	}
	return out
}

func boardBodies(rows []map[string]any) []any {
	out := make([]any, len(rows))
	for i, r := range rows {
		out[i] = r["body"]
	}
	return out
}

func TestBoardCommentsAreVisibleToEveryoneWhoSeesThePost(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	ben := env.boardFriend()
	post := env.boardCreatePost("hello")
	env.boardComment(post, "nice", "", ben.token)

	seen := env.boardComments(post, ana.token)
	require.Len(t, seen, 1)
	author, _ := seen[0]["author"].(map[string]any)
	assert.Equal(t, ben.handle, author["handle"])
}

func TestBoardReplyToAReplyHangsOffTheTopLevelComment(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	post := env.boardCreatePost("hello")
	topID := env.boardComment(post, "c1", "")["id"].(string)
	second := env.boardComment(post, "r1", topID)
	replyID := second["id"].(string)
	assert.Equal(t, topID, second["replyTo"])
	third := env.boardComment(post, "r2", replyID)
	assert.Equal(t, topID, third["replyTo"])

	bad := env.send(http.MethodPost, "/v1/board/posts/"+post+"/comments",
		map[string]any{"body": "x", "replyTo": strings.ToUpper(uuid.NewString())})
	assert.Equal(t, http.StatusUnprocessableEntity, bad.Code)
	assert.Contains(t, bad.Body.String(), "replyTo")
}

func TestBoardBlocksHideCommentsBothWays(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	ben := env.boardFriend()
	post := env.boardCreatePost("hello")
	env.boardComment(post, "from ben", "", ben.token)
	env.boardComment(post, "from me", "")
	assert.Len(t, env.boardComments(post, ana.token), 2)

	boardBlock(env.harness, ana.uid, ben.uid)
	assert.Equal(t, []any{"from me"}, boardBodies(env.boardComments(post, ana.token)))
	env.boardComment(post, "from ana", "", ana.token)
	assert.NotContains(t, boardBodies(env.boardComments(post, ben.token)), "from ana")
}

func TestBoardAuthorWhoBlockedTheViewerIsTheMissing404AndOffTheFeed(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	anaPost := env.boardCreatePost("ana's", ana.token)
	assert.Equal(t, http.StatusOK, env.send(http.MethodGet, "/v1/board/posts/"+anaPost, nil).Code)
	boardBlock(env.harness, ana.uid, env.user)

	missing := env.send(http.MethodGet, "/v1/board/posts/"+strings.ToUpper(uuid.NewString()), nil)
	hidden := env.send(http.MethodGet, "/v1/board/posts/"+anaPost, nil)
	assert.Equal(t, http.StatusNotFound, hidden.Code)
	assert.Equal(t, missing.Body.String(), hidden.Body.String())
	assert.NotContains(t, env.boardIDs("/v1/board"), anaPost)
}

func TestBoardMentionsReachThePostsAudienceNotTheCommentersFriends(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	ben := env.boardFriend()
	// Carl is Ben's friend only.
	carl := env.boardStranger()
	boardMakeFriends(env.harness, ben.uid, carl.uid)

	post := env.boardCreatePost("hello")
	toAna := env.boardComment(post, "hi @"+ana.handle, "", ben.token)
	assert.Equal(t, []any{ana.id}, toAna["mentions"])
	toCarl := env.boardComment(post, "hi @"+carl.handle, "", ben.token)
	assert.Equal(t, []any{}, toCarl["mentions"])
}

func TestBoardBlockedFriendsPostIsTheMissing404(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	anaPost := env.boardCreatePost("ana's", ana.token)
	boardBlock(env.harness, env.user, ana.uid)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/board/posts/"+anaPost+"/comments", nil).Code)
}

func TestBoardPostAuthorDeletesAnyCommentOthersOnlyTheirOwn(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	ben := env.boardFriend()
	post := env.boardCreatePost("hello")
	byAna := env.boardComment(post, "ana", "", ana.token)["id"].(string)
	byBen := env.boardComment(post, "ben", "", ben.token)["id"].(string)

	path := "/v1/board/posts/" + post + "/comments/"
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodDelete, path+byAna, nil, ben.token).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, path+byBen, nil, ben.token).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, path+byAna, nil).Code)
	assert.Empty(t, env.boardComments(post))
}

func TestBoardDeletedCommentWithRepliesStaysAsAnEmptyRow(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	post := env.boardCreatePost("hello")
	topID := env.boardComment(post, "top", "")["id"].(string)
	env.boardComment(post, "reply", topID)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/board/posts/"+post+"/comments/"+topID, nil).Code)

	rows := env.boardComments(post)
	require.Len(t, rows, 2)
	assert.Equal(t, true, rows[0]["deleted"])
	assert.Empty(t, rows[0]["body"])
	assert.NotContains(t, rows[0], "author")
	assert.Equal(t, []any{}, rows[0]["mentions"])
	assert.Equal(t, false, rows[0]["mentionsAgent"])
	assert.Equal(t, "reply", rows[1]["body"])
}

func TestBoardCommentingOnADeletedPostIsTheMissing404(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	post := env.boardCreatePost("hello")
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/board/posts/"+post, nil).Code)
	path := "/v1/board/posts/" + post + "/comments"
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, path, map[string]any{"body": "late"}).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, path, nil).Code)
}

func TestBoardAaruInACommentIsRecordedNotAnswered(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("hello")
	made := env.boardComment(post, "hey @aaru and @"+ana.handle, "")
	assert.Equal(t, true, made["mentionsAgent"])
	assert.Equal(t, []any{ana.id}, made["mentions"])
	rows := env.boardComments(post)
	require.Len(t, rows, 1)
	assert.Equal(t, false, rows[0]["fromAgent"])
}

func TestBoardCommentBodiesAreValidated(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	post := env.boardCreatePost("hello")
	path := "/v1/board/posts/" + post + "/comments"
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, path, map[string]any{"body": "   "}).Code)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, path, map[string]any{"body": strings.Repeat("a", 4001)}).Code)
}

func TestBoardAllFilteredCommentPageStillCarriesACursor(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	post := env.boardCreatePost("hello")
	for i := range 3 {
		id := env.boardComment(post, "gone "+string(rune('0'+i)), "", ana.token)["id"].(string)
		assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/board/posts/"+post+"/comments/"+id, nil, ana.token).Code)
	}
	env.boardComment(post, "visible", "")

	page := env.boardGet("/v1/board/posts/" + post + "/comments?limit=3")
	assert.Equal(t, []any{}, page["items"])
	next, ok := page["next"].(string)
	require.True(t, ok, "next: %v", page["next"])
	second := env.boardGet("/v1/board/posts/" + post + "/comments?limit=3&after=" + next)
	items, _ := second["items"].([]any)
	require.Len(t, items, 1)
	assert.Equal(t, "visible", items[0].(map[string]any)["body"])
	assert.Nil(t, second["next"])
}

func TestBoardHiddenCommentIsNotFoundToDeleteOrReplyTo(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	ben := env.boardFriend()
	post := env.boardCreatePost("carl's")
	byBen := env.boardComment(post, "ben", "", ben.token)["id"].(string)
	boardBlock(env.harness, ana.uid, ben.uid)

	path := "/v1/board/posts/" + post + "/comments"
	gone := env.send(http.MethodDelete, path+"/"+byBen, nil, ana.token)
	unknown := env.send(http.MethodDelete, path+"/"+uuid.NewString(), nil, ana.token)
	assert.Equal(t, http.StatusNotFound, gone.Code)
	assert.Equal(t, unknown.Body.String(), gone.Body.String())
	reply := env.send(http.MethodPost, path, map[string]any{"body": "hi", "replyTo": byBen}, ana.token)
	assert.Equal(t, http.StatusUnprocessableEntity, reply.Code)
	assert.Contains(t, reply.Body.String(), "replyTo")
}
