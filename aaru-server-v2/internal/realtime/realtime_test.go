package realtime

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/groups"
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/labstack/echo/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func quiet() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func plainFrame(e groups.Event, _ uuid.UUID) ([]byte, bool) {
	return []byte(`{"type":"` + string(e.Type) + `"}`), true
}

func flush(t *testing.T, h *Hub) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	h.Flush(ctx)
	require.NoError(t, ctx.Err(), "flush timed out")
}

type counter struct{ n atomic.Int32 }

func (c *counter) sink(context.Context, []byte) error { c.n.Add(1); return nil }

func TestPublishDoesNotWaitOnASlowSocketAndDropsItWhenItFallsBehind(t *testing.T) {
	hub := NewHub(plainFrame, quiet())
	user := uuid.New()
	release := make(chan struct{})
	t.Cleanup(func() { close(release) })
	blocked := func(ctx context.Context, _ []byte) error {
		select {
		case <-release:
		case <-ctx.Done():
		}
		return ctx.Err()
	}
	var dropped atomic.Int32
	_, ok := hub.Attach(user, blocked, func(r DropReason) {
		if r == DropSlow {
			dropped.Add(1)
		}
	})
	require.True(t, ok)
	fast := &counter{}
	hub.Connect(user, fast.sink)

	// The healthy socket gets to drain between frames: this test is about the blocked one, and a
	// tight loop can outrun any writer's queue.
	var publishing time.Duration
	for i := range SendQueue + 5 {
		start := time.Now()
		hub.Publish(context.Background(), groups.Event{Type: groups.EventGroupUpdated}, []uuid.UUID{user})
		publishing += time.Since(start)
		require.Eventually(t, func() bool { return fast.n.Load() == int32(i+1) }, 5*time.Second, 100*time.Microsecond)
	}
	assert.Less(t, publishing, 100*time.Millisecond, "publishing never waits on a socket")
	require.Eventually(t, func() bool { return dropped.Load() == 1 }, 5*time.Second, 5*time.Millisecond,
		"the socket that fell behind is dropped")
	flush(t, hub)
	assert.EqualValues(t, 1, dropped.Load(), "once")
	assert.EqualValues(t, SendQueue+5, fast.n.Load(), "the other socket got every frame")
	assert.Equal(t, 1, hub.ConnectionCount(user))
}

func TestAPanickingSinkDropsOnlyItsSocket(t *testing.T) {
	hub := NewHub(plainFrame, quiet())
	user := uuid.New()
	hub.Connect(user, func(context.Context, []byte) error { panic("boom") })
	ok := &counter{}
	hub.Connect(user, ok.sink)
	hub.Publish(context.Background(), groups.Event{Type: groups.EventGroupUpdated}, []uuid.UUID{user})
	flush(t, hub)
	assert.EqualValues(t, 1, ok.n.Load())
	assert.Equal(t, 1, hub.ConnectionCount(user))
}

func TestSocketsPerUserAreCappedAndTicketsRateLimited(t *testing.T) {
	hub := NewHub(plainFrame, quiet())
	user := uuid.New()
	for range MaxSocketsPerUser {
		_, ok := hub.Attach(user, (&counter{}).sink, nil)
		require.True(t, ok)
	}
	_, ok := hub.Attach(user, (&counter{}).sink, nil)
	assert.False(t, ok)
	_, ok = hub.Attach(uuid.New(), (&counter{}).sink, nil)
	assert.True(t, ok, "the cap is per user")

	now := time.Now()
	for range TicketsPerMinute {
		require.True(t, hub.AllowTicket(user, now))
	}
	assert.False(t, hub.AllowTicket(user, now))
	assert.True(t, hub.AllowTicket(user, now.Add(time.Minute)))
}

func TestCloseAllDropsEverySocketForShutdownAndRefusesNewOnes(t *testing.T) {
	hub := NewHub(plainFrame, quiet())
	var reasons sync.Map
	for range 3 {
		user := uuid.New()
		_, ok := hub.Attach(user, (&counter{}).sink, func(r DropReason) { reasons.Store(user, r) })
		require.True(t, ok)
	}
	hub.CloseAll(context.Background())
	n := 0
	reasons.Range(func(_, v any) bool {
		n++
		assert.Equal(t, DropShutdown, v)
		return true
	})
	assert.Equal(t, 3, n)
	_, ok := hub.Attach(uuid.New(), (&counter{}).sink, nil)
	assert.False(t, ok)
}

// MARK: Gateway end to end

type oneSession struct{ user uuid.UUID }

func (s oneSession) UserIDForTokenHash(context.Context, string, time.Time) (uuid.UUID, bool, error) {
	return s.user, true, nil
}

type countingCommands struct {
	mu     sync.Mutex
	typing map[uuid.UUID]int
	fail   map[uuid.UUID]error
}

func (c *countingCommands) Typing(_ context.Context, _, channel, _ uuid.UUID) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.typing[channel]++
	return c.fail[channel]
}

func (c *countingCommands) React(context.Context, uuid.UUID, uuid.UUID, string, uuid.UUID) error {
	return nil
}

func (c *countingCommands) calls() (total int, by map[uuid.UUID]int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	by = map[uuid.UUID]int{}
	for k, v := range c.typing {
		by[k] = v
		total += v
	}
	return total, by
}

func serveGateway(t *testing.T, hub *Hub, commands Commands) (url string, user uuid.UUID) {
	t.Helper()
	user = uuid.New()
	g := &Gateway{Hub: hub, Commands: commands, Sessions: oneSession{user}}
	e := echo.New()
	e.GET("/v1/ws", g.Handle)
	server := httptest.NewServer(e)
	t.Cleanup(server.Close)
	return "ws" + strings.TrimPrefix(server.URL, "http") + "/v1/ws", user
}

func dial(ctx context.Context, t *testing.T, url string) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: http.Header{"Authorization": {"Bearer x"}}})
	require.NoError(t, err)
	t.Cleanup(func() { _ = conn.CloseNow() })
	_, data, err := conn.Read(ctx)
	require.NoError(t, err)
	require.JSONEq(t, `{"type":"ready"}`, string(data))
	return conn
}

func typing(channel uuid.UUID) []byte {
	return []byte(`{"type":"typing","groupId":"` + uuid.NewString() + `","channelId":"` + channel.String() + `"}`)
}

func TestInboundFramesAreBucketedPerConnection(t *testing.T) {
	commands := &countingCommands{typing: map[uuid.UUID]int{}, fail: map[uuid.UUID]error{}}
	url, _ := serveGateway(t, NewHub(plainFrame, quiet()), commands)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn := dial(ctx, t, url)

	start := time.Now()
	for range 1000 {
		if conn.Write(ctx, websocket.MessageText, typing(uuid.New())) != nil {
			break // closed for flooding
		}
	}
	elapsed := time.Since(start)
	// The server either closed the socket for flooding or reads the rest; either way it ends.
	_, _, err := conn.Read(ctx)
	require.Error(t, err)
	assert.Equal(t, websocket.StatusPolicyViolation, websocket.CloseStatus(err))
	total, _ := commands.calls()
	allowed := InboundBurst + int(elapsed.Seconds()*InboundFramesPerSecond) + 1
	assert.LessOrEqual(t, total, allowed, "commands reached are bounded by the bucket")
	assert.Positive(t, total)
}

func TestTypingIsThrottledOnlyAfterItSucceeds(t *testing.T) {
	denied, allowed := uuid.New(), uuid.New()
	commands := &countingCommands{
		typing: map[uuid.UUID]int{},
		fail:   map[uuid.UUID]error{denied: apperr.NotFound(), allowed: nil},
	}
	hub := NewHub(plainFrame, quiet())
	url, user := serveGateway(t, hub, commands)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn := dial(ctx, t, url)
	for _, ch := range []uuid.UUID{denied, denied, allowed, allowed} {
		require.NoError(t, conn.Write(ctx, websocket.MessageText, typing(ch)))
	}
	require.Eventually(t, func() bool {
		_, by := commands.calls()
		return by[denied] == 2 && by[allowed] == 1
	}, 5*time.Second, 10*time.Millisecond)
	assert.Equal(t, 1, hub.ConnectionCount(user))
}

func TestShutdownClosesLiveSocketsWithGoingAway(t *testing.T) {
	hub := NewHub(plainFrame, quiet())
	url, user := serveGateway(t, hub, &countingCommands{typing: map[uuid.UUID]int{}})
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn := dial(ctx, t, url)
	require.Eventually(t, func() bool { return hub.ConnectionCount(user) == 1 }, 5*time.Second, 10*time.Millisecond)

	closed := make(chan struct{})
	go func() {
		defer close(closed)
		hub.CloseAll(ctx)
	}()
	_, _, err := conn.Read(ctx)
	require.Error(t, err)
	assert.Equal(t, websocket.StatusGoingAway, websocket.CloseStatus(err))
	<-closed
	assert.Equal(t, 0, hub.ConnectionCount(user))
}

func TestFrameBucketRefills(t *testing.T) {
	now := time.Now()
	b := newFrameBucket(now)
	for range InboundBurst {
		require.True(t, b.take(now))
	}
	assert.False(t, b.take(now))
	assert.True(t, b.take(now.Add(time.Second/InboundFramesPerSecond)))
}

// CON-004: closing a socket that fell behind can take seconds. The poster and the other sockets
// do not wait for it.
func TestPublishDoesNotWaitForASlowSocketToClose(t *testing.T) {
	hub := NewHub(plainFrame, quiet())
	user := uuid.New()
	writing := make(chan struct{}, 1)
	release := make(chan struct{})
	defer close(release)
	closing := make(chan struct{})
	var once sync.Once
	_, ok := hub.Attach(user, func(ctx context.Context, _ []byte) error {
		select {
		case writing <- struct{}{}:
		default:
		}
		select {
		case <-release:
		case <-ctx.Done():
		}
		return nil
	}, func(DropReason) {
		once.Do(func() { close(closing) })
		<-release // a close that takes as long as it likes
	})
	require.True(t, ok)

	event := groups.Event{Type: groups.EventMessageCreated, Group: uuid.New(), Channel: uuid.New()}
	hub.Publish(context.Background(), event, []uuid.UUID{user})
	<-writing
	started := time.Now()
	for range SendQueue + 2 {
		hub.Publish(context.Background(), event, []uuid.UUID{user})
	}
	assert.Less(t, time.Since(started), time.Second)
	select {
	case <-closing:
	case <-time.After(5 * time.Second):
		t.Fatal("the socket that fell behind was not dropped")
	}
}
