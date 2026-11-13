package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/moderation"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The word filter over HTTP (SOC-012): every place one person's text reaches another refuses a
// listed word with one typed error and stores nothing; private text is left alone. The words
// come from the list by position, so none is written here.

// refusedPhrase and refusedWord are entries of the committed list.
func refusedPhrase() string { return moderation.Builtin().Entries(moderation.CategoryThreat)[0] }

func refusedWord() string { return moderation.Builtin().Entries(moderation.CategoryHate)[0] }

// assertRefused checks the one answer a refused write gets, and that it does not say the word.
func assertRefused(t *testing.T, rec *httptest.ResponseRecorder, what string) {
	t.Helper()
	require.Equal(t, http.StatusUnprocessableEntity, rec.Code, what+": "+rec.Body.String())
	body := decode[map[string]any](t, rec)
	assert.Equal(t, "content_not_allowed", body["code"], what)
	assert.Equal(t, "That text has words Aaru doesn't allow. Change it and try again.", body["message"], what)
	assert.NotContains(t, strings.ToLower(rec.Body.String()), refusedPhrase(), what)
	assert.NotContains(t, strings.ToLower(rec.Body.String()), refusedWord(), what)
}

func (h *harness) rowCount(query string, args ...any) int {
	h.t.Helper()
	var n int
	require.NoError(h.t, h.pool.QueryRow(context.Background(), query, args...).Scan(&n))
	return n
}

func TestTheWordFilterRefusesBoardPostsAndComments(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()

	assertRefused(t, env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": "well, " + refusedPhrase()}), "a post")
	assertRefused(t, env.send(http.MethodPost, "/v1/board/posts", map[string]any{"body": strings.ToUpper(refusedWord()) + "!"}), "a post in capitals")
	assert.Zero(t, env.rowCount(`SELECT count(*) FROM board_posts`))

	// Talking about a film is not a threat.
	post := env.boardCreatePost("Kill Bill and Inglourious Basterds, back to back")
	assertRefused(t, env.send(http.MethodPatch, "/v1/board/posts/"+post, map[string]any{"body": refusedPhrase()}), "an edit")
	assert.Equal(t, "Kill Bill and Inglourious Basterds, back to back", env.boardGet("/v1/board/posts/" + post)["body"])

	assertRefused(t, env.send(http.MethodPost, "/v1/board/posts/"+post+"/comments", map[string]any{"body": refusedPhrase()}), "a comment")
	assert.Zero(t, env.rowCount(`SELECT count(*) FROM board_comments`))
	env.boardComment(post, "Dick Tracy next?", "")
	assert.Equal(t, 1, env.rowCount(`SELECT count(*) FROM board_comments`))
}

func TestTheWordFilterRefusesGroupNamesChannelsAndMessages(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()

	assertRefused(t, env.send(http.MethodPost, "/v1/groups", map[string]any{"name": refusedWord()}), "a group name")
	assert.Zero(t, env.rowCount(`SELECT count(*) FROM groups`))

	group, general := env.createGroup("Film club")
	base := "/v1/groups/" + group
	assertRefused(t, env.send(http.MethodPatch, base, map[string]any{"name": refusedWord() + " club"}), "a group rename")
	assert.Equal(t, 1, env.rowCount(`SELECT count(*) FROM groups WHERE name = 'Film club'`))

	assertRefused(t, env.send(http.MethodPost, base+"/channels", map[string]any{"name": refusedWord()}), "a channel name")
	assertRefused(t, env.send(http.MethodPost, base+"/channels", map[string]any{"name": "fridays", "topic": refusedPhrase()}), "a channel topic")
	assert.Equal(t, 1, env.rowCount(`SELECT count(*) FROM group_channels`), "only #general")
	assert.Zero(t, env.rowCount(`SELECT count(*) FROM group_channels WHERE name = 'fridays'`))

	assertRefused(t, env.send(http.MethodPatch, base+"/channels/"+general, map[string]any{"name": refusedWord()}), "a channel rename")
	assertRefused(t, env.send(http.MethodPatch, base+"/channels/"+general, map[string]any{"topic": refusedPhrase()}), "a new topic")
	assert.Zero(t, env.rowCount(`SELECT count(*) FROM group_channels WHERE name <> 'general' OR topic IS NOT NULL`))

	channel := channelPath(group, general)
	assertRefused(t, env.send(http.MethodPost, channel+"/messages", map[string]any{"body": refusedPhrase()}), "a message")
	assert.Zero(t, env.rowCount(`SELECT count(*) FROM group_messages WHERE body = $1`, refusedPhrase()))

	message := env.post(channel, "Sex Education is back")["id"].(string)
	assertRefused(t, env.send(http.MethodPatch, channel+"/messages/"+message, map[string]any{"body": refusedPhrase()}), "an edited message")
	assert.Equal(t, 1, env.rowCount(`SELECT count(*) FROM group_messages WHERE body = 'Sex Education is back'`))
}

func TestTheWordFilterRefusesRecommendationAndShareNotes(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	tmdb := e.stubMovie("Arrival")

	recommended := e.send(http.MethodPost, "/v1/social/recommendations",
		map[string]any{"to": []string{ana.idString()}, "title": film(tmdb), "note": refusedPhrase()})
	assertRefused(t, recommended, "a recommendation's note")
	assert.Zero(t, e.rowCount(`SELECT count(*) FROM social_recommendations`))

	shared := e.send(http.MethodPost, "/v1/shares",
		map[string]any{"target": map[string]any{"kind": "title", "ref": film(tmdb)}, "note": refusedPhrase()})
	assertRefused(t, shared, "a share link's note")
	assert.Zero(t, e.rowCount(`SELECT count(*) FROM shares`))

	// The same writes with ordinary notes go through.
	ok := e.send(http.MethodPost, "/v1/social/recommendations",
		map[string]any{"to": []string{ana.idString()}, "title": film(tmdb), "note": "Better than Kill Bill"})
	assert.Equal(t, http.StatusNoContent, ok.Code, ok.Body.String())
	shareCode(t, e, map[string]any{"target": map[string]any{"kind": "title", "ref": film(tmdb)}, "note": "Kill Bill, but with aliens"})
}

func TestTheWordFilterRefusesHandlesAndNames(t *testing.T) {
	e := newSocialEnv(t)

	assertRefused(t, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": refusedWord()}), "a handle")
	assertRefused(t, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": "the" + refusedWord() + "99"}), "a handle holding the word")
	assert.Zero(t, e.rowCount(`SELECT count(*) FROM profiles WHERE user_id = $1 AND handle IS NOT NULL`, e.user))

	handle := e.claimHandle()
	assertRefused(t, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"firstName": refusedWord()}), "a first name")
	assertRefused(t, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"firstName": "Ana", "lastName": refusedWord()}), "a last name")
	assertRefused(t, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"displayName": "Ana " + refusedWord()}), "an older app's one name")
	assert.Equal(t, 1, e.rowCount(`SELECT count(*) FROM users WHERE id = $1 AND first_name IS NULL AND last_name IS NULL`, e.user))

	// A name is checked only when it changes: saving the handle again beside it still works.
	saved := e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": handle, "firstName": "Dick", "lastName": "Tracy"})
	assert.Equal(t, http.StatusOK, saved.Code, saved.Body.String())
}

func TestASignInNameTheWordFilterRefusesIsLeftOut(t *testing.T) {
	h := authHarness(t, nil, nil)
	name := "Ana " + refusedWord()
	session := h.signInApple(&name)

	rec := h.do(http.MethodGet, "/v1/me", session.Token, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	me := decode[api.Me](t, rec)
	assert.Nil(t, me.FirstName)
	assert.Nil(t, me.LastName)
	assert.Nil(t, me.DisplayName)
}

func TestTheWordFilterLeavesPrivateTextAlone(t *testing.T) {
	e := newSocialEnv(t)
	item := e.addItem("movie", e.stubMovie("Arrival"), "wishlist")

	noted := e.send(http.MethodPatch, "/v1/library/items/"+item, map[string]any{"notes": refusedPhrase()})
	require.Equal(t, http.StatusOK, noted.Code, noted.Body.String())
	assert.Equal(t, refusedPhrase(), decode[map[string]any](t, noted)["notes"])

	list := e.send(http.MethodPost, "/v1/lists", map[string]any{"name": refusedWord()})
	require.Less(t, list.Code, 300, list.Body.String())
	assert.Equal(t, 1, e.rowCount(`SELECT count(*) FROM lists WHERE name = $1`, refusedWord()))
}
