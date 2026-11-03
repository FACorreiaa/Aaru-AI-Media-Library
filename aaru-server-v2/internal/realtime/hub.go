// Package realtime is the `/v1/ws` gateway (GRP-006): every open socket on this replica by
// user, the single-use tickets browsers open sockets with, and fan-out of group events
// (Realtime/RealtimeHub.swift, RealtimeRoutes.swift).
//
// One replica, as RT-001 assumes. A second replica needs cross-pod fan-out (ARCHITECTURE.md:
// Valkey pub/sub); that is documented, not built.
package realtime

import (
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/token"
	"context"
	"fmt"
	"log/slog"
	"runtime/debug"
	"sync"
	"time"

	"github.com/google/uuid"
)

// TicketLifetime is how long a browser ticket stays good.
const TicketLifetime = 60 * time.Second

// Hub limits.
const (
	// SendQueue is the frames one socket may have waiting. A socket that falls further behind
	// is dropped rather than slowing the writer that published.
	SendQueue = 64
	// MaxSocketsPerUser is the open sockets one user may hold on this replica.
	MaxSocketsPerUser = 10
	// TicketsPerMinute is the browser tickets one user may take a minute.
	TicketsPerMinute = 20
)

// writeTimeout bounds one frame to one socket: one slow socket must not hold up the rest.
const writeTimeout = 10 * time.Second

// Sink writes one text frame to one socket.
type Sink func(ctx context.Context, frame []byte) error

// Framer encodes an event for one recipient (RealtimeEvent JSON); false skips the recipient.
type Framer func(event groups.Event, recipient uuid.UUID) ([]byte, bool)

// DropReason is why the hub let go of a socket.
type DropReason int

const (
	// DropClosed is the socket's own end: Disconnect.
	DropClosed DropReason = iota
	// DropWriteFailed is a frame that could not be written.
	DropWriteFailed
	// DropSlow is a socket whose send queue is full.
	DropSlow
	// DropShutdown is the server shutting down (CloseAll).
	DropShutdown
)

type ticket struct {
	user      uuid.UUID
	expiresAt time.Time
}

// outbound is one queued frame, or (flushed set) a marker Flush waits on.
type outbound struct {
	frame   []byte
	flushed chan struct{}
}

// socket is one open connection: a bounded queue drained by its own writer goroutine, so a
// publisher only ever enqueues.
type socket struct {
	user, id uuid.UUID
	sink     Sink
	onDrop   func(DropReason)
	queue    chan outbound
	done     chan struct{}
	once     sync.Once
}

// Hub is the replica's open sockets and tickets. It implements groups.Publisher.
type Hub struct {
	// Frame encodes events; the HTTP layer sets it, since frames carry its DTOs.
	Frame Framer
	Log   *slog.Logger

	mu       sync.Mutex
	sockets  map[uuid.UUID]map[uuid.UUID]*socket
	tickets  map[string]ticket
	sweptAt  time.Time
	closing  bool
	issuance *ratelimit.FixedWindow
}

// NewHub is an empty hub.
func NewHub(frame Framer, log *slog.Logger) *Hub {
	if log == nil {
		log = slog.Default()
	}
	return &Hub{
		Frame: frame, Log: log, sockets: map[uuid.UUID]map[uuid.UUID]*socket{}, tickets: map[string]ticket{},
		issuance: ratelimit.New(TicketsPerMinute, time.Minute),
	}
}

// Connect registers a socket and returns its id; uuid.Nil when the user is at
// MaxSocketsPerUser or the hub is shutting down.
func (h *Hub) Connect(user uuid.UUID, sink Sink) uuid.UUID {
	id, _ := h.Attach(user, sink, nil)
	return id
}

// Attach registers a socket. onDrop (may be nil) runs once when the hub lets go of the socket
// for any reason but Disconnect, so the gateway can close it. False when the user is at
// MaxSocketsPerUser or the hub is shutting down.
func (h *Hub) Attach(user uuid.UUID, sink Sink, onDrop func(DropReason)) (uuid.UUID, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closing || len(h.sockets[user]) >= MaxSocketsPerUser {
		return uuid.Nil, false
	}
	s := &socket{
		user: user, id: uuid.New(), sink: sink, onDrop: onDrop,
		queue: make(chan outbound, SendQueue), done: make(chan struct{}),
	}
	if h.sockets[user] == nil {
		h.sockets[user] = map[uuid.UUID]*socket{}
	}
	h.sockets[user][s.id] = s
	go h.write(s)
	return s.id, true
}

// write drains one socket's queue until the socket is dropped.
func (h *Hub) write(s *socket) {
	defer func() {
		if r := recover(); r != nil {
			h.Log.Error("Recovered a panic", "where", "realtime writer", "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
			h.drop(s, DropWriteFailed)
		}
	}()
	for {
		select {
		case <-s.done:
			return
		case item := <-s.queue:
			if item.flushed != nil {
				close(item.flushed)
				continue
			}
			ctx, cancel := context.WithTimeout(context.Background(), writeTimeout)
			err := s.sink(ctx, item.frame)
			cancel()
			if err != nil {
				h.Log.Debug("Dropping a socket that failed a write", "user", s.user)
				h.drop(s, DropWriteFailed)
				return
			}
		}
	}
}

// drop lets go of a socket once: its writer stops, and onDrop runs unless the owner asked.
// Never called with mu held.
func (h *Hub) drop(s *socket, reason DropReason) {
	s.once.Do(func() {
		close(s.done)
		h.mu.Lock()
		if h.sockets[s.user][s.id] == s {
			delete(h.sockets[s.user], s.id)
			if len(h.sockets[s.user]) == 0 {
				delete(h.sockets, s.user)
			}
		}
		h.mu.Unlock()
		if reason != DropClosed && s.onDrop != nil {
			defer func() {
				if r := recover(); r != nil {
					h.Log.Error("Recovered a panic", "where", "realtime drop", "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
				}
			}()
			s.onDrop(reason)
		}
	})
}

// Disconnect forgets a socket.
func (h *Hub) Disconnect(user, connection uuid.UUID) {
	h.mu.Lock()
	s := h.sockets[user][connection]
	h.mu.Unlock()
	if s != nil {
		h.drop(s, DropClosed)
	}
}

// ConnectionCount is the user's open sockets on this replica.
func (h *Hub) ConnectionCount(user uuid.UUID) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.sockets[user])
}

// AllowTicket counts one ticket for the user: false past TicketsPerMinute.
func (h *Hub) AllowTicket(user uuid.UUID, now time.Time) bool {
	return h.issuance.Allow(user.String(), now)
}

// IssueTicket is a single-use ticket for a browser socket, valid for TicketLifetime.
func (h *Hub) IssueTicket(user uuid.UUID, now time.Time) (string, time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	// Expired tickets are swept at most once a lifetime, not on every issue.
	if now.Sub(h.sweptAt) >= TicketLifetime {
		h.sweptAt = now
		for k, t := range h.tickets {
			if !t.expiresAt.After(now) {
				delete(h.tickets, k)
			}
		}
	}
	value := token.Generate()
	expiresAt := now.Add(TicketLifetime)
	h.tickets[value] = ticket{user: user, expiresAt: expiresAt}
	return value, expiresAt
}

// Redeem is the ticket's user, once. A second use or an expired ticket is false.
func (h *Hub) Redeem(value string, now time.Time) (uuid.UUID, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	t, ok := h.tickets[value]
	if !ok {
		return uuid.Nil, false
	}
	delete(h.tickets, value)
	if !t.expiresAt.After(now) {
		return uuid.Nil, false
	}
	return t.user, true
}

// Publish queues the event for every open socket of every recipient, each in its own frame,
// and returns without waiting for any socket: each socket's writer sends it. A socket whose
// queue is full, or that fails a write, is dropped.
func (h *Hub) Publish(_ context.Context, event groups.Event, recipients []uuid.UUID) {
	if h.Frame == nil {
		return
	}
	type target struct {
		user    uuid.UUID
		sockets []*socket
	}
	seen := map[uuid.UUID]bool{}
	var targets []target
	h.mu.Lock()
	for _, user := range recipients {
		if seen[user] {
			continue
		}
		seen[user] = true
		if len(h.sockets[user]) == 0 {
			continue
		}
		t := target{user: user}
		for _, s := range h.sockets[user] {
			t.sockets = append(t.sockets, s)
		}
		targets = append(targets, t)
	}
	h.mu.Unlock()
	// Frames are encoded outside the lock: other sockets connect and disconnect meanwhile.
	for _, t := range targets {
		frame, ok := h.Frame(event, t.user)
		if !ok {
			continue
		}
		for _, s := range t.sockets {
			h.enqueue(s, frame)
		}
	}
}

func (h *Hub) enqueue(s *socket, frame []byte) {
	select {
	case <-s.done:
		return
	default:
	}
	select {
	case s.queue <- outbound{frame: frame}:
	case <-s.done:
	default:
		h.Log.Warn("Dropping a socket that fell behind", "user", s.user)
		h.drop(s, DropSlow)
	}
}

// Flush waits until every frame queued so far has been written or its socket dropped, or ctx
// ends. Publish does not wait for sockets; tests and shutdown do.
func (h *Hub) Flush(ctx context.Context) {
	h.mu.Lock()
	var all []*socket
	for _, byID := range h.sockets {
		for _, s := range byID {
			all = append(all, s)
		}
	}
	h.mu.Unlock()
	for _, s := range all {
		marker := outbound{flushed: make(chan struct{})}
		select {
		case s.queue <- marker:
		case <-s.done:
			continue
		case <-ctx.Done():
			return
		}
		select {
		case <-marker.flushed:
		case <-s.done:
		case <-ctx.Done():
			return
		}
	}
}

// CloseAll drops every socket for a shutdown (each gateway closes its socket with 1001 going
// away) and refuses new ones. It waits for the closes, or until ctx ends.
func (h *Hub) CloseAll(ctx context.Context) {
	h.mu.Lock()
	h.closing = true
	var all []*socket
	for _, byID := range h.sockets {
		for _, s := range byID {
			all = append(all, s)
		}
	}
	h.mu.Unlock()
	done := make(chan struct{})
	go func() {
		defer close(done)
		var wg sync.WaitGroup
		for _, s := range all {
			wg.Go(func() { h.drop(s, DropShutdown) })
		}
		wg.Wait()
	}()
	select {
	case <-done:
	case <-ctx.Done():
	}
}
