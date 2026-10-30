package httpapi

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/push"
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Mention and invite alerts against a fake APNs (GRP-012). No real key, no network.

type sentPush struct {
	message push.Message
	device  push.Device
}

// groupFakeAPNs records every alert instead of sending it.
type groupFakeAPNs struct {
	mu   sync.Mutex
	sent []sentPush
}

func (f *groupFakeAPNs) Send(_ context.Context, m push.Message, d push.Device) (push.Outcome, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, sentPush{m, d})
	return push.Sent, nil
}

func (f *groupFakeAPNs) messages() []sentPush {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]sentPush(nil), f.sent...)
}

func newGroupPushEnv(t *testing.T) (*groupEnv, *groupFakeAPNs) {
	fake := &groupFakeAPNs{}
	env := newGroupEnv(t, func(d *Deps) {
		d.Push = &push.UserPush{Q: sqlc.New(d.Pool), APNs: fake}
	})
	return env, fake
}

// device registers a device for whoever the token signs in, and returns its APNs token.
func (e *groupEnv) device(token ...string) string {
	e.t.Helper()
	device := apnsToken()
	rec := e.send(http.MethodPut, "/v1/devices", map[string]string{
		"token": device, "environment": "production", "bundleId": "com.fernandocorreia.aaru",
	}, token...)
	require.Equal(e.t, http.StatusNoContent, rec.Code, rec.Body.String())
	return device
}

func (e *groupEnv) notificationSettings(body map[string]bool, token ...string) map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodPut, "/v1/me/notifications", body, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

func TestGroupPushSwitchesStartOffAndPutChangesOnlyWhatItSends(t *testing.T) {
	env := newGroupEnv(t)
	initial := env.get("/v1/me/notifications")
	assert.Equal(t, false, initial["airing"])
	assert.Equal(t, false, initial["groupMentions"])
	assert.Equal(t, false, initial["groupInvites"])
	mentions := env.notificationSettings(map[string]bool{"groupMentions": true})
	assert.Equal(t, true, mentions["groupMentions"])
	assert.Equal(t, false, mentions["airing"])
	airing := env.notificationSettings(map[string]bool{"airing": true})
	assert.Equal(t, true, airing["airing"])
	assert.Equal(t, true, airing["groupMentions"])
	assert.Equal(t, false, airing["groupInvites"])
}

func TestGroupPushMentionAlertsTheTaggedMemberOnceWithoutTheMessage(t *testing.T) {
	env, fake := newGroupPushEnv(t)
	mine := env.claimHandle()
	group, general := env.createGroup("Film club")
	ana, ben, cai, dan := env.friend(env.user), env.friend(env.user), env.friend(env.user), env.friend(env.user)
	for _, p := range []person{ana, ben, cai, dan} {
		env.join(p, group)
	}
	names := map[string]string{env.device(ana.Token): "ana", env.device(): "me"}
	names[env.device(ben.Token)] = "ben"
	names[env.device(dan.Token)] = "dan"
	for _, p := range []person{ana, ben, dan} {
		env.notificationSettings(map[string]bool{"groupMentions": true}, p.Token)
	}
	names[env.device(cai.Token)] = "cai"
	env.notificationSettings(map[string]bool{"groupMentions": true})
	// Ben muted the group, Cai never turned mention alerts on, Dan blocked the author.
	rec := env.send(http.MethodPut, "/v1/groups/"+group+"/me", map[string]any{"muted": true}, ben.Token)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	muted := decode[map[string]any](t, rec)
	assert.Equal(t, true, muted["muted"])
	assert.Equal(t, false, muted["shareProgress"])
	env.block(dan.uid, env.user)
	env.unfriend(dan.uid, env.user)

	path := channelPath(group, general)
	body := fmt.Sprintf("@%s @%s @%s @%s @%s the twist is the dog", ana.Handle, ben.Handle, cai.Handle, dan.Handle, mine)
	payload := map[string]any{"body": body, "clientNonce": "n-1"}
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, path+"/messages", payload).Code)
	// A retry returns the first message and alerts nobody again.
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, path+"/messages", payload).Code)

	sent := fake.messages()
	got := make([]string, len(sent))
	for i, s := range sent {
		got[i] = names[s.device.Token]
	}
	assert.Equal(t, []string{"ana"}, got)
	require.NotEmpty(t, sent)
	alert := sent[0].message
	assert.Equal(t, "Film club", alert.Title)
	assert.Equal(t, "@"+mine+" mentioned you in #general", alert.Body)
	assert.Equal(t, "aaru://group/"+group+"/channel/"+general, alert.Payload["url"])
	assert.Equal(t, group, alert.Payload["groupId"])
	assert.Equal(t, general, alert.Payload["channelId"])
	assert.NotContains(t, fmt.Sprintf("%v", alert), "twist")
}

func TestGroupPushInviteAlertsTheFriendOnceOnlyWithInviteAlertsOn(t *testing.T) {
	env, fake := newGroupPushEnv(t)
	mine := env.claimHandle()
	group, _ := env.createGroup("Anime night")
	ana, ben := env.friend(env.user), env.friend(env.user)
	anaDevice := env.device(ana.Token)
	env.device(ben.Token)
	env.notificationSettings(map[string]bool{"groupInvites": true}, ana.Token)

	for _, p := range []person{ana, ben, ana} {
		rec := env.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": p.ID})
		require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	}
	sent := fake.messages()
	require.Len(t, sent, 1)
	assert.Equal(t, anaDevice, sent[0].device.Token)
	assert.Equal(t, "@"+mine+" invited you to Anime night", sent[0].message.Body)
	assert.Equal(t, "aaru://groups", sent[0].message.Payload["url"])
}

func TestGroupPushWebAlertsOpenTheChannelOrTheGroupsPage(t *testing.T) {
	blank := "  "
	channel := groups.MentionAlert(
		groups.User{ID: uuid.New(), Handle: "ana", DisplayName: &blank},
		"Film club",
		groups.Channel{ID: uuid.New(), GroupID: uuid.New(), Name: "general", IsDefault: true, CreatedAt: time.Now()},
	)
	assert.Equal(t, "@ana mentioned you in #general", channel.Body)
	assert.Equal(t, "/app/groups/"+channel.Payload["groupId"]+"/"+channel.Payload["channelId"], push.WebPath(channel.Payload))
	name := "Ana"
	invite := groups.InviteAlert(groups.User{ID: uuid.New(), Handle: "ana", DisplayName: &name}, "Film club")
	assert.Equal(t, "Ana invited you to Film club", invite.Body)
	assert.Equal(t, "/app/groups", push.WebPath(invite.Payload))
	assert.False(t, strings.Contains(invite.Body, "@"))
}
