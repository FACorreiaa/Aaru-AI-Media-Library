package scrobble

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/push"
	"context"
	"log/slog"
	"reflect"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	// WatchedLinger is how long a ticked row stays, reading "Watched".
	WatchedLinger = 8 * time.Second
	// StaleGrace is how long past the next expected change the activity may go unheard before it
	// reads stale.
	StaleGrace = 30 * time.Minute
	// EndTimeSlack is the rule — an end time moving by more than this (a seek, a duration first known) is a change.
	EndTimeSlack = 60 * time.Second
)

// Notifier is LiveSetNotifier: keeps the "Now playing" Live Activity in step with everything that
// plays (SCR-008, SCR-009). One activity per device lists the user's live set. Each report, and each
// sweep, recomputes the set and pushes only when what the activity shows changes: the first thing
// playing starts it on every device by push, a row added, gone, paused, resumed or ticked updates it,
// and nothing left ends it. Position alone never pushes, so a player's heartbeat costs nothing. Best
// effort: a push outage never fails a report.
type Notifier struct {
	Store  *Store
	Titles Titles
	Sender push.LiveActivitySender
	Log    *slog.Logger
}

func (n *Notifier) log() *slog.Logger {
	if n.Log == nil {
		return slog.Default()
	}
	return n.Log
}

// event is what a recomputation asks of the activity.
type event struct {
	kind push.LiveActivityEvent
	// alertBody is a start's line; dismissal an end's.
	alertBody string
	dismissal time.Time
}

// Sync recomputes what plays for user and pushes the difference. ticked names watch events that
// just ticked: their rows stay a moment as "Watched".
func (n *Notifier) Sync(ctx context.Context, user uuid.UUID, now time.Time, ticked []uuid.UUID) {
	err := func() error {
		has, err := n.Store.HasLiveActivityTokens(ctx, user)
		if err != nil || !has {
			return err
		}
		// A second report saving first means this one recomputes once on top of it.
		saved, err := n.attempt(ctx, user, now, ticked)
		if err != nil || saved {
			return err
		}
		_, err = n.attempt(ctx, user, now, ticked)
		return err
	}()
	if err != nil {
		n.log().Warn("Live Activity push failed", "error", err.Error())
	}
}

// CaughtUp is an activity's token arriving, maybe well after a push started it in the background:
// the app uploads it when iOS next runs it. The token hears what the activity should show now.
func (n *Notifier) CaughtUp(ctx context.Context, token push.LiveActivityToken, user uuid.UUID, now time.Time) {
	err := func() error {
		state, err := n.Store.LiveActivityState(ctx, user)
		if err != nil {
			return err
		}
		if state.Pushed != nil {
			n.deliver(ctx, event{kind: push.LiveActivityUpdate}, *state.Pushed, []push.LiveActivityToken{token}, nil, now)
			return nil
		}
		entries, err := LoadLiveSet(ctx, n.Store, n.Titles, user, now)
		if err != nil {
			return err
		}
		if len(entries) == 0 {
			n.deliver(ctx, event{kind: push.LiveActivityEnd, dismissal: now}, core.NowPlayingActivityState{},
				[]push.LiveActivityToken{token}, nil, now)
			return n.Store.ForgetLiveActivity(ctx, token.Token)
		}
		// The app started the activity itself: it is the one running now.
		n.Sync(ctx, user, now, nil)
		return nil
	}()
	if err != nil {
		n.log().Warn("Live Activity catch-up failed", "error", err.Error())
	}
}

// attempt is one read, compute, save and push. False when another report saved first.
func (n *Notifier) attempt(ctx context.Context, user uuid.UUID, now time.Time, ticked []uuid.UUID) (bool, error) {
	state, err := n.Store.LiveActivityState(ctx, user)
	if err != nil {
		return false, err
	}
	ids := map[string]bool{}
	for _, id := range ticked {
		ids[strings.ToLower(id.String())] = true
	}
	var lingering []Lingering
	for _, l := range state.Lingering {
		if !ids[l.Item.ID] && l.Until.After(now) {
			lingering = append(lingering, l)
		}
	}
	if state.Pushed != nil {
		for _, item := range state.Pushed.Items {
			if ids[item.ID] {
				item.Watched = true
				lingering = append(lingering, Lingering{Item: item, Until: core.ReferenceTime{Time: now.Add(WatchedLinger)}})
			}
		}
	}
	entries, err := LoadLiveSet(ctx, n.Store, n.Titles, user, now)
	if err != nil {
		return false, err
	}
	shown := map[string]bool{}
	items := []core.NowPlayingActivityItem{}
	for _, l := range lingering {
		shown[l.Item.ID] = true
		items = append(items, l.Item)
	}
	for _, e := range entries {
		if item := e.ActivityItem(); !shown[item.ID] {
			items = append(items, item)
		}
	}
	if len(items) > core.NowPlayingMaxItems {
		items = items[:core.NowPlayingMaxItems]
	}
	next := core.NowPlayingActivityState{Items: items}
	var nextCheck *time.Time
	consider := func(t time.Time) {
		if nextCheck == nil || t.Before(*nextCheck) {
			nextCheck = &t
		}
	}
	for _, l := range lingering {
		consider(l.Until.Time)
	}
	for _, e := range entries {
		consider(e.LiveUntil())
	}

	var ev *event
	switch {
	case state.Pushed == nil && len(next.Items) == 0:
	case state.Pushed != nil && len(next.Items) == 0:
		ev = &event{kind: push.LiveActivityEnd, dismissal: now}
	case state.Pushed == nil:
		ev = &event{kind: push.LiveActivityStart, alertBody: Line(next.Items[0])}
	case Differs(*state.Pushed, next):
		ev = &event{kind: push.LiveActivityUpdate}
	}
	if ev == nil {
		if nextCheck != nil {
			return true, n.Store.ScheduleLiveActivityCheck(ctx, user, *nextCheck)
		}
		return true, nil
	}
	last := state.Pushed
	state.Pushed = nil
	if len(next.Items) > 0 {
		state.Pushed = &next
	}
	state.Lingering = lingering
	state.NextCheckAt = nextCheck
	saved, err := n.Store.SaveLiveActivityState(ctx, state, user)
	if err != nil || !saved {
		return false, err
	}
	return true, n.send(ctx, *ev, state, last, user, now)
}

// send sends a change already saved: to the running activities, or to every device to start one.
func (n *Notifier) send(ctx context.Context, ev event, saved LiveActivityState, last *core.NowPlayingActivityState, user uuid.UUID, now time.Time) error {
	next := core.NowPlayingActivityState{}
	if saved.Pushed != nil {
		next = *saved.Pushed
	}
	var stale *time.Time
	if saved.NextCheckAt != nil {
		t := saved.NextCheckAt.Add(StaleGrace)
		stale = &t
	}
	running, err := n.Store.LiveActivityTokens(ctx, user, push.LiveActivityTokenUpdate)
	if err != nil {
		return err
	}
	switch ev.kind {
	case push.LiveActivityStart:
		if len(running) > 0 {
			// The app started one itself and handed over its token: update it, start no second.
			n.deliver(ctx, event{kind: push.LiveActivityUpdate}, next, running, stale, now)
			return nil
		}
		starts, err := n.Store.LiveActivityTokens(ctx, user, push.LiveActivityTokenStart)
		if err != nil {
			return err
		}
		n.deliver(ctx, ev, next, starts, stale, now)
	case push.LiveActivityUpdate:
		n.deliver(ctx, ev, next, running, stale, now)
	case push.LiveActivityEnd:
		content := next
		if last != nil {
			content = *last
		}
		n.deliver(ctx, ev, content, running, nil, now)
		return n.Store.ForgetLiveActivityUpdates(ctx, user)
	}
	return nil
}

// Differs is whether the activity would look different: rows, their order, pause, tick, text or
// art, or an end time moved by more than EndTimeSlack. Not position: the activity runs its own clock.
func Differs(old, next core.NowPlayingActivityState) bool {
	if len(old.Items) != len(next.Items) {
		return true
	}
	for i, before := range old.Items {
		after := next.Items[i]
		same := before
		same.StartedAt, same.EndsAt, same.PausedAt = after.StartedAt, after.EndsAt, after.PausedAt
		if !reflect.DeepEqual(same, after) || (before.PausedAt == nil) != (after.PausedAt == nil) ||
			(before.EndsAt == nil) != (after.EndsAt == nil) {
			return true
		}
		if before.EndsAt != nil && after.EndsAt != nil {
			if d := before.EndsAt.Sub(after.EndsAt.Time); d > EndTimeSlack || d < -EndTimeSlack {
				return true
			}
		}
	}
	return false
}

// Line is "Pluribus · S1 · E2 · Pilot", "Song · Artist".
func Line(item core.NowPlayingActivityItem) string {
	if item.Subtitle == nil {
		return item.Title
	}
	return item.Title + " · " + *item.Subtitle
}

func (n *Notifier) deliver(ctx context.Context, ev event, content core.NowPlayingActivityState, tokens []push.LiveActivityToken, stale *time.Time, now time.Time) {
	p := push.LiveActivityPush{
		Event: ev.kind, Content: normalized(content), StaleDate: stale, Timestamp: now,
		// A start or an end shows at once; a row coming or going waits for a good moment.
		Considerate: ev.kind == push.LiveActivityUpdate,
	}
	switch ev.kind {
	case push.LiveActivityStart:
		p.AlertTitle, p.AlertBody = "Now playing", ev.alertBody
	case push.LiveActivityEnd:
		p.Dismissal = ev.dismissal
	case push.LiveActivityUpdate:
	}
	for _, t := range tokens {
		outcome, err := n.Sender.SendLiveActivity(ctx, p, t)
		push.RecordOutcome("live_activity", outcome, err)
		if err == nil && outcome == push.DeadToken {
			_ = n.Store.ForgetLiveActivity(ctx, t.Token)
		}
	}
}
