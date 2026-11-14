package groups

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// `@aaru` mentions (GRP-011, GroupService+Agent.swift): the fair-use caps, the queue, and posting
// the agent's replies. The model call itself runs in ReplyService, off the request path.

// Fair-use caps.
const (
	AgentDailyCapPerUser   = 30
	AgentHourlyCapPerGroup = 10
	RestingNote            = "I'm resting for now. I answer up to 30 questions a day for each person and 10 an hour in each " +
		"group. Ask me again later."
)

// Reply job states.
const (
	ReplyQueued  = "queued"
	ReplyRunning = "running"
	ReplyDone    = "done"
	ReplyFailed  = "failed"
	// ReplyCapped: over the fair-use cap, answered once with the resting note, no model call.
	ReplyCapped = "capped"
	// ReplySkipped: over the cap after the note was already given, no answer at all.
	ReplySkipped = "skipped"
)

// UTCDayStart is midnight UTC of t's day.
func UTCDayStart(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// MentionAgent queues an answer to a mention, or, over a cap, answers once that Aaru is resting
// and then stays quiet. Never calls the model. Failures only cost the answer, never the message.
func (s *Service) MentionAgent(ctx context.Context, m Message, group, tagger uuid.UUID) {
	if !s.AgentAvailable {
		return
	}
	if err := s.mentionAgent(ctx, m, group, tagger); err != nil {
		// The member's message is already saved; losing the answer is the lesser harm.
		s.log().WarnContext(ctx, "queue @aaru mention", "error", err)
	}
}

func (s *Service) mentionAgent(ctx context.Context, m Message, group, tagger uuid.UUID) error {
	now := s.now()
	load, err := s.q().GroupAgentLoad(ctx, sqlc.GroupAgentLoadParams{
		Tagger: tagger, DayStart: UTCDayStart(now), GroupID: group, HourStart: now.Add(-time.Hour),
	})
	if err != nil {
		return err
	}
	job := sqlc.EnqueueAgentReplyParams{
		ID: uuid.New(), MessageID: m.ID, GroupID: group, ChannelID: m.ChannelID, TaggerID: tagger, CreatedAt: now,
	}
	userCapped := load.UserToday >= AgentDailyCapPerUser
	groupCapped := load.GroupHour >= AgentHourlyCapPerGroup
	if !userCapped && !groupCapped {
		job.State = ReplyQueued
		if err := s.q().EnqueueAgentReply(ctx, job); err != nil {
			return err
		}
		// Thinking shows where the member asked and where the answer will land.
		s.announce(ctx, Event{Type: EventAgentThinking, Group: group, Channel: m.ChannelID, MessageID: m.ID}, group, uuid.Nil)
		replies, err := s.agentReplyChannel(ctx, group)
		if err != nil {
			return err
		}
		if replies.ID != m.ChannelID {
			s.announce(ctx, Event{Type: EventAgentThinking, Group: group, Channel: replies.ID, MessageID: m.ID}, group, uuid.Nil)
		}
		return nil
	}
	noted := (userCapped && load.UserNoted) || (groupCapped && load.GroupNoted)
	job.State = ReplyCapped
	if noted {
		job.State = ReplySkipped
	}
	if err := s.q().EnqueueAgentReply(ctx, job); err != nil {
		return err
	}
	if !noted {
		_, err = s.PostAgentReply(ctx, group, m.ChannelID, m.ID, RestingNote, nil, nil)
	}
	return err
}

// PostAgentReply posts a message from `@aaru` into the group's #ai-reply and tells the members.
// source is the channel the mention was posted in: the reply points back at it through replyTo,
// and a title channel's spoiler stamp stays on the reply, about that channel's title. Catalog
// cards only; no mentions, so a reply never notifies anyone. Once the message is saved it is
// posted: telling the members is best effort, so a failure there never sends the reply round
// again (Go audit REL-002).
func (s *Service) PostAgentReply(ctx context.Context, group, source, replyTo uuid.UUID, body string, components []Component, spoiler *SpoilerStamp) (Message, error) {
	target, err := s.agentReplyChannel(ctx, group)
	if err != nil {
		return Message{}, err
	}
	var spoilerTitle *uuid.UUID
	if spoiler != nil {
		from, err := s.requireChannel(ctx, group, source)
		if err != nil {
			return Message{}, err
		}
		spoilerTitle = from.TitleID
	}
	body = core.Prefix(body, MaxMessageLength)
	reply := replyTo
	posted, err := s.Store.PostMessage(ctx, Message{
		ID: uuid.New(), ChannelID: target.ID, Body: body, Mentions: []uuid.UUID{}, CreatedAt: s.now(),
		Spoiler: spoiler, SpoilerTitleID: spoilerTitle, FromAgent: true, ReplyTo: &reply, Components: components,
	}, nil)
	if err != nil {
		return Message{}, err
	}
	posted.Components = components
	if err := s.announceAgentReply(ctx, group, posted); err != nil {
		s.log().WarnContext(ctx, "announce @aaru reply", "error", err)
	}
	return posted, nil
}

func (s *Service) announceAgentReply(ctx context.Context, group uuid.UUID, posted Message) error {
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return err
	}
	var progress map[uuid.UUID]TitleProgress
	if posted.Spoiler != nil && posted.SpoilerTitleID != nil {
		if progress, err = Progress(ctx, s.q(), *posted.SpoilerTitleID, memberIDs(members)); err != nil {
			return err
		}
	}
	s.publish(ctx, Event{
		Type: EventMessageCreated, Group: group, Channel: posted.ChannelID, MessageID: posted.ID, Message: &posted,
		BlockedBy: map[uuid.UUID]bool{}, VeiledFor: VeiledFor(posted, members, progress),
	}, memberIDs(members))
	return nil
}

// maxAgentRepliesNames bounds the names tried for #ai-reply when a group already has a channel
// called that from before the name was reserved: ai-reply, ai-reply-2, … ai-reply-5.
const maxAgentRepliesNames = 5

// agentReplyChannel is the group's #ai-reply, made on the first mention: a plain text channel,
// not the default, last in the group. It is found by its flag, so a rename keeps it, and a
// deleted one comes back on the next mention. It does not count against MaxChannels: Aaru makes
// it, not a member.
func (s *Service) agentReplyChannel(ctx context.Context, group uuid.UUID) (Channel, error) {
	found, err := s.Store.AgentRepliesChannel(ctx, group)
	if err != nil || found != nil {
		return derefChannel(found), err
	}
	for i := 1; i <= maxAgentRepliesNames; i++ {
		name := AgentRepliesName
		if i > 1 {
			name = fmt.Sprintf("%s-%d", AgentRepliesName, i)
		}
		_, err := s.Store.CreateAgentRepliesChannel(ctx, uuid.New(), group, name, s.now())
		if errors.Is(err, errChannelNameTaken) {
			continue
		}
		if err != nil {
			return Channel{}, err
		}
		// Made here, or by a mention at the same moment: either way it is there now.
		found, err := s.Store.AgentRepliesChannel(ctx, group)
		if err != nil {
			return Channel{}, err
		}
		if found == nil {
			return Channel{}, fmt.Errorf("agent replies channel of %s vanished", group)
		}
		s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
		return *found, nil
	}
	return Channel{}, fmt.Errorf("no free name for the agent replies channel of %s", group)
}

func derefChannel(c *Channel) Channel {
	if c == nil {
		return Channel{}
	}
	return *c
}
