package httpapi

import (
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/realtime"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// RealtimeTests.swift: the realtime gateway (GRP-006).

func quietLog() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func TestRealtimeHubDeliversOnlyToRecipientsAndDropsAFailingSocket(t *testing.T) {
	hub := realtime.NewHub(RealtimeFrame, quietLog())
	ana, kai := uuid.New(), uuid.New()
	phone, laptop, other := &frames{}, &frames{}, &frames{}
	hub.Connect(ana, phone.sink)
	hub.Connect(ana, laptop.sink)
	hub.Connect(kai, other.sink)
	hub.Connect(kai, func(context.Context, []byte) error { return errors.New("gone") })

	ctx := context.Background()
	hub.Publish(ctx, groups.Event{Type: groups.EventGroupUpdated, Group: uuid.New()}, []uuid.UUID{ana})
	assert.Equal(t, []string{"group.updated"}, phone.types())
	assert.Equal(t, []string{"group.updated"}, laptop.types())
	assert.Empty(t, other.types())

	hub.Publish(ctx, groups.Event{Type: groups.EventInvitesChanged}, []uuid.UUID{kai})
	assert.Equal(t, []string{"invites.changed"}, other.types())
	assert.Equal(t, 1, hub.ConnectionCount(kai))
}

func TestRealtimeTicketWorksOnceAndOnlyForAMinute(t *testing.T) {
	hub := realtime.NewHub(RealtimeFrame, quietLog())
	user := uuid.New()
	now := time.Now()
	ticket, expiresAt := hub.IssueTicket(user, now)
	assert.Equal(t, now.Add(60*time.Second), expiresAt)
	got, ok := hub.Redeem(ticket, now)
	assert.True(t, ok)
	assert.Equal(t, user, got)
	_, ok = hub.Redeem(ticket, now)
	assert.False(t, ok)
	late, _ := hub.IssueTicket(user, now)
	_, ok = hub.Redeem(late, now.Add(61*time.Second))
	assert.False(t, ok)
}

func TestRealtimeGroupWritesReachMembersFlaggedForBlockers(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	ana := env.friend(env.user)
	group, general := env.createGroup("Film club")
	anaSocket := env.listen(ana.uid)
	stranger, _ := env.signIn()
	strangerSocket := env.listen(stranger)

	env.join(ana, group)
	assert.Contains(t, anaSocket.types(), "group.updated")

	channel := channelPath(group, general)
	posted := env.post(channel, "hello")
	all := anaSocket.all()
	created := all[len(all)-1]
	assert.Equal(t, "message.created", created["type"])
	assert.Equal(t, general, created["channelId"])
	message := created["message"].(map[string]any)
	assert.Equal(t, posted["id"], message["id"])
	assert.Equal(t, false, message["fromBlocked"])

	env.block(ana.uid, env.user)
	env.unfriend(ana.uid, env.user)
	env.post(channel, "still me")
	all = anaSocket.all()
	assert.Equal(t, true, all[len(all)-1]["message"].(map[string]any)["fromBlocked"])

	// Typing goes to the others, never back to the typist.
	mySocket := env.listen(env.user)
	require.NoError(t, env.server.Groups.Typing(context.Background(), uuid.MustParse(group), uuid.MustParse(general), env.user))
	types := anaSocket.types()
	assert.Equal(t, "typing", types[len(types)-1])
	assert.Empty(t, mySocket.types())

	// Removing Ana tells her she is out.
	rec := env.send(http.MethodDelete, "/v1/groups/"+group+"/members/"+ana.ID, nil)
	require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	types = anaSocket.types()
	assert.Equal(t, "group.removed", types[len(types)-1])
	assert.Empty(t, strangerSocket.types())
}

// readTypes dials /v1/ws, reads the first frame and closes.
func readFirstType(t *testing.T, url string, header http.Header) (string, *http.Response, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, resp, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		return "", resp, err
	}
	defer func() { _ = conn.CloseNow() }()
	_, data, err := conn.Read(ctx)
	require.NoError(t, err)
	var frame map[string]any
	require.NoError(t, json.Unmarshal(data, &frame))
	_ = conn.Close(websocket.StatusNormalClosure, "")
	return frame["type"].(string), resp, nil
}

func TestRealtimeSocketUpgradesWithBearerOrTicketAndRefusesForeignOrigins(t *testing.T) {
	const origin = "http://localhost"
	env := newGroupEnv(t, func(d *Deps) { d.Config.RealtimeOrigins = []string{origin} })
	server := httptest.NewServer(env.echo)
	t.Cleanup(server.Close)
	socket := "ws" + strings.TrimPrefix(server.URL, "http") + "/v1/ws"

	kind, _, err := readFirstType(t, socket, http.Header{"Authorization": {"Bearer " + env.bearer}})
	require.NoError(t, err)
	assert.Equal(t, "ready", kind)

	ticket := env.json(http.MethodPost, "/v1/realtime/ticket", nil)
	value := ticket["ticket"].(string)
	assert.True(t, strings.HasPrefix(ticket["url"].(string), "wss://api.aaruapp.com/v1/ws?ticket="), ticket["url"])

	browser := http.Header{"Origin": {origin}}
	kind, _, err = readFirstType(t, socket+"?ticket="+value, browser)
	require.NoError(t, err)
	assert.Equal(t, "ready", kind)
	// Spent.
	_, resp, err := readFirstType(t, socket+"?ticket="+value, browser)
	require.Error(t, err)
	assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	_, resp, err = readFirstType(t, socket, nil)
	require.Error(t, err)
	assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
}

func TestRealtimeOnlyAWellFormedFrameIsACommand(t *testing.T) {
	group, channel := uuid.New(), uuid.New()
	typing := `{"type":"typing","groupId":"` + up(group) + `","channelId":"` + up(channel) + `"}`
	cmd, ok := realtime.ParseCommand([]byte(typing))
	assert.True(t, ok)
	assert.Equal(t, realtime.Command{Type: "typing", Group: group, Channel: channel}, cmd)
	react := `{"type":"react","groupId":"` + up(group) + `","channelId":"` + up(channel) + `","emoji":"🔥"}`
	cmd, ok = realtime.ParseCommand([]byte(react))
	assert.True(t, ok)
	assert.Equal(t, realtime.Command{Type: "react", Group: group, Channel: channel, Emoji: "🔥"}, cmd)
	for _, bad := range []string{
		`{"type":"typing","groupId":"x","channelId":"y"}`,
		`{"type":"shout","groupId":"` + up(group) + `","channelId":"` + up(channel) + `"}`,
		"not json",
	} {
		_, ok := realtime.ParseCommand([]byte(bad))
		assert.False(t, ok, bad)
	}
}

func TestRealtimeForeignOriginTicketIsRefusedAndStaysUnspent(t *testing.T) {
	env := newGroupEnv(t)
	user := uuid.New()
	ticket, _ := env.server.Realtime.IssueTicket(user, time.Now())
	for _, origin := range []string{"https://evil.example", ""} {
		req := httptest.NewRequest(http.MethodGet, "/v1/ws?ticket="+ticket, nil)
		req.Header.Set("Upgrade", "websocket")
		req.Header.Set("Connection", "upgrade")
		if origin != "" {
			req.Header.Set("Origin", origin)
		}
		rec := httptest.NewRecorder()
		env.echo.ServeHTTP(rec, req)
		assert.Equal(t, http.StatusForbidden, rec.Code, origin)
	}
	got, ok := env.server.Realtime.Redeem(ticket, time.Now())
	assert.True(t, ok)
	assert.Equal(t, user, got)
}
