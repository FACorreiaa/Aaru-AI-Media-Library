// Package push sends alerts to a user's Apple devices (APNs) and browsers (web
// push), and pushes the "Now playing" Live Activity. It is the port of
// Sources/App/Push (Push.swift, WebPush.swift, LiveActivityPush.swift) and
// PostgresPushStore.swift.
//
// Other areas reach a user through UserPush.Send (best effort) or
// UserPush.Deliver, and a Live Activity token through APNSSender.SendLiveActivity.
package push

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/metrics"
	"context"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Environment is the APNs gateway a device's build talks to.
type Environment string

const (
	// Sandbox is Xcode builds.
	Sandbox Environment = "sandbox"
	// Production is TestFlight and the App Store.
	Production Environment = "production"
)

// AllowedTopics are the bundle ids a device may register for: Release and Beta are separate APNs topics.
var AllowedTopics = map[string]bool{"com.fernandocorreia.aaru": true, "com.fernandocorreia.aaru.beta": true}

// Device is one registered app install.
type Device struct {
	Token       string
	Environment Environment
	// Topic is the app's bundle id: Release and Beta are separate topics.
	Topic string
}

// WebSubscription is one browser's push subscription.
type WebSubscription struct {
	Endpoint string
	// P256dh is the browser's P-256 public key, base64url.
	P256dh string
	// Auth is the browser's auth secret, base64url.
	Auth string
	// VAPIDKeyID is the VAPID public key it was made with (base64url), so a later key still reaches it.
	VAPIDKeyID string
}

// Message is one alert.
type Message struct {
	Title string
	Body  string
	// Payload is read by the app to open the right screen.
	Payload map[string]string
}

// Outcome is what a send did.
type Outcome int

const (
	// Sent reached the push service.
	Sent Outcome = iota + 1
	// DeadToken means Apple or the browser will never deliver to this token again; forget it.
	DeadToken
)

// Sender sends one alert to one Apple device.
type Sender interface {
	Send(ctx context.Context, m Message, d Device) (Outcome, error)
}

// WebSender sends one alert to one browser subscription (RFC 8030/8291/8292).
type WebSender interface {
	// PublicKey is the VAPID public key (base64url) a browser subscribes with.
	PublicKey() string
	Send(ctx context.Context, m Message, s WebSubscription) (Outcome, error)
}

// RecordOutcome counts one send in `aaru_push_total`: `sent`, `dead_token` or `error`.
// Channel is `apns`, `web` or `live_activity`.
func RecordOutcome(channel string, outcome Outcome, err error) {
	result := "error"
	if err == nil {
		switch outcome {
		case Sent:
			result = "sent"
		case DeadToken:
			result = "dead_token"
		}
	}
	metrics.Push.WithLabelValues(channel, result).Inc()
}

// UserPush sends one message to every device and browser a user registered.
// APNs and Web may be nil (not configured).
type UserPush struct {
	Q    *sqlc.Queries
	APNs Sender
	Web  WebSender
	Log  *slog.Logger
}

// Send is best effort, for callers that must not fail on a push outage.
func (p *UserPush) Send(ctx context.Context, m Message, userID uuid.UUID) {
	if p == nil {
		return
	}
	if _, err := p.Deliver(ctx, m, userID); err != nil && p.Log != nil {
		p.Log.Warn("Push delivery failed", "error", err.Error())
	}
}

// Deliver sends to each device and browser; one failing never stops the others.
// It returns how many went out.
func (p *UserPush) Deliver(ctx context.Context, m Message, userID uuid.UUID) (int, error) {
	sent := 0
	if p.APNs != nil {
		rows, err := p.Q.PushDevices(ctx, userID)
		if err != nil {
			return sent, fmt.Errorf("push devices: %w", err)
		}
		for _, row := range rows {
			env := Environment(row.Environment)
			if env != Sandbox && env != Production {
				continue
			}
			outcome, err := p.APNs.Send(ctx, m, Device{Token: row.Token, Environment: env, Topic: row.Topic})
			RecordOutcome("apns", outcome, err)
			switch {
			case err != nil:
				continue
			case outcome == Sent:
				sent++
			case outcome == DeadToken:
				if err := p.Q.ForgetPushDevice(ctx, row.Token); err != nil {
					return sent, fmt.Errorf("forget device: %w", err)
				}
			}
		}
	}
	if p.Web != nil {
		rows, err := p.Q.WebPushSubscriptions(ctx, userID)
		if err != nil {
			return sent, fmt.Errorf("web push subscriptions: %w", err)
		}
		for _, row := range rows {
			sub := WebSubscription{Endpoint: row.Endpoint, P256dh: row.P256dh, Auth: row.Auth, VAPIDKeyID: row.VapidKeyID}
			outcome, err := p.Web.Send(ctx, m, sub)
			RecordOutcome("web", outcome, err)
			switch {
			case err != nil:
				continue
			case outcome == Sent:
				sent++
			case outcome == DeadToken:
				if err := p.Q.ForgetWebPushSubscription(ctx, row.Endpoint); err != nil {
					return sent, fmt.Errorf("forget web push: %w", err)
				}
			}
		}
	}
	return sent, nil
}

// DueAiring is an episode that aired for a user who asked to hear about it, not yet announced.
type DueAiring struct {
	UserID  uuid.UUID
	TitleID uuid.UUID
	// LibraryItemID is the user's library item for the show: what a tap on the alert opens.
	LibraryItemID uuid.UUID
	Title         string
	Season        int
	Episode       int
	EpisodeName   *string
}

// AiringWindow is how far back a run looks: episodes that aired while the server was down still go out.
const AiringWindow = 2 * 24 * time.Hour

// AiringNotifier announces newly aired episodes of shows a user is watching (2026-10-15 decision).
// Each episode is claimed in Postgres before it is sent, so two replicas or a restart never send it twice.
// The ten-minute loop around RunOnce (AiringNotifierService) belongs to the schedule area.
type AiringNotifier struct {
	Q *sqlc.Queries
	// APNs is nil when no APNs key is configured: devices still register, nothing is sent to them.
	APNs Sender
	// Web is nil when no VAPID key is configured: browsers cannot subscribe.
	Web WebSender
	Now func() time.Time
}

// RunOnce is one pass. It returns how many notifications went out.
func (n *AiringNotifier) RunOnce(ctx context.Context) (int, error) {
	if n.APNs == nil && n.Web == nil {
		return 0, nil
	}
	now := time.Now()
	if n.Now != nil {
		now = n.Now()
	}
	since := now.Add(-AiringWindow)
	rows, err := n.Q.DueAirings(ctx, sqlc.DueAiringsParams{Since: &since, Now: &now})
	if err != nil {
		return 0, fmt.Errorf("due airings: %w", err)
	}
	push := &UserPush{Q: n.Q, APNs: n.APNs, Web: n.Web}
	sent := 0
	for _, row := range rows {
		claimed, err := n.Q.ClaimAiring(ctx, sqlc.ClaimAiringParams{
			UserID: row.UserID, TitleID: row.TitleID, Season: row.Season, Episode: row.Episode,
		})
		if err != nil {
			return sent, fmt.Errorf("claim airing: %w", err)
		}
		if len(claimed) == 0 {
			continue
		}
		airing := DueAiring{
			UserID: row.UserID, TitleID: row.TitleID, LibraryItemID: row.LibraryItemID, Title: row.Title,
			Season: int(row.Season), Episode: int(row.Episode), EpisodeName: row.Name,
		}
		count, err := push.Deliver(ctx, AiringMessage(airing), airing.UserID)
		sent += count
		if err != nil {
			return sent, err
		}
	}
	return sent, nil
}

// AiringMessage is the alert for one aired episode.
func AiringMessage(a DueAiring) Message {
	episode := "S" + strconv.Itoa(a.Season) + " E" + strconv.Itoa(a.Episode)
	body := episode + " is out"
	if a.EpisodeName != nil {
		body = episode + " · “" + *a.EpisodeName + "” is out"
	}
	return Message{
		Title: a.Title,
		Body:  body,
		Payload: map[string]string{
			// Uppercase, as Swift's `description` wrote them and as the API returns ids.
			"titleId":       strings.ToUpper(a.TitleID.String()),
			"libraryItemId": strings.ToUpper(a.LibraryItemID.String()),
			"season":        strconv.Itoa(a.Season),
			"episode":       strconv.Itoa(a.Episode),
		},
	}
}
