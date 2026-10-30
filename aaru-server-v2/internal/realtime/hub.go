// Package realtime is the `/v1/ws` gateway (GRP-006): every open socket on this replica by
// user, the single-use tickets browsers open sockets with, and fan-out of group events
// (Realtime/RealtimeHub.swift, RealtimeRoutes.swift).
//
// One replica, as RT-001 assumes. A second replica needs cross-pod fan-out (ARCHITECTURE.md:
// Valkey pub/sub); that is documented, not built.
package realtime

import (
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/token"
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
)

// TicketLifetime is how long a browser ticket stays good.
const TicketLifetime = 60 * time.Second

// writeTimeout bounds one frame to one socket: one slow socket must not hold up the rest.
const writeTimeout = 10 * time.Second

// Sink writes one text frame to one socket.
type Sink func(ctx context.Context, frame []byte) error

// Framer encodes an event for one recipient (RealtimeEvent JSON); false skips the recipient.
type Framer func(event groups.Event, recipient uuid.UUID) ([]byte, bool)

type ticket struct {
	user      uuid.UUID
	expiresAt time.Time
}

// Hub is the replica's open sockets and tickets. It implements groups.Publisher.
type Hub struct {
	// Frame encodes events; the HTTP layer sets it, since frames carry its DTOs.
	Frame Framer
	Log   *slog.Logger

	mu      sync.Mutex
	sinks   map[uuid.UUID]map[uuid.UUID]Sink
	tickets map[string]ticket
}

// NewHub is an empty hub.
func NewHub(frame Framer, log *slog.Logger) *Hub {
	if log == nil {
		log = slog.Default()
	}
	return &Hub{Frame: frame, Log: log, sinks: map[uuid.UUID]map[uuid.UUID]Sink{}, tickets: map[string]ticket{}}
}

// Connect registers a socket and returns its id.
func (h *Hub) Connect(user uuid.UUID, sink Sink) uuid.UUID {
	h.mu.Lock()
	defer h.mu.Unlock()
	id := uuid.New()
	if h.sinks[user] == nil {
		h.sinks[user] = map[uuid.UUID]Sink{}
	}
	h.sinks[user][id] = sink
	return id
}

// Disconnect forgets a socket.
func (h *Hub) Disconnect(user, connection uuid.UUID) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.sinks[user], connection)
	if len(h.sinks[user]) == 0 {
		delete(h.sinks, user)
	}
}

// ConnectionCount is the user's open sockets on this replica.
func (h *Hub) ConnectionCount(user uuid.UUID) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.sinks[user])
}

// IssueTicket is a single-use ticket for a browser socket, valid for TicketLifetime.
func (h *Hub) IssueTicket(user uuid.UUID, now time.Time) (string, time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for k, t := range h.tickets {
		if !t.expiresAt.After(now) {
			delete(h.tickets, k)
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

type delivery struct {
	user, connection uuid.UUID
	sink             Sink
	frame            []byte
}

// Publish writes the event to every open socket of every recipient, each in its own frame.
// A socket that fails a write is dropped.
func (h *Hub) Publish(ctx context.Context, event groups.Event, recipients []uuid.UUID) {
	if h.Frame == nil {
		return
	}
	seen := map[uuid.UUID]bool{}
	var deliveries []delivery
	h.mu.Lock()
	for _, user := range recipients {
		if seen[user] {
			continue
		}
		seen[user] = true
		connections := h.sinks[user]
		if len(connections) == 0 {
			continue
		}
		frame, ok := h.Frame(event, user)
		if !ok {
			continue
		}
		for id, sink := range connections {
			deliveries = append(deliveries, delivery{user: user, connection: id, sink: sink, frame: frame})
		}
	}
	h.mu.Unlock()
	if len(deliveries) == 0 {
		return
	}
	// The write already committed; a request that ends must not cut the fan-out short.
	base := context.WithoutCancel(ctx)
	var wg sync.WaitGroup
	failed := make([]bool, len(deliveries))
	for i, d := range deliveries {
		wg.Go(func() {
			wctx, cancel := context.WithTimeout(base, writeTimeout)
			defer cancel()
			if err := d.sink(wctx, d.frame); err != nil {
				failed[i] = true
			}
		})
	}
	wg.Wait()
	for i, d := range deliveries {
		if failed[i] {
			h.Log.DebugContext(ctx, "Dropping a socket that failed a write", "user", d.user)
			h.Disconnect(d.user, d.connection)
		}
	}
}
