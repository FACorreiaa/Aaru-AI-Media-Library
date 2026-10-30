package push

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// LiveActivityEvent is what a Live Activity push does to the "Now playing" activity (SCR-008, SCR-009).
type LiveActivityEvent int

const (
	// LiveActivityStart is push-to-start, with the alert the device shows as it appears.
	LiveActivityStart LiveActivityEvent = iota + 1
	// LiveActivityUpdate changes the running activity.
	LiveActivityUpdate
	// LiveActivityEnd ends it; it leaves the Lock Screen at Dismissal.
	LiveActivityEnd
)

// LiveActivityPush is one push to the "Now playing" Live Activity: start it on a device, or
// update or end the one running there.
type LiveActivityPush struct {
	Event LiveActivityEvent
	// AlertTitle and AlertBody are shown with a start.
	AlertTitle string
	AlertBody  string
	// Dismissal is when an ended activity leaves the Lock Screen.
	Dismissal time.Time
	// Content is the activity's content state (AaruCore's NowPlayingActivityState), encoded as
	// ActivityKit decodes it: its dates are seconds since 2001 (Foundation's default), which is
	// the caller's type's job.
	Content any
	// StaleDate is when the activity reads as stale; nil for none. Not sent with an end.
	StaleDate *time.Time
	// Timestamp: Apple drops a push older than the last one it delivered to the activity.
	Timestamp time.Time
	// Considerate is `apns-priority` 5 (Apple budgets the immediate ones); false is 10.
	Considerate bool
}

// LiveActivityTokenKind says what a Live Activity token can do.
type LiveActivityTokenKind string

const (
	// LiveActivityTokenStart is push-to-start: lets the server start the activity on this device.
	LiveActivityTokenStart LiveActivityTokenKind = "start"
	// LiveActivityTokenUpdate is one running activity's own token, for updates and the end.
	LiveActivityTokenUpdate LiveActivityTokenKind = "update"
)

// LiveActivityToken is where a Live Activity push goes.
type LiveActivityToken struct {
	Token       string
	Kind        LiveActivityTokenKind
	Environment Environment
	// Topic is the app's bundle id; APNs gets `<topic>.push-type.liveactivity`.
	Topic string
}

// LiveActivitySender sends one Live Activity push. APNSSender implements it.
type LiveActivitySender interface {
	SendLiveActivity(ctx context.Context, p LiveActivityPush, t LiveActivityToken) (Outcome, error)
}

// attributesType is the type name ActivityKit matches a push-to-start against: the app's
// `NowPlayingActivityAttributes`.
const attributesType = "NowPlayingActivityAttributes"

type liveActivityAlert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type liveActivityAPS struct {
	Timestamp      int64              `json:"timestamp"`
	Event          string             `json:"event"`
	ContentState   any                `json:"content-state"`
	DismissalDate  *int64             `json:"dismissal-date,omitempty"`
	StaleDate      *int64             `json:"stale-date,omitempty"`
	Alert          *liveActivityAlert `json:"alert,omitempty"`
	Attributes     *struct{}          `json:"attributes,omitempty"`
	AttributesType string             `json:"attributes-type,omitempty"`
}

// LiveActivityPayload is the APNs body APNSwift sends for p.
func LiveActivityPayload(p LiveActivityPush) ([]byte, error) {
	aps := liveActivityAPS{Timestamp: p.Timestamp.Unix(), ContentState: p.Content}
	var stale *int64
	if p.StaleDate != nil {
		v := p.StaleDate.Unix()
		stale = &v
	}
	switch p.Event {
	case LiveActivityStart:
		aps.Event = "start"
		aps.StaleDate = stale
		aps.Alert = &liveActivityAlert{Title: p.AlertTitle, Body: p.AlertBody}
		aps.Attributes = &struct{}{}
		aps.AttributesType = attributesType
	case LiveActivityUpdate:
		aps.Event = "update"
		aps.StaleDate = stale
	case LiveActivityEnd:
		aps.Event = "end"
		d := p.Dismissal.Unix()
		aps.DismissalDate = &d
	default:
		return nil, fmt.Errorf("live activity: unknown event %d", p.Event)
	}
	return json.Marshal(map[string]any{"aps": aps})
}

// SendLiveActivity sends p (push type `liveactivity`). An ended activity's token answers
// ExpiredToken, which counts as dead.
func (s *APNSSender) SendLiveActivity(ctx context.Context, p LiveActivityPush, t LiveActivityToken) (Outcome, error) {
	body, err := LiveActivityPayload(p)
	if err != nil {
		return 0, err
	}
	priority := 10
	if p.Considerate {
		priority = 5
	}
	return s.post(ctx, request{
		environment: t.Environment, token: t.Token, pushType: "liveactivity", priority: priority,
		topic: t.Topic + ".push-type.liveactivity", body: body,
	}, true)
}
