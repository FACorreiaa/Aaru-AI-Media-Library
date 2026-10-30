package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/realtime"
	"context"
	"encoding/json"
	"net/url"
	"time"

	"github.com/google/uuid"
)

// CreateRealtimeTicket is POST /v1/realtime/ticket: a single-use ticket a browser opens
// `/v1/ws` with, since it cannot send a bearer token on the upgrade.
func (s *Server) CreateRealtimeTicket(ctx context.Context, _ api.CreateRealtimeTicketRequestObject) (api.CreateRealtimeTicketResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	ticket, expiresAt := s.Realtime.IssueTicket(user, time.Now())
	socket := url.URL{Scheme: "wss", Path: "/v1/ws", RawQuery: url.Values{"ticket": {ticket}}.Encode()}
	if base := s.Config.PublicBaseURL; base != nil {
		socket.Host = base.Host
		if base.Scheme == "http" {
			socket.Scheme = "ws"
		}
	}
	return api.CreateRealtimeTicket200JSONResponse(api.RealtimeTicket{
		Ticket: ticket, Url: socket.String(), ExpiresAt: apitime.From(expiresAt),
	}), nil
}

// realtimeGateway is `GET /v1/ws`.
func (s *Server) realtimeGateway() *realtime.Gateway {
	var commands realtime.Commands = noCommands{}
	if s.Groups != nil {
		commands = s.Groups
	}
	return &realtime.Gateway{
		Hub: s.Realtime, Commands: commands, Sessions: sessionLookup{s.q}, AllowedOrigins: s.Config.RealtimeOrigins,
	}
}

type noCommands struct{}

func (noCommands) Typing(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) error { return nil }
func (noCommands) React(context.Context, uuid.UUID, uuid.UUID, string, uuid.UUID) error {
	return nil
}

// RealtimeFrame is the RealtimeEvent JSON for one recipient: whether the author is blocked by
// them, and whether the message is veiled for them, differ per recipient.
func RealtimeFrame(e groups.Event, recipient uuid.UUID) ([]byte, bool) {
	dto := RealtimeEventDTO(e, recipient)
	data, err := json.Marshal(dto)
	if err != nil {
		return nil, false
	}
	return data, true
}

// RealtimeEventDTO is RealtimeHub.dto: one event as one recipient sees it.
func RealtimeEventDTO(e groups.Event, recipient uuid.UUID) api.RealtimeEvent {
	dto := api.RealtimeEvent{Type: api.RealtimeEventType(e.Type)}
	group, channel, message := apiid.From(e.Group), apiid.From(e.Channel), apiid.From(e.MessageID)
	switch e.Type {
	case groups.EventMessageCreated, groups.EventMessageUpdated:
		dto.GroupId, dto.ChannelId, dto.MessageId = &group, &channel, &message
		if e.Message != nil {
			m := GroupMessageDTO(*e.Message, e.BlockedBy[recipient], recipient, e.VeiledFor[recipient])
			dto.Message = &m
		}
	case groups.EventMessageDeleted, groups.EventAgentThinking:
		dto.GroupId, dto.ChannelId, dto.MessageId = &group, &channel, &message
	case groups.EventTyping, groups.EventWatchReaction:
		dto.GroupId, dto.ChannelId = &group, &channel
		if e.User != nil {
			u := SocialUserDTO(*e.User)
			dto.User = &u
		}
		if e.Type == groups.EventWatchReaction {
			emoji := e.Emoji
			dto.Emoji = &emoji
		}
	case groups.EventRead, groups.EventShelfUpdated, groups.EventWatchUpdated:
		dto.GroupId, dto.ChannelId = &group, &channel
	case groups.EventGroupUpdated, groups.EventGroupRemoved:
		dto.GroupId = &group
	case groups.EventInvitesChanged:
	}
	return dto
}
