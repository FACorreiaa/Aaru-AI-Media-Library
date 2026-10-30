package httpapi

import (
	"aaru-go-api/internal/groups"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GroupTests.swift: groups, channels and messages (GRP-001…GRP-003).

func TestGroupCreateNeedsHandleAndHidesFromOutsiders(t *testing.T) {
	env := newGroupEnv(t)
	noHandle := env.send(http.MethodPost, "/v1/groups", map[string]any{"name": "Film club"})
	assert.Equal(t, "handle_required", decode[map[string]any](t, noHandle)["code"])
	env.claimHandle()
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, "/v1/groups", map[string]any{"name": "  "}).Code)

	group, general := env.createGroup("Film club")
	detail := env.get("/v1/groups/" + group)
	channels := maps(detail["channels"])
	require.Len(t, channels, 1)
	assert.Equal(t, "general", channels[0]["name"])
	assert.Equal(t, general, channels[0]["id"])
	assert.Equal(t, true, channels[0]["isDefault"])
	assert.Equal(t, "owner", detail["group"].(map[string]any)["role"])
	listed := items(t, env.send(http.MethodGet, "/v1/groups", nil))
	assert.Equal(t, group, listed[0]["id"])

	// A stranger sees exactly what a group that does not exist shows.
	stranger := env.stranger()
	hidden := env.send(http.MethodGet, "/v1/groups/"+group, nil, stranger.Token)
	missing := env.send(http.MethodGet, "/v1/groups/"+up(uuid.New()), nil, stranger.Token)
	assert.Equal(t, http.StatusNotFound, hidden.Code)
	assert.Equal(t, missing.Body.String(), hidden.Body.String())
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, channelPath(group, general)+"/messages", nil, stranger.Token).Code)
}

func TestGroupInvitesAreFriendsOnly(t *testing.T) {
	env := newGroupEnv(t)
	mine := env.claimHandle()
	group, _ := env.createGroup("Film club")
	stranger := env.stranger()
	notFriend := env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": stranger.ID})
	assert.Equal(t, http.StatusUnprocessableEntity, notFriend.Code)
	// Someone who blocked you looks exactly like someone who is not your friend: blocking ends the
	// friendship (the social area does that), so the invite meets the same refusal.
	blocker := env.friend(env.user)
	env.unfriend(env.user, blocker.uid)
	env.block(blocker.uid, env.user)
	blocked := env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": blocker.ID})
	assert.Equal(t, http.StatusUnprocessableEntity, blocked.Code)
	assert.Equal(t, notFriend.Body.String(), blocked.Body.String())

	ana := env.friend(env.user)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": ana.ID}).Code)
	pending := maps(env.get("/v1/groups/" + group)["invited"])
	require.Len(t, pending, 1)
	assert.Equal(t, ana.Handle, pending[0]["handle"])
	// Declining removes it; a non-member still sees nothing.
	inbox := env.inbox(ana)
	require.Len(t, inbox, 1)
	assert.Equal(t, mine, inbox[0]["inviter"].(map[string]any)["handle"])
	inviteID := inbox[0]["id"].(string)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/group-invites/"+inviteID, nil, ana.Token).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, "/v1/group-invites/"+inviteID+"/accept", nil, ana.Token).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/groups/"+group, nil, ana.Token).Code)

	env.join(ana, group)
	assert.Len(t, maps(env.get("/v1/groups/"+group, ana.Token)["members"]), 2)
	// Inviting someone already in changes nothing.
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": ana.ID}).Code)
	assert.Empty(t, maps(env.get("/v1/groups/" + group)["invited"]))
	// A malformed user id is nobody.
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": "nope"}).Code)
}

func TestGroupMessagesPageRetryMentionAndUnread(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	ana := env.friend(env.user)
	group, general := env.createGroup("Film club")
	env.join(ana, group)
	channel := channelPath(group, general)

	first := decode[map[string]any](t, env.send(http.MethodPost, channel+"/messages", map[string]any{"body": " hi ", "clientNonce": "n-1"}))
	retry := decode[map[string]any](t, env.send(http.MethodPost, channel+"/messages", map[string]any{"body": "hi", "clientNonce": "n-1"}))
	assert.Equal(t, first["id"], retry["id"])
	assert.Equal(t, "hi", first["body"])
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, channel+"/messages", map[string]any{"body": "   "}).Code)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, channel+"/messages", map[string]any{"body": strings.Repeat("a", 4001)}).Code)

	tagged := env.post(channel, "@"+strings.ToUpper(ana.Handle)+" and @aaru, not a@"+ana.Handle)
	assert.Equal(t, []any{ana.ID}, tagged["mentions"])
	assert.Equal(t, true, tagged["mentionsAgent"])
	// A friend who is not in the group is not mentioned.
	outsider := env.friend(env.user)
	assert.Equal(t, []any{}, env.post(channel, "hi @"+outsider.Handle)["mentions"])
	for n := 1; n <= 5; n++ {
		env.post(channel, fmt.Sprintf("m%d", n))
	}

	// Ana sees her unread and mention counts, then reads.
	summary := items(t, env.send(http.MethodGet, "/v1/groups", nil, ana.Token))
	require.Len(t, summary, 1)
	assert.InDelta(t, 8, summary[0]["unread"], 0)
	assert.InDelta(t, 1, summary[0]["mentions"], 0)

	latest := env.send(http.MethodGet, channel+"/messages?limit=3", nil, ana.Token)
	assert.Equal(t, []string{"m3", "m4", "m5"}, bodies(t, latest))
	page := items(t, latest)
	oldest, last := page[0]["id"].(string), page[2]["id"].(string)
	older := bodies(t, env.send(http.MethodGet, channel+"/messages?before="+oldest+"&limit=3", nil, ana.Token))
	assert.Len(t, older, 3)
	assert.Equal(t, "m2", older[2])
	assert.Equal(t, []string{"m4", "m5"}, bodies(t, env.send(http.MethodGet, channel+"/messages?after="+oldest, nil, ana.Token)))

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, channel+"/read", map[string]any{"messageId": last}, ana.Token).Code)
	read := maps(env.get("/v1/groups/"+group, ana.Token)["channels"])
	assert.InDelta(t, 0, read[0]["unread"], 0)
	assert.InDelta(t, 0, read[0]["mentions"], 0)
	// The read point never moves back.
	env.send(http.MethodPost, channel+"/read", map[string]any{"messageId": oldest}, ana.Token)
	assert.InDelta(t, 0, maps(env.get("/v1/groups/"+group, ana.Token)["channels"])[0]["unread"], 0)
	// A malformed cursor is no such message.
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, channel+"/messages?before=nope", nil, ana.Token).Code)
}

func TestGroupEditDeleteAndBlockedAuthors(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	ana := env.friend(env.user)
	group, general := env.createGroup("Film club")
	env.join(ana, group)
	channel := channelPath(group, general)

	hers := env.post(channel, "from ana", ana.Token)["id"].(string)
	mineID := env.post(channel, "from me")["id"].(string)
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodPatch, channel+"/messages/"+hers, map[string]any{"body": "edited"}).Code)
	editedRec := env.send(http.MethodPatch, channel+"/messages/"+hers, map[string]any{"body": "edited"}, ana.Token)
	require.Equal(t, http.StatusOK, editedRec.Code, editedRec.Body.String())
	edited := decode[map[string]any](t, editedRec)
	assert.Equal(t, "edited", edited["body"])
	assert.NotNil(t, edited["editedAt"])
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodDelete, channel+"/messages/"+mineID, nil, ana.Token).Code)
	// The owner deletes anyone's message; the row stays, empty.
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, channel+"/messages/"+hers, nil).Code)
	var deleted map[string]any
	for _, m := range items(t, env.send(http.MethodGet, channel+"/messages", nil)) {
		if m["id"] == hers {
			deleted = m
		}
	}
	require.NotNil(t, deleted)
	assert.Equal(t, true, deleted["deleted"])
	assert.Equal(t, "", deleted["body"])

	env.post(channel, "still here", ana.Token)
	env.block(env.user, ana.uid)
	flagged := items(t, env.send(http.MethodGet, channel+"/messages", nil))
	assert.Equal(t, true, flagged[len(flagged)-1]["fromBlocked"])
	assert.Equal(t, "still here", flagged[len(flagged)-1]["body"])
}

func TestGroupRolesChannelsAndOwnership(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	ana := env.friend(env.user)
	kai := env.friend(env.user)
	group, general := env.createGroup("Film club")
	env.join(ana, group)
	env.join(kai, group)
	base := "/v1/groups/" + group

	assert.Equal(t, http.StatusForbidden, env.send(http.MethodPost, base+"/channels", map[string]any{"name": "x"}, ana.Token).Code)
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodPatch, base+"/members/"+ana.ID, map[string]any{"role": "admin"}, kai.Token).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPatch, base+"/members/"+ana.ID, map[string]any{"role": "admin"}).Code)

	created := env.send(http.MethodPost, base+"/channels", map[string]any{"name": " Movie  Night! "}, ana.Token)
	require.Equal(t, http.StatusOK, created.Code, created.Body.String())
	channel := decode[map[string]any](t, created)
	assert.Equal(t, "movie-night", channel["name"])
	channelID := channel["id"].(string)
	assert.Equal(t, http.StatusConflict, env.send(http.MethodPost, base+"/channels", map[string]any{"name": "movie night"}).Code)
	renamed := decode[map[string]any](t, env.send(http.MethodPatch, base+"/channels/"+channelID, map[string]any{"topic": "Fridays"}, ana.Token))
	assert.Equal(t, "Fridays", renamed["topic"])
	assert.Equal(t, "movie-night", renamed["name"])
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodDelete, base+"/channels/"+general, nil).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, base+"/channels/"+channelID, nil, ana.Token).Code)
	for n := 1; n <= 19; n++ {
		env.send(http.MethodPost, base+"/channels", map[string]any{"name": fmt.Sprintf("c%d", n)})
	}
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, base+"/channels", map[string]any{"name": "one-too-many"}).Code)

	// An admin removes members, not the owner or another admin.
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodDelete, base+"/members/"+up(env.user), nil, ana.Token).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, base+"/members/"+kai.ID, nil, ana.Token).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, base, nil, kai.Token).Code)

	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodDelete, base+"/members/"+up(env.user), nil).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, base+"/transfer", map[string]any{"userId": ana.ID}).Code)
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodDelete, base, nil).Code)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, base+"/members/"+up(env.user), nil).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, base, nil).Code)
	assert.Equal(t, "owner", env.get(base, ana.Token)["group"].(map[string]any)["role"])
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, base, nil, ana.Token).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, base, nil, ana.Token).Code)
}

func TestGroupAccountDeleteEmptiesMessagesAndHandsGroupsOn(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	ana := env.friend(env.user)
	// Ana owns one group with the harness user in it and one alone.
	shared, general := env.createGroup("Shared", ana.Token)
	alone, _ := env.createGroup("Alone", ana.Token)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, "/v1/groups/"+shared+"/invites", map[string]any{"userId": up(env.user)}, ana.Token).Code)
	me := groupMember{uid: env.user, ID: up(env.user), Token: env.bearer}
	invite := env.inbox(me)[0]["id"].(string)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/group-invites/"+invite+"/accept", nil).Code)
	channel := channelPath(shared, general)
	env.post(channel, "secret plans", ana.Token)
	env.post(channel, "mine stays")

	export := env.get("/v1/me/export", ana.Token)
	exported := maps(export["groupMessages"])
	require.Len(t, exported, 1)
	assert.Equal(t, "secret plans", exported[0]["body"])
	assert.Len(t, export["groups"], 2)

	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/me", nil, ana.Token).Code)
	assert.Equal(t, "owner", env.get("/v1/groups/" + shared)["group"].(map[string]any)["role"])
	messages := items(t, env.send(http.MethodGet, channel+"/messages", nil))
	require.Len(t, messages, 2)
	assert.Equal(t, "", messages[0]["body"])
	assert.Equal(t, "mine stays", messages[1]["body"])
	assert.Nil(t, messages[0]["author"])
	remaining, err := env.server.Groups.Store.Summaries(t.Context(), ana.uid)
	require.NoError(t, err)
	assert.Empty(t, remaining)
	other := env.stranger()
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/groups/"+alone, nil, other.Token).Code)
}

func TestGroupNonceIsTheAuthors(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	ana := env.friend(env.user)
	group, general := env.createGroup("Film club")
	env.join(ana, group)
	path := channelPath(group, general) + "/messages"
	posted := decode[map[string]any](t, env.send(http.MethodPost, path, map[string]any{"body": "hi", "clientNonce": "n-9"}))
	assert.Equal(t, "n-9", posted["clientNonce"])
	mine := items(t, env.send(http.MethodGet, path, nil))
	assert.Equal(t, "n-9", mine[len(mine)-1]["clientNonce"])
	hers := items(t, env.send(http.MethodGet, path, nil, ana.Token))
	assert.Nil(t, hers[len(hers)-1]["clientNonce"])
}

func TestGroupPaginationWalksBackOnce(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	for n := 1; n <= 7; n++ {
		env.post(channel, fmt.Sprintf("p%d", n))
	}
	var seen []string
	cursor := ""
	for {
		page := items(t, env.send(http.MethodGet, channel+"/messages?limit=2"+cursor, nil))
		if len(page) == 0 {
			break
		}
		var got []string
		for _, m := range page {
			got = append(got, m["body"].(string))
		}
		seen = append(got, seen...)
		cursor = "&before=" + page[0]["id"].(string)
	}
	assert.Equal(t, []string{"p1", "p2", "p3", "p4", "p5", "p6", "p7"}, seen)
}

func TestGroupMentionParsing(t *testing.T) {
	ana := groups.User{ID: uuid.New(), Handle: "ana"}
	users, agent := groups.Mentions("@ana @ANA mail@ana x@aaru @anax", []groups.User{ana})
	assert.Equal(t, []uuid.UUID{ana.ID}, users)
	assert.False(t, agent)
	_, agent = groups.Mentions("hey @aaru!", nil)
	assert.True(t, agent)
	name, err := groups.ChannelName("Séries  e Filmes")
	require.NoError(t, err)
	assert.Equal(t, "séries-e-filmes", name)
	_, err = groups.ChannelName("!!!")
	assert.Error(t, err)
}

// GroupTests+Friendship.swift. Unfriending or blocking dropping the pair's invites is the social
// area's write; what groups own is accept re-checking the friendship.
func TestGroupAcceptRechecksFriendship(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	group, _ := env.createGroup("Film club")
	dee := env.friend(env.user)
	env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": dee.ID})
	orphan := env.inbox(dee)[0]["id"].(string)
	// The friendship goes behind the store's back, as a race with a block could leave it.
	env.unfriend(env.user, dee.uid)
	refused := env.send(http.MethodPost, "/v1/group-invites/"+orphan+"/accept", nil, dee.Token)
	missing := env.send(http.MethodPost, "/v1/group-invites/"+up(uuid.New())+"/accept", nil, dee.Token)
	assert.Equal(t, http.StatusNotFound, refused.Code)
	assert.Equal(t, missing.Body.String(), refused.Body.String())
	assert.Empty(t, env.inbox(dee))
}

// GroupTests+Nonce.swift.
func TestGroupNonceRetryStaysInItsChannel(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	other := decode[map[string]any](t, env.send(http.MethodPost, "/v1/groups/"+group+"/channels", map[string]any{"name": "other"}))["id"].(string)
	path := channelPath(group, general) + "/messages"
	first := decode[map[string]any](t, env.send(http.MethodPost, path, map[string]any{"body": "hi", "clientNonce": "n-1"}))
	retry := decode[map[string]any](t, env.send(http.MethodPost, path, map[string]any{"body": "hi", "clientNonce": "n-1"}))
	assert.Equal(t, first["id"], retry["id"])
	elsewhere := env.send(http.MethodPost, channelPath(group, other)+"/messages", map[string]any{"body": "hi", "clientNonce": "n-1"})
	assert.Equal(t, http.StatusConflict, elsewhere.Code)
	assert.Empty(t, bodies(t, env.send(http.MethodGet, channelPath(group, other)+"/messages", nil)))
}

func TestGroupInvitesEndWithFriendship(t *testing.T) {
	env := newGroupEnv(t)
	mine := env.claimHandle()
	group, _ := env.createGroup("Film club")
	ana := env.friend(env.user)
	require.Equal(t, http.StatusNoContent, env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": ana.ID}).Code)
	inbox := env.inbox(ana)
	require.NotEmpty(t, inbox)
	stale := inbox[0]["id"].(string)
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/social/friends/"+ana.ID, nil).Code)
	assert.Empty(t, env.inbox(ana))
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, "/v1/group-invites/"+stale+"/accept", nil, ana.Token).Code)
	env.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.Handle})
	env.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, ana.Token)
	env.join(ana, group)
}

func TestGroupBlockDropsOnlyThePairsInvites(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	group, _ := env.createGroup("Film club")
	bob, cara := env.friend(env.user), env.friend(env.user)
	env.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": bob.Handle}, cara.Token)
	env.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": cara.Handle}, bob.Token)
	carasGroup, _ := env.createGroup("Cara's", cara.Token)
	require.Equal(t, http.StatusNoContent,
		env.send(http.MethodPost, "/v1/groups/"+carasGroup+"/invites", map[string]any{"userId": bob.ID}, cara.Token).Code)
	require.Equal(t, http.StatusNoContent, env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": bob.ID}).Code)
	assert.Len(t, env.inbox(bob), 2)
	require.Less(t, env.send(http.MethodPut, "/v1/social/blocks/"+up(env.user), nil, bob.Token).Code, 300)
	left := env.inbox(bob)
	require.Len(t, left, 1)
	assert.Equal(t, carasGroup, left[0]["groupId"])
	assert.Equal(t, cara.Handle, left[0]["inviter"].(map[string]any)["handle"])
}
