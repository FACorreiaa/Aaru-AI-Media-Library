package realtime

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/middleware"
	"aaru-go-api/internal/token"
	"context"
	"encoding/json"
	"slices"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

// Gateway limits (RealtimeRoutes.swift).
const (
	// MaxInboundBytes is the largest frame a client may send; a typing command is about 120 bytes.
	MaxInboundBytes = 1024
	// TypingInterval: typing frames per channel per connection count at most this often.
	TypingInterval = 3 * time.Second
	// ReactionInterval: watch-party reactions per connection count at most this often.
	ReactionInterval = time.Second
	// PingInterval keeps a 60 s-idle proxy from closing the socket.
	PingInterval = 25 * time.Second
)

// Commands are what a socket may ask for: typing and watch-party reactions. Writes stay on REST.
type Commands interface {
	Typing(ctx context.Context, group, channel, viewer uuid.UUID) error
	React(ctx context.Context, group, channel uuid.UUID, emoji string, viewer uuid.UUID) error
}

// Sessions resolves an app's bearer token hash to its user.
type Sessions interface {
	UserIDForTokenHash(ctx context.Context, hash string, now time.Time) (uuid.UUID, bool, error)
}

// Gateway is `GET /v1/ws`: one socket per signed-in client, events out, typing and reactions in.
//
// Apps send their bearer token on the upgrade; a browser cannot, so it brings a single-use ticket
// from `POST /v1/realtime/ticket`. A ticket only works from an allowed Origin, so another site
// cannot open a socket with it. A bearer token cannot come from a browser socket, so its Origin
// (some clients send one) is not checked.
type Gateway struct {
	Hub            *Hub
	Commands       Commands
	Sessions       Sessions
	AllowedOrigins []string
	// Ping is the keep-alive interval; zero means PingInterval.
	Ping time.Duration
}

var errOrigin = apperr.Forbidden("This origin may not open a socket.")

// authenticate signs in an upgrade by bearer token, or by ticket from an allowed Origin.
func (g *Gateway) authenticate(c echo.Context) (uuid.UUID, error) {
	req := c.Request()
	if bearer := middleware.BearerToken(req.Header.Get("Authorization")); bearer != "" {
		user, ok, err := g.Sessions.UserIDForTokenHash(req.Context(), token.Hash(bearer), time.Now())
		if err != nil {
			return uuid.Nil, err
		}
		if ok {
			return user, nil
		}
		return uuid.Nil, apperr.Unauthorized()
	}
	if ticket := req.URL.Query().Get("ticket"); req.URL.Query().Has("ticket") {
		// Only a browser brings a ticket, and a browser always says where the page came from.
		origin := req.Header.Get("Origin")
		if origin == "" || !slices.Contains(g.AllowedOrigins, origin) {
			return uuid.Nil, errOrigin
		}
		if user, ok := g.Hub.Redeem(ticket, time.Now()); ok {
			return user, nil
		}
	}
	return uuid.Nil, apperr.Unauthorized()
}

// Handle is the upgrade route.
func (g *Gateway) Handle(c echo.Context) error {
	user, err := g.authenticate(c)
	if err != nil {
		return err
	}
	// The origin rule is ours (above); the library's same-origin check would refuse every app.
	conn, err := websocket.Accept(c.Response(), c.Request(), &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return nil //nolint:nilerr // Accept already answered the failed upgrade
	}
	defer func() { _ = conn.CloseNow() }()
	conn.SetReadLimit(MaxInboundBytes)
	ctx, cancel := context.WithCancel(context.WithoutCancel(c.Request().Context()))
	defer cancel()

	connection := g.Hub.Connect(user, func(ctx context.Context, frame []byte) error {
		return conn.Write(ctx, websocket.MessageText, frame)
	})
	defer g.Hub.Disconnect(user, connection)

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"type":"ready"}`)); err != nil {
		return nil
	}
	go g.keepAlive(ctx, conn, cancel)
	g.read(ctx, conn, user)
	_ = conn.Close(websocket.StatusNormalClosure, "")
	return nil
}

func (g *Gateway) keepAlive(ctx context.Context, conn *websocket.Conn, cancel context.CancelFunc) {
	every := g.Ping
	if every <= 0 {
		every = PingInterval
	}
	ticker := time.NewTicker(every)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			pctx, pcancel := context.WithTimeout(ctx, every)
			err := conn.Ping(pctx)
			pcancel()
			if err != nil {
				cancel()
				return
			}
		}
	}
}

func (g *Gateway) read(ctx context.Context, conn *websocket.Conn, user uuid.UUID) {
	lastTyping := map[uuid.UUID]time.Time{}
	var lastReaction time.Time
	for {
		kind, data, err := conn.Read(ctx)
		if err != nil {
			// Closed, too large, or the ping failed: the socket is done.
			return
		}
		if kind != websocket.MessageText {
			continue
		}
		cmd, ok := ParseCommand(data)
		if !ok {
			continue
		}
		now := time.Now()
		// A frame for a group the user is not in is dropped like a malformed one.
		switch cmd.Type {
		case "typing":
			if last, seen := lastTyping[cmd.Channel]; seen && now.Sub(last) < TypingInterval {
				continue
			}
			lastTyping[cmd.Channel] = now
			_ = g.Commands.Typing(ctx, cmd.Group, cmd.Channel, user)
		case "react":
			if now.Sub(lastReaction) < ReactionInterval {
				continue
			}
			lastReaction = now
			_ = g.Commands.React(ctx, cmd.Group, cmd.Channel, cmd.Emoji, user)
		}
	}
}

// Command is one inbound frame: typing in a channel, or a reaction in a watch channel.
type Command struct {
	Type    string
	Group   uuid.UUID
	Channel uuid.UUID
	Emoji   string
}

// ParseCommand reads a RealtimeCommand; false for anything malformed.
func ParseCommand(data []byte) (Command, bool) {
	var raw struct {
		Type      string  `json:"type"`
		GroupID   *string `json:"groupId"`
		ChannelID *string `json:"channelId"`
		Emoji     *string `json:"emoji"`
	}
	if json.Unmarshal(data, &raw) != nil || raw.GroupID == nil || raw.ChannelID == nil {
		return Command{}, false
	}
	group, err := uuid.Parse(*raw.GroupID)
	if err != nil {
		return Command{}, false
	}
	channel, err := uuid.Parse(*raw.ChannelID)
	if err != nil {
		return Command{}, false
	}
	switch raw.Type {
	case "typing":
		return Command{Type: "typing", Group: group, Channel: channel}, true
	case "react":
		if raw.Emoji == nil {
			return Command{}, false
		}
		return Command{Type: "react", Group: group, Channel: channel, Emoji: *raw.Emoji}, true
	default:
		return Command{}, false
	}
}
