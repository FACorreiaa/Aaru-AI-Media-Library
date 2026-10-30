package groups

import (
	"context"

	"github.com/google/uuid"
)

// EventType names a realtime event, as the wire spells it (RealtimeEvent.type).
type EventType string

// The events (GroupEvent in RealtimeHub.swift).
const (
	EventMessageCreated EventType = "message.created"
	EventMessageUpdated EventType = "message.updated"
	EventMessageDeleted EventType = "message.deleted"
	EventTyping         EventType = "typing"
	// EventRead: the recipient read a channel on another device.
	EventRead EventType = "read"
	// EventGroupUpdated: name, channels, members or invites changed; refetch the group.
	EventGroupUpdated EventType = "group.updated"
	// EventGroupRemoved: the recipient is no longer in the group, or it is gone.
	EventGroupRemoved EventType = "group.removed"
	// EventInvitesChanged: the recipient's invites changed.
	EventInvitesChanged EventType = "invites.changed"
	EventShelfUpdated   EventType = "shelf.updated"
	// EventWatchUpdated: the party in a watch channel opened, changed state, or gained or lost a
	// ready member.
	EventWatchUpdated  EventType = "watch.updated"
	EventWatchReaction EventType = "watch.reaction"
	// EventAgentThinking: `@aaru` is working on an answer to that mention (MessageID).
	EventAgentThinking EventType = "agent.thinking"
)

// Event is something that happened in a group, for the members' open sockets (GRP-006). Writes
// stay on REST; a service publishes after its write commits, so an event never announces a row
// that is not there.
type Event struct {
	Type      EventType
	Group     uuid.UUID
	Channel   uuid.UUID
	MessageID uuid.UUID
	// Message is set for message.created and message.updated.
	Message *Message
	// BlockedBy are recipients who blocked the author: they get the message flagged.
	BlockedBy map[uuid.UUID]bool
	// VeiledFor are recipients behind the message's spoiler stamp: they get it veiled.
	VeiledFor map[uuid.UUID]bool
	// User is the typist or the reacting member.
	User  *User
	Emoji string
}

// Publisher fans events out to the recipients' open sockets.
type Publisher interface {
	Publish(ctx context.Context, event Event, recipients []uuid.UUID)
}

// NoEvents drops every event (no realtime gateway, tests).
type NoEvents struct{}

// Publish does nothing.
func (NoEvents) Publish(context.Context, Event, []uuid.UUID) {}
