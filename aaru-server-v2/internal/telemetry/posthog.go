package telemetry

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
)

// Event is one product event Aaru's server counts (`docs/privacy.md` "Product counts"). Each
// carries the account's random id and a few fixed words, never a title, a name, an email or text.
type Event string

// The product events and their properties. Call Capture with these only.
const (
	// AccountCreated: `provider` (apple, google, email).
	AccountCreated Event = "account_created"
	// ImportCompleted: `source`, `result` (planned, failed).
	ImportCompleted Event = "import_completed"
	// LibraryAction: `kind` (add, update, remove, list, tv, import, undo), `actor` (user, agent, external_agent).
	LibraryAction Event = "library_action"
	// ListCreated: no properties.
	ListCreated Event = "list_created"
	// GroupCreated: no properties.
	GroupCreated Event = "group_created"
	// FriendAdded: no properties.
	FriendAdded Event = "friend_added"
	// AgentPlanDecided: `decision` (approved, denied).
	AgentPlanDecided Event = "agent_plan_decided"
	// TonightShown: the Tonight strip showed at least one pick, once per local day (AG-005).
	TonightShown Event = "tonight_shown"
	// TonightAccepted: progress landed on a pick within six hours of it showing; once per local day.
	TonightAccepted Event = "tonight_accepted"
	// TonightRejected: `verdict` (rejected, not_tonight).
	TonightRejected Event = "tonight_rejected"
	// CaptureSubmitted: `kind` (text, image, url) (AG-006).
	CaptureSubmitted Event = "capture_submitted"
	// CapturePlanDecided: `decision` (approved = applied, denied = a planned capture deleted).
	CapturePlanDecided Event = "capture_plan_decided"
	// PaywallShown: `reason` (capture_quota). The server refused and the apps offer Plus.
	PaywallShown Event = "paywall_shown"
	// PlusPurchased: `product` (the App Store product id). The first time a subscription is seen active.
	PlusPurchased Event = "plus_purchased"
	// ShareCreated: `kind` (title, sport_event, concert). Keyed by the sender, never the opener (SHR-002).
	ShareCreated Event = "share_created"
	// ShareOpened: `kind`. Keyed by the sender, never the opener; none once the sender's account is gone.
	ShareOpened Event = "share_opened"
)

// Sink is where product events go: PostHog in production, nothing until one is installed.
type Sink interface {
	// Capture never blocks and never fails: counting must not slow or fail a request.
	Capture(event Event, userID uuid.UUID, properties map[string]string)
}

type sinkBox struct{ sink Sink }

var installed atomic.Pointer[sinkBox]

// Install sets the process-wide sink (nil removes it).
func Install(s Sink) {
	if s == nil {
		installed.Store(nil)
		return
	}
	installed.Store(&sinkBox{sink: s})
}

// Capture counts one product event for an account, after the write it is about. Call sites
// never know whether PostHog is configured.
func Capture(event Event, userID uuid.UUID, properties map[string]string) {
	if box := installed.Load(); box != nil {
		box.sink.Capture(event, userID, properties)
	}
}

// postHogEvent is one queued event, as PostHog's batch endpoint reads it.
type postHogEvent struct {
	DistinctID string         `json:"distinct_id"`
	Event      string         `json:"event"`
	Properties map[string]any `json:"properties"`
	Timestamp  string         `json:"timestamp"`
}

// PostHog speaks PostHog's batch capture API directly. Capture queues; Run posts every 10
// seconds and drains the queue on shutdown. Best effort: a failed post is logged and dropped,
// never retried. It is an httpapi.Worker.
type PostHog struct {
	Endpoint      string
	projectToken  string
	client        *http.Client
	flushInterval time.Duration
	log           *slog.Logger

	mu    sync.Mutex
	queue []postHogEvent
}

// PostHog limits.
const (
	postHogMaxQueue = 2000
	postHogMaxBatch = 100
)

// NewPostHog builds the client for POSTHOG_PROJECT_TOKEN and POSTHOG_HOST.
func NewPostHog(projectToken string, host *url.URL, client *http.Client, log *slog.Logger) *PostHog {
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	if log == nil {
		log = slog.Default()
	}
	return &PostHog{
		Endpoint: strings.TrimSuffix(host.String(), "/") + "/batch/", projectToken: projectToken,
		client: client, flushInterval: 10 * time.Second, log: log,
	}
}

// Name is the worker's name.
func (p *PostHog) Name() string { return "posthog" }

// Capture queues one event; the queue holds at most 2000.
func (p *PostHog) Capture(event Event, userID uuid.UUID, properties map[string]string) {
	values := make(map[string]any, len(properties)+3)
	for k, v := range properties {
		values[k] = v
	}
	// No person profile per account, and no location from the (server's) address.
	values["$process_person_profile"] = false
	values["$geoip_disable"] = true
	values["$lib"] = "aaru-server"
	item := postHogEvent{
		Event: string(event), DistinctID: strings.ToLower(userID.String()), Timestamp: isoMillis(time.Now()), Properties: values,
	}
	p.mu.Lock()
	if len(p.queue) < postHogMaxQueue {
		p.queue = append(p.queue, item)
	}
	p.mu.Unlock()
}

// Pending is what is queued and not yet posted.
func (p *PostHog) Pending() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.queue)
}

// Run posts every flush interval until ctx ends, then drains the queue.
func (p *PostHog) Run(ctx context.Context) error {
	ticker := time.NewTicker(p.flushInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			drain, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
			p.Flush(drain)
			cancel()
			return nil
		case <-ticker.C:
			p.Flush(ctx)
		}
	}
}

// Flush posts the queue in batches of 100.
func (p *PostHog) Flush(ctx context.Context) {
	for {
		p.mu.Lock()
		n := min(len(p.queue), postHogMaxBatch)
		batch := append([]postHogEvent(nil), p.queue[:n]...)
		p.queue = p.queue[n:]
		p.mu.Unlock()
		if len(batch) == 0 {
			return
		}
		p.post(ctx, batch)
		if len(batch) < postHogMaxBatch {
			return
		}
	}
}

func (p *PostHog) post(ctx context.Context, batch []postHogEvent) {
	body, err := marshal(struct {
		APIKey string         `json:"api_key"`
		Batch  []postHogEvent `json:"batch"`
	}{p.projectToken, batch})
	if err == nil {
		var req *http.Request
		req, err = http.NewRequestWithContext(ctx, http.MethodPost, p.Endpoint, bytes.NewReader(body))
		if err == nil {
			req.Header.Set("content-type", "application/json")
			var resp *http.Response
			if resp, err = p.client.Do(req); err == nil {
				_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
				_ = resp.Body.Close()
				if resp.StatusCode >= 300 {
					p.log.Warn("PostHog refused events", "status", resp.StatusCode, "events", len(batch))
				}
				return
			}
		}
	}
	p.log.Warn("PostHog post failed", "errorType", fmt.Sprintf("%T", err), "events", len(batch))
}
