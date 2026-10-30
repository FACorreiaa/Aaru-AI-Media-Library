package groups

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
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
		s.announce(ctx, Event{Type: EventAgentThinking, Group: group, Channel: m.ChannelID, MessageID: m.ID}, group, uuid.Nil)
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

// PostAgentReply posts a message from `@aaru` and tells the members. Catalog cards only; no
// mentions, so a reply never notifies anyone.
func (s *Service) PostAgentReply(ctx context.Context, group, channel, replyTo uuid.UUID, body string, components []Component, spoiler *SpoilerStamp) (Message, error) {
	body = core.Prefix(body, MaxMessageLength)
	reply := replyTo
	posted, err := s.Store.PostMessage(ctx, Message{
		ID: uuid.New(), ChannelID: channel, Body: body, Mentions: []uuid.UUID{}, CreatedAt: s.now(),
		Spoiler: spoiler, FromAgent: true, ReplyTo: &reply, Components: components,
	}, nil)
	if err != nil {
		return Message{}, err
	}
	posted.Components = components
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return Message{}, err
	}
	var progress map[uuid.UUID]TitleProgress
	if spoiler != nil {
		found, err := s.requireChannel(ctx, group, channel)
		if err != nil {
			return Message{}, err
		}
		if found.TitleID != nil {
			if progress, err = Progress(ctx, s.q(), *found.TitleID, memberIDs(members)); err != nil {
				return Message{}, err
			}
		}
	}
	s.publish(ctx, Event{
		Type: EventMessageCreated, Group: group, Channel: channel, MessageID: posted.ID, Message: &posted,
		BlockedBy: map[uuid.UUID]bool{}, VeiledFor: VeiledFor(posted, members, progress),
	}, memberIDs(members))
	return posted, nil
}
