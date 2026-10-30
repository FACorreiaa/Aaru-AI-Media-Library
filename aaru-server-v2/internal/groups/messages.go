package groups

import (
	"aaru-go-api/internal/core"
	"context"
	"fmt"

	"github.com/google/uuid"
)

// MARK: Channels (GroupService+Channels.swift)

// CreateChannel adds a channel. A `title` channel needs the title, and takes its name when none
// is given.
func (s *Service) CreateChannel(ctx context.Context, group uuid.UUID, kind ChannelKind, name, topic *string, ref *core.MediaRef, viewer uuid.UUID) (Channel, error) {
	if err := s.requireManager(ctx, group, viewer); err != nil {
		return Channel{}, err
	}
	existing, err := s.Store.Channels(ctx, group, viewer)
	if err != nil {
		return Channel{}, err
	}
	if len(existing) >= MaxChannels {
		return Channel{}, Invalid("name", fmt.Sprintf("A group holds %d channels.", MaxChannels))
	}
	var title *core.Title
	if kind == KindTitle {
		if ref == nil {
			return Channel{}, Invalid("title", "Pick the title this channel is about.")
		}
		t, err := s.Catalog.Resolver().Resolve(ctx, *ref, nil)
		if err != nil {
			return Channel{}, err
		}
		title = &t
	}
	var raw string
	switch {
	case name != nil:
		raw = *name
	case title != nil:
		raw = string([]rune(title.Title)[:min(len([]rune(title.Title)), MaxChannelNameLength)])
	default:
		return Channel{}, Invalid("name", "Name the channel.")
	}
	clean, err := ChannelName(raw)
	if err != nil {
		return Channel{}, err
	}
	validTopic, err := ValidTopic(topic)
	if err != nil {
		return Channel{}, err
	}
	position := 0
	for _, c := range existing {
		position = max(position, c.Position)
	}
	channel := Channel{
		ID: uuid.New(), GroupID: group, Kind: kind, Name: clean, Topic: validTopic, Position: position + 1,
		CreatedAt: s.now(),
	}
	if title != nil {
		id := title.ID
		channel.TitleID = &id
	}
	if err := s.Store.CreateChannel(ctx, channel); err != nil {
		return Channel{}, err
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return channel, nil
}

// UpdateChannel renames a channel or sets its topic; a nil field is left alone and an empty
// topic clears it.
func (s *Service) UpdateChannel(ctx context.Context, group, channel uuid.UUID, name, topic *string, viewer uuid.UUID) (Channel, error) {
	if err := s.requireManager(ctx, group, viewer); err != nil {
		return Channel{}, err
	}
	if _, err := s.requireChannel(ctx, group, channel); err != nil {
		return Channel{}, err
	}
	var newName *string
	if name != nil {
		clean, err := ChannelName(*name)
		if err != nil {
			return Channel{}, err
		}
		newName = &clean
	}
	newTopic, err := ValidTopic(topic)
	if err != nil {
		return Channel{}, err
	}
	if err := s.Store.UpdateChannel(ctx, channel, newName, topic != nil, newTopic); err != nil {
		return Channel{}, err
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return s.requireChannel(ctx, group, channel)
}

// DeleteChannel deletes a channel and its messages. The first channel stays.
func (s *Service) DeleteChannel(ctx context.Context, group, channel, viewer uuid.UUID) error {
	if err := s.requireManager(ctx, group, viewer); err != nil {
		return err
	}
	found, err := s.requireChannel(ctx, group, channel)
	if err != nil {
		return err
	}
	if found.IsDefault {
		return Invalid("channelId", "The first channel stays; rename it instead.")
	}
	if _, err := s.Store.DeleteChannel(ctx, channel); err != nil {
		return err
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return nil
}

// MARK: Messages (GroupService.swift)

// Page is a page of messages, the authors the viewer blocked (their messages arrive collapsed),
// and the messages that would spoil what the viewer has not watched yet (they arrive veiled).
type Page struct {
	Messages []Message
	Blocked  map[uuid.UUID]bool
	Veiled   map[uuid.UUID]bool
}

// Messages are a page of a channel's messages.
func (s *Service) Messages(ctx context.Context, group, channel uuid.UUID, cursor Cursor, limit *int, viewer uuid.UUID) (Page, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return Page{}, err
	}
	found, err := s.requireChannel(ctx, group, channel)
	if err != nil {
		return Page{}, err
	}
	size := DefaultPageSize
	if limit != nil {
		size = *limit
	}
	size = min(max(size, 1), MaxPageSize)
	messages, err := s.Store.Messages(ctx, channel, cursor, size)
	if err != nil {
		return Page{}, err
	}
	blockedUsers, err := s.Social.Blocked(ctx, viewer)
	if err != nil {
		return Page{}, err
	}
	messages, err = s.HydrateComponents(ctx, messages)
	if err != nil {
		return Page{}, err
	}
	page := Page{Messages: messages, Blocked: map[uuid.UUID]bool{}, Veiled: map[uuid.UUID]bool{}}
	for _, u := range blockedUsers {
		page.Blocked[u.ID] = true
	}
	if found.TitleID != nil {
		mine, err := ProgressOf(ctx, s.q(), *found.TitleID, viewer)
		if err != nil {
			return Page{}, err
		}
		for _, m := range messages {
			if m.AuthorID() != viewer && Veils(m.Spoiler, mine) {
				page.Veiled[m.ID] = true
			}
		}
	}
	return page, nil
}

// Post posts a message. A retry with the same nonce returns the first message. In a title
// channel the message carries a spoiler stamp (see SpoilerChoice).
func (s *Service) Post(ctx context.Context, group, channel uuid.UUID, body string, nonce *string, spoiler SpoilerChoice, viewer uuid.UUID) (Message, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return Message{}, err
	}
	found, err := s.requireChannel(ctx, group, channel)
	if err != nil {
		return Message{}, err
	}
	author, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return Message{}, err
	}
	body, err = ValidBody(body)
	if err != nil {
		return Message{}, err
	}
	var key *string
	if nonce != nil {
		trimmed := trim(*nonce)
		if length(trimmed) > 64 {
			return Message{}, Invalid("clientNonce", "Keep the nonce under 64 characters.")
		}
		if trimmed != "" {
			key = &trimmed
		}
	}
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return Message{}, err
	}
	mentions, agent := Mentions(body, memberUsers(members))
	var progress map[uuid.UUID]TitleProgress
	if found.TitleID != nil {
		if progress, err = Progress(ctx, s.q(), *found.TitleID, memberIDs(members)); err != nil {
			return Message{}, err
		}
	}
	var stamp *SpoilerStamp
	if found.TitleID != nil {
		switch spoiler.Kind {
		case SpoilerStamped:
			stamp = spoiler.Stamp
		case SpoilerAuto:
			stamp = AutoStamp(progressOf(progress, viewer))
		case SpoilerFree:
		}
	}
	id := uuid.New()
	posted, err := s.Store.PostMessage(ctx, Message{
		ID: id, ChannelID: channel, Author: &author, Body: body, Mentions: mentions, MentionsAgent: agent,
		CreatedAt: s.now(), Spoiler: stamp,
	}, key)
	if err != nil {
		return Message{}, err
	}
	blockedBy, err := s.Social.Blockers(ctx, viewer)
	if err != nil {
		return Message{}, err
	}
	s.publish(ctx, Event{
		Type: EventMessageCreated, Group: group, Channel: channel, MessageID: posted.ID, Message: &posted,
		BlockedBy: blockedBy, VeiledFor: VeiledFor(posted, members, progress),
	}, memberIDs(members))
	if posted.MentionsAgent {
		s.MentionAgent(ctx, posted, group, viewer)
	}
	// A retried post returns the first message, which already alerted.
	if posted.ID == id {
		s.alertMentions(ctx, posted, found, blockedBy)
	}
	return posted, nil
}

// Edit changes a message's body. Only the author edits a message.
func (s *Service) Edit(ctx context.Context, group, channel, message uuid.UUID, body string, viewer uuid.UUID) (Message, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return Message{}, err
	}
	original, err := s.requireMessage(ctx, group, channel, message)
	if err != nil {
		return Message{}, err
	}
	if original.AuthorID() != viewer || original.Author == nil || original.DeletedAt != nil {
		return Message{}, Forbidden("You can only edit your own messages.")
	}
	body, err = ValidBody(body)
	if err != nil {
		return Message{}, err
	}
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return Message{}, err
	}
	mentions, agent := Mentions(body, memberUsers(members))
	if err := s.Store.EditMessage(ctx, message, body, mentions, agent, s.now()); err != nil {
		return Message{}, err
	}
	edited, err := s.requireMessage(ctx, group, channel, message)
	if err != nil {
		return Message{}, err
	}
	blockedBy, err := s.Social.Blockers(ctx, viewer)
	if err != nil {
		return Message{}, err
	}
	found, err := s.requireChannel(ctx, group, channel)
	if err != nil {
		return Message{}, err
	}
	var progress map[uuid.UUID]TitleProgress
	if found.TitleID != nil {
		if progress, err = Progress(ctx, s.q(), *found.TitleID, memberIDs(members)); err != nil {
			return Message{}, err
		}
	}
	s.publish(ctx, Event{
		Type: EventMessageUpdated, Group: group, Channel: channel, MessageID: edited.ID, Message: &edited,
		BlockedBy: blockedBy, VeiledFor: VeiledFor(edited, members, progress),
	}, memberIDs(members))
	return edited, nil
}

// DeleteMessage lets the author, an admin or the owner delete a message. Deleting twice changes nothing.
func (s *Service) DeleteMessage(ctx context.Context, group, channel, message, viewer uuid.UUID) error {
	mine, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	original, err := s.requireMessage(ctx, group, channel, message)
	if err != nil {
		return err
	}
	if (original.Author == nil || original.Author.ID != viewer) && !mine.Manages() {
		return Forbidden("You can only delete your own messages.")
	}
	if err := s.Store.DeleteMessage(ctx, message, s.now()); err != nil {
		return err
	}
	s.announce(ctx, Event{Type: EventMessageDeleted, Group: group, Channel: channel, MessageID: message}, group, uuid.Nil)
	return nil
}

// MarkRead moves the viewer's read point in a channel up to a message.
func (s *Service) MarkRead(ctx context.Context, group, channel, message, viewer uuid.UUID) error {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return err
	}
	if _, err := s.requireMessage(ctx, group, channel, message); err != nil {
		return err
	}
	if err := s.Store.MarkRead(ctx, viewer, channel, message); err != nil {
		return err
	}
	s.publish(ctx, Event{Type: EventRead, Group: group, Channel: channel}, []uuid.UUID{viewer})
	return nil
}

// Typing tells the other members the viewer is typing in a channel. The socket rate-limits it.
func (s *Service) Typing(ctx context.Context, group, channel, viewer uuid.UUID) error {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return err
	}
	if _, err := s.requireChannel(ctx, group, channel); err != nil {
		return err
	}
	typist, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return err
	}
	s.announce(ctx, Event{Type: EventTyping, Group: group, Channel: channel, User: &typist}, group, viewer)
	return nil
}

// HydrateComponents fills in the titles agent cards point to; a card whose title is gone is dropped.
func (s *Service) HydrateComponents(ctx context.Context, messages []Message) ([]Message, error) {
	seen := map[uuid.UUID]bool{}
	var ids []uuid.UUID
	for _, m := range messages {
		for _, c := range m.Components {
			if !seen[c.TitleID] {
				seen[c.TitleID] = true
				ids = append(ids, c.TitleID)
			}
		}
	}
	if len(ids) == 0 {
		return messages, nil
	}
	titles, err := s.titles(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := make([]Message, len(messages))
	for i, m := range messages {
		var cards []Component
		for _, c := range m.Components {
			if t, ok := titles[c.TitleID]; ok {
				cards = append(cards, Component{TitleID: c.TitleID, Title: &t})
			}
		}
		m.Components = cards
		out[i] = m
	}
	return out, nil
}
