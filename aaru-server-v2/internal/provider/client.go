package provider

import (
	"aaru-go-api/internal/apperr"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ErrorKind is how a provider failed.
type ErrorKind int

const (
	// KindNotFound is a 404: the provider has no such entry.
	KindNotFound ErrorKind = iota + 1
	// KindUnavailable is down, too slow, or still failing after retries.
	KindUnavailable
	// KindMalformed is an answer that does not decode.
	KindMalformed
	// KindUnauthorized is a refused credential (401/403): a revoked user token, never retried.
	KindUnauthorized
	// KindRefused is any other 4xx, kept so a caller can explain it (Trakt's 420 account
	// limit, 423 locked account). Never retried: asking again gets the same answer.
	KindRefused
)

// String is the Swift case as logged: notFound, unavailable, refused(420)…
func (k ErrorKind) String() string {
	switch k {
	case KindNotFound:
		return "notFound"
	case KindUnavailable:
		return "unavailable"
	case KindMalformed:
		return "malformed"
	case KindUnauthorized:
		return "unauthorized"
	case KindRefused:
		return "refused"
	default:
		return "unknown"
	}
}

// Error is a provider failure. Surfaces as 502 `provider_unavailable` — never as a
// 500, and never with the provider's own message.
type Error struct {
	Provider string
	Kind     ErrorKind
	// Status is the HTTP status for KindRefused.
	Status int
}

// NewError builds a provider error.
func NewError(provider string, kind ErrorKind) *Error {
	return &Error{Provider: provider, Kind: kind}
}

func (e *Error) Error() string {
	kinds := map[ErrorKind]string{
		KindNotFound: "not found", KindUnavailable: "unavailable", KindMalformed: "malformed",
		KindUnauthorized: "unauthorized", KindRefused: "refused",
	}
	if e.Kind == KindRefused {
		return fmt.Sprintf("provider %s: refused (%d)", e.Provider, e.Status)
	}
	return fmt.Sprintf("provider %s: %s", e.Provider, kinds[e.Kind])
}

// Is compares by value, so errors.Is(err, NewError("tmdb", KindNotFound)) works.
func (e *Error) Is(target error) bool {
	t, ok := target.(*Error)
	return ok && *t == *e
}

var displayNames = map[string]string{
	"anilist":      "AniList",
	"tmdb":         "TMDB",
	"openlibrary":  "Open Library",
	"trakt":        "Trakt",
	"mal":          "MyAnimeList",
	"tvmaze":       "TVmaze",
	"pogdesign":    "Pogdesign CAT",
	"thesportsdb":  "TheSportsDB",
	"lastfm":       "Last.fm",
	"listenbrainz": "ListenBrainz",
}

// DisplayName is the provider's name as people read it.
func (e *Error) DisplayName() string {
	if name, ok := displayNames[e.Provider]; ok {
		return name
	}
	return e.Provider
}

// IsAniListOutage is AniList failing as a whole (down, disabled, answering garbage),
// not missing one entry.
func (e *Error) IsAniListOutage() bool {
	return e.Provider == "anilist" && e.Kind != KindNotFound
}

// AppError is the 502 every provider failure renders as (apperr.Convertible).
func (e *Error) AppError() *apperr.Error {
	return apperr.ProviderUnavailable(e.Provider, e.DisplayName())
}

// AsError finds a provider error inside err.
func AsError(err error) (*Error, bool) {
	var e *Error
	if errors.As(err, &e) {
		return e, true
	}
	return nil, false
}

// IsNotFound is true when err is a provider's 404.
func IsNotFound(err error) bool {
	e, ok := AsError(err)
	return ok && e.Kind == KindNotFound
}

// IsAniListOutage is true when err is AniList failing as a whole.
func IsAniListOutage(err error) bool {
	e, ok := AsError(err)
	return ok && e.IsAniListOutage()
}

// Pacer is a token bucket shared by every caller of one provider (CAT-001, X-002),
// so two concurrent imports cannot stampede it. Waiting is cancellable.
type Pacer struct {
	mu         sync.Mutex
	rate       float64
	burst      float64
	tokens     float64
	refilledAt time.Time
}

// NewPacer allows requestsPerSecond on average, and burst at once.
func NewPacer(requestsPerSecond float64, burst int) *Pacer {
	return &Pacer{rate: requestsPerSecond, burst: float64(burst), tokens: float64(burst), refilledAt: time.Now()}
}

// Acquire takes one token, waiting for it.
func (p *Pacer) Acquire(ctx context.Context) error {
	for {
		p.mu.Lock()
		now := time.Now()
		p.tokens = min(p.burst, p.tokens+now.Sub(p.refilledAt).Seconds()*p.rate)
		p.refilledAt = now
		if p.tokens >= 1 {
			p.tokens--
			p.mu.Unlock()
			return nil
		}
		wait := time.Duration((1-p.tokens)/p.rate*1000)*time.Millisecond + time.Millisecond
		p.mu.Unlock()
		if err := Sleep(ctx, wait); err != nil {
			return err
		}
	}
}

// Sleep waits d or until ctx is done.
func Sleep(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// MaxRetryAfter is the longest `Retry-After` honoured; a longer one fails the call
// so a job can retry later.
const MaxRetryAfter = 60 * time.Second

// Client is the one way adapters reach a provider: paced, retried with backoff on
// 429/5xx and network errors, and cancelled with the caller's context (a client
// that disconnects cancels its provider calls).
type Client struct {
	Name      string
	Transport Transport
	Pacer     *Pacer
	// MaxAttempts defaults to 3.
	MaxAttempts int
	// BaseDelay doubles after each retry; 250 ms by default.
	BaseDelay time.Duration
	// Sleep is replaceable in tests.
	Sleep func(ctx context.Context, d time.Duration) error
	// Jitter spreads a computed backoff so callers failing together do not retry together;
	// nil is EqualJitter. A provider's own Retry-After is honoured as sent, without jitter.
	Jitter func(d time.Duration) time.Duration
	// Classify is a provider's own reading of a failed answer, before the
	// status-code rules: AniList says "disabled" with a 403, which is an outage, not a
	// refused credential. ok false leaves the answer to the default rules.
	Classify func(*Response) (kind ErrorKind, ok bool)
}

// NewClient builds a client with the default retry policy.
func NewClient(name string, transport Transport, pacer *Pacer) *Client {
	return &Client{Name: name, Transport: transport, Pacer: pacer, MaxAttempts: 3, BaseDelay: 250 * time.Millisecond, Sleep: Sleep}
}

// Data is the body of a successful response.
func (c *Client) Data(ctx context.Context, req Request) ([]byte, error) {
	resp, err := c.Do(ctx, req)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}

// Do is the whole successful response, headers included (Trakt pages by `X-Pagination-*`).
func (c *Client) Do(ctx context.Context, req Request) (*Response, error) {
	maxAttempts := c.MaxAttempts
	if maxAttempts <= 0 {
		maxAttempts = 3
	}
	sleep := c.Sleep
	if sleep == nil {
		sleep = Sleep
	}
	jitter := c.Jitter
	if jitter == nil {
		jitter = EqualJitter
	}
	for attempt := 1; ; attempt++ {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if c.Pacer != nil {
			if err := c.Pacer.Acquire(ctx); err != nil {
				return nil, err
			}
		}
		if req.BeforeAttempt != nil {
			if err := req.BeforeAttempt(); err != nil {
				return nil, err
			}
		}
		var retryAfter time.Duration
		retryable := false
		resp, err := c.Transport.Send(ctx, req)
		switch {
		case errors.Is(err, ErrBodyTooLarge):
			// Asking again downloads the same oversize answer.
			return nil, NewError(c.Name, KindMalformed)
		case err != nil:
			if ctxErr := ctx.Err(); ctxErr != nil {
				return nil, ctxErr
			}
			retryable = true // network error
		case resp.Status >= 200 && resp.Status < 300:
			return resp, nil
		default:
			if refused := c.refuse(resp); refused != nil {
				return nil, refused
			}
			retryable = resp.Status == 429 || (resp.Status >= 500 && resp.Status < 600)
			if resp.Status == 429 || resp.Status == 503 {
				retryAfter = RetryAfter(resp.HeaderValue("Retry-After"), time.Now())
			}
		}
		if !retryable || attempt >= maxAttempts || retryAfter > MaxRetryAfter {
			return nil, NewError(c.Name, KindUnavailable)
		}
		delay := retryAfter
		if delay == 0 {
			delay = jitter(c.BaseDelay * time.Duration(1<<(attempt-1)))
		}
		// A wait the caller's deadline cannot cover fails now, with the provider's error,
		// instead of sleeping into the deadline.
		if deadline, ok := ctx.Deadline(); ok && time.Until(deadline) < delay {
			return nil, NewError(c.Name, KindUnavailable)
		}
		if err := sleep(ctx, delay); err != nil {
			return nil, err
		}
	}
}

// EqualJitter is d/2 plus a random part of d/2: never less than half the backoff, never more.
func EqualJitter(d time.Duration) time.Duration {
	if d <= 1 {
		return d
	}
	half := d / 2
	return half + rand.N(d-half+1) //nolint:gosec // jitter, not a secret
}

// RetryAfter reads a `Retry-After` header: delay-seconds or an HTTP-date (RFC 9110 10.2.3).
// Zero when absent, unreadable or already past.
func RetryAfter(value string, now time.Time) time.Duration {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	if seconds, err := strconv.Atoi(value); err == nil {
		if seconds <= 0 {
			return 0
		}
		return time.Duration(seconds) * time.Second
	}
	at, err := http.ParseTime(value)
	if err != nil {
		return 0
	}
	if d := at.Sub(now); d > 0 {
		return d.Round(time.Second)
	}
	return 0
}

// refuse is the error for answers asking again would not change: 404, 401/403, any
// other 4xx but 429. Nil for a retryable answer.
func (c *Client) refuse(resp *Response) *Error {
	if c.Classify != nil {
		if kind, ok := c.Classify(resp); ok {
			e := NewError(c.Name, kind)
			if kind == KindRefused {
				e.Status = resp.Status
			}
			return e
		}
	}
	switch {
	case resp.Status == 404:
		return NewError(c.Name, KindNotFound)
	case resp.Status == 401 || resp.Status == 403:
		return NewError(c.Name, KindUnauthorized)
	case resp.Status == 429:
		return nil
	case resp.Status >= 400 && resp.Status < 500:
		return &Error{Provider: c.Name, Kind: KindRefused, Status: resp.Status}
	}
	return nil
}

// DecodeJSON fetches and decodes the body into v; a body that does not decode is
// KindMalformed.
func (c *Client) DecodeJSON(ctx context.Context, req Request, v any) error {
	body, err := c.Data(ctx, req)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, v); err != nil {
		return NewError(c.Name, KindMalformed)
	}
	return nil
}
