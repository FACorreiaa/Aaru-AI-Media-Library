package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

// groupEnv is the LibraryHarness with the social rows groups need written straight to the
// database (profiles, friendships, blocks): the social routes are another area's.
type groupEnv struct {
	*libEnv
}

// person is another signed-in user. ID is uppercase, as the wire writes it.
type person struct {
	uid    uuid.UUID
	ID     string
	Token  string
	Handle string
}

func newGroupEnv(t *testing.T, tweak ...func(*Deps)) *groupEnv {
	t.Helper()
	env := newLibEnv(t)
	if len(tweak) > 0 {
		// Rebuild the server over the same pool and catalog with the tweak applied.
		deps := env.server.Deps
		deps.Groups, deps.Realtime = nil, nil
		for _, f := range tweak {
			f(&deps)
		}
		env.server = New(deps)
		env.echo = env.server.Router(nil)
	}
	return &groupEnv{libEnv: env}
}

func (e *groupEnv) exec(sql string, args ...any) {
	e.t.Helper()
	_, err := e.pool.Exec(context.Background(), sql, args...)
	require.NoError(e.t, err)
}

func freshHandle() string {
	return "u" + strings.ReplaceAll(uuid.NewString(), "-", "")[:12]
}

// setHandle gives a user a handle and returns it.
func (e *groupEnv) setHandle(user uuid.UUID) string {
	handle := freshHandle()
	e.exec(`INSERT INTO profiles (user_id, handle) VALUES ($1, $2)`, user, handle)
	return handle
}

// claimHandle gives the harness user a handle.
func (e *groupEnv) claimHandle() string { return e.setHandle(e.user) }

func (e *groupEnv) makeFriends(a, b uuid.UUID) {
	low, high := a, b
	if strings.Compare(low.String(), high.String()) > 0 {
		low, high = high, low
	}
	e.exec(`INSERT INTO social_friendships (user_low, user_high, created_at) VALUES ($1, $2, now()) ON CONFLICT DO NOTHING`, low, high)
}

func (e *groupEnv) unfriend(a, b uuid.UUID) {
	e.exec(`DELETE FROM social_friendships WHERE user_low = LEAST($1::uuid, $2::uuid) AND user_high = GREATEST($1::uuid, $2::uuid)`, a, b)
}

func (e *groupEnv) block(blocker, blocked uuid.UUID) {
	e.exec(`INSERT INTO social_blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, now())`, blocker, blocked)
}

// stranger is a signed-in user with a handle and no friends.
func (e *groupEnv) stranger() person {
	id, token := e.signIn()
	return person{uid: id, ID: strings.ToUpper(id.String()), Token: token, Handle: e.setHandle(id)}
}

// friend is a new user with a handle, friends with of.
func (e *groupEnv) friend(of uuid.UUID) person {
	p := e.stranger()
	e.makeFriends(of, p.uid)
	return p
}

func up(id uuid.UUID) string { return strings.ToUpper(id.String()) }

// createGroup makes a group as the harness user (or token) and returns it and its #general.
func (e *groupEnv) createGroup(name string, token ...string) (group, general string) {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/groups", map[string]any{"name": name}, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	g := decode[map[string]any](e.t, rec)["group"].(map[string]any)
	return g["id"].(string), g["defaultChannelId"].(string)
}

// join invites a friend into the harness user's group and accepts for them.
func (e *groupEnv) join(p person, group string) {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/groups/"+group+"/invites", map[string]any{"userId": p.ID})
	require.Equal(e.t, http.StatusNoContent, rec.Code, rec.Body.String())
	var id string
	for _, inv := range e.inbox(p) {
		if inv["groupId"] == group {
			id = inv["id"].(string)
		}
	}
	require.NotEmpty(e.t, id)
	rec = e.send(http.MethodPost, "/v1/group-invites/"+id+"/accept", nil, p.Token)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

func (e *groupEnv) inbox(p person) []map[string]any {
	e.t.Helper()
	return items(e.t, e.send(http.MethodGet, "/v1/me/group-invites", nil, p.Token))
}

// post posts a message to a channel path and returns it.
func (e *groupEnv) post(channel, body string, token ...string) map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodPost, channel+"/messages", map[string]any{"body": body}, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

func (e *groupEnv) get(path string, token ...string) map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodGet, path, nil, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

func items(t *testing.T, rec *httptest.ResponseRecorder) []map[string]any {
	t.Helper()
	require.Less(t, rec.Code, 300, rec.Body.String())
	raw := decode[map[string]any](t, rec)["items"].([]any)
	out := make([]map[string]any, len(raw))
	for i, r := range raw {
		out[i] = r.(map[string]any)
	}
	return out
}

func bodies(t *testing.T, rec *httptest.ResponseRecorder) []string {
	t.Helper()
	out := []string{}
	for _, m := range items(t, rec) {
		out = append(out, m["body"].(string))
	}
	return out
}

func maps(v any) []map[string]any {
	raw, _ := v.([]any)
	out := make([]map[string]any, len(raw))
	for i, r := range raw {
		out[i] = r.(map[string]any)
	}
	return out
}

func channelPath(group, channel string) string {
	return fmt.Sprintf("/v1/groups/%s/channels/%s", group, channel)
}

var _ = time.Second
