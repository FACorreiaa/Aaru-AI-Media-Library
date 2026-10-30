// Package telemetry is the port of Sources/App/Telemetry: Sentry error reports for 5xx and
// PostHog's server-side product events. What either may carry is what `docs/privacy.md`
// promises, and nothing leaves the server without configuration.
package telemetry

import (
	"aaru-go-api/internal/middleware"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Sentry sends server errors (5xx) to Sentry's envelope endpoint, speaking the wire format itself.
//
// An event holds the error's type, the route template, the status, the release. Never the path
// with its ids, a query, a header, a body, the error's text (a decoding or database error can
// quote what the user sent) or who the user is.
type Sentry struct {
	Endpoint    string
	publicKey   string
	environment string
	release     string
	client      *http.Client
	log         *slog.Logger
	wg          sync.WaitGroup
}

var _ middleware.Reporter = (*Sentry)(nil)

// NewSentry is nil, so reporting is off, when dsn is empty or not a Sentry DSN
// (`https://<key>@<host>/<project id>`).
func NewSentry(dsn, environment string, release *string, client *http.Client, log *slog.Logger) *Sentry {
	u, err := url.Parse(strings.TrimSpace(dsn))
	if err != nil || u.Scheme == "" || u.Hostname() == "" || u.User == nil || u.User.Username() == "" {
		return nil
	}
	project := strings.Trim(u.Path, "/")
	if project == "" {
		return nil
	}
	host := u.Hostname()
	if port := u.Port(); port != "" {
		host += ":" + port
	}
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	if log == nil {
		log = slog.Default()
	}
	s := &Sentry{
		Endpoint: u.Scheme + "://" + host + "/api/" + project + "/envelope/", publicKey: u.User.Username(),
		environment: environment, client: client, log: log,
	}
	if release != nil {
		s.release = strings.TrimSpace(*release)
	}
	return s
}

// Report is fire and forget: reporting never slows or fails the request it is about.
func (s *Sentry) Report(f middleware.Failure) {
	if s == nil {
		return
	}
	s.wg.Go(func() {
		req, err := s.Request(context.Background(), f, time.Now())
		if err != nil {
			s.log.Debug("Sentry error report failed", "errorType", fmt.Sprintf("%T", err))
			return
		}
		resp, err := s.client.Do(req)
		if err != nil {
			s.log.Debug("Sentry error report failed", "errorType", fmt.Sprintf("%T", err))
			return
		}
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		_ = resp.Body.Close()
		if resp.StatusCode >= 300 {
			s.log.Warn("Sentry refused an error report", "status", resp.StatusCode)
		}
	})
}

// Wait blocks until reports in flight finish (shutdown and tests).
func (s *Sentry) Wait() {
	if s != nil {
		s.wg.Wait()
	}
}

// Request is the envelope POST for one failure.
func (s *Sentry) Request(ctx context.Context, f middleware.Failure, now time.Time) (*http.Request, error) {
	eventID := strings.ReplaceAll(uuid.NewString(), "-", "")
	timestamp := isoMillis(now)
	tags := map[string]string{
		"http.method":      f.Method,
		"http.route":       f.Route,
		"http.status_code": strconv.Itoa(f.Status),
		"code":             f.Code,
	}
	event := map[string]any{
		"event_id":    eventID,
		"timestamp":   timestamp,
		"platform":    "other",
		"level":       "error",
		"logger":      "aaru-server",
		"environment": s.environment,
		"server_name": "aaru-api",
		"transaction": f.Method + " " + f.Route,
		"exception": map[string]any{"values": []map[string]string{
			{"type": f.ErrorType, "value": strconv.Itoa(f.Status) + " " + f.Code},
		}},
		"tags": tags,
	}
	if s.release != "" {
		event["release"] = s.release
	}
	var body bytes.Buffer
	for i, line := range []any{map[string]string{"event_id": eventID, "sent_at": timestamp}, map[string]string{"type": "event"}, event} {
		if i > 0 {
			body.WriteByte('\n')
		}
		data, err := marshal(line)
		if err != nil {
			return nil, err
		}
		body.Write(data)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.Endpoint, &body)
	if err != nil {
		return nil, fmt.Errorf("sentry request: %w", err)
	}
	req.Header.Set("content-type", "application/x-sentry-envelope")
	req.Header.Set("x-sentry-auth", "Sentry sentry_version=7, sentry_client=aaru-server/1.0, sentry_key="+s.publicKey)
	return req, nil
}

// marshal is JSON with sorted keys (maps) and unescaped slashes and HTML.
func marshal(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, fmt.Errorf("telemetry json: %w", err)
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// isoMillis is ISO 8601 with milliseconds in UTC, as Foundation's formatter writes it.
func isoMillis(t time.Time) string {
	return t.UTC().Format("2006-01-02T15:04:05.000Z")
}
