package groups

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/push"
	"context"
	"strings"
	"sync"

	"github.com/google/uuid"
)

// GRP-012: alerts for mentions and invites (GroupService+Push.swift). An alert names who and
// where, never what was said, and carries the link a tap opens.

// AlertName is how an alert names someone: what their friends call them, else their handle.
func AlertName(u User) string {
	if u.DisplayName != nil {
		if name := strings.TrimSpace(*u.DisplayName); name != "" {
			return name
		}
	}
	return "@" + u.Handle
}

// MentionAlert is the alert for being tagged in a channel.
func MentionAlert(author User, group string, channel Channel) push.Message {
	groupID, channelID := strings.ToUpper(channel.GroupID.String()), strings.ToUpper(channel.ID.String())
	return push.Message{
		Title: group,
		Body:  AlertName(author) + " mentioned you in #" + channel.Name,
		Payload: map[string]string{
			"groupId":   groupID,
			"channelId": channelID,
			"url":       "aaru://group/" + groupID + "/channel/" + channelID,
		},
	}
}

// InviteAlert is the alert for a group invite.
func InviteAlert(inviter User, group string) push.Message {
	return push.Message{
		Title:   "Group invite",
		Body:    AlertName(inviter) + " invited you to " + group,
		Payload: map[string]string{"groupInvite": "1", "url": "aaru://groups"},
	}
}

// alertMentions alerts the members a message tags, except the author, anyone who blocked the
// author, and anyone who muted the group or turned mention alerts off. Best effort: the message
// is posted.
func (s *Service) alertMentions(ctx context.Context, m Message, channel Channel, blockedBy map[uuid.UUID]bool) {
	if s.Push == nil || m.Author == nil {
		return
	}
	var tagged []uuid.UUID
	for _, id := range m.Mentions {
		if id != m.Author.ID && !blockedBy[id] {
			tagged = append(tagged, id)
		}
	}
	if len(tagged) == 0 {
		return
	}
	recipients, err := s.q().MentionRecipients(ctx, sqlc.MentionRecipientsParams{GroupID: channel.GroupID, Users: tagged})
	if err != nil || len(recipients) == 0 {
		return
	}
	group, err := s.Store.Summary(ctx, channel.GroupID, m.Author.ID)
	if err != nil || group == nil {
		return
	}
	alert := MentionAlert(*m.Author, group.Name, channel)
	var wg sync.WaitGroup
	for _, user := range recipients {
		wg.Go(func() { s.Push.Send(ctx, alert, user) })
	}
	wg.Wait()
}

// alertInvite alerts a friend who was just invited, if they turned invite alerts on.
func (s *Service) alertInvite(ctx context.Context, invitee, group uuid.UUID, inviter User) {
	if s.Push == nil {
		return
	}
	settings, err := s.q().NotificationSettings(ctx, invitee)
	if err != nil || !settings.GroupInvites {
		if err != nil && !db.IsNoRows(err) {
			s.log().DebugContext(ctx, "invite alert settings", "error", err)
		}
		return
	}
	summary, err := s.Store.Summary(ctx, group, inviter.ID)
	if err != nil || summary == nil {
		return
	}
	s.Push.Send(ctx, InviteAlert(inviter, summary.Name), invitee)
}
