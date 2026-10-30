// Package provider is the one outbound HTTP layer (TMDB, AniList, TVmaze, Open
// Library, Trakt, MAL, Anthropic, …): a Transport that sends one request, and a
// Client per provider that paces, retries and classifies failures into a typed
// *Error, which renders as 502 `provider_unavailable`.
//
// Tests never reach a real service or use a real key: adapters take a base URL,
// so a test points them at an httptest.Server, or swaps the Transport for a
// TransportFunc.
package provider

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// DefaultTimeout bounds one call, body included, unless a request says otherwise.
const DefaultTimeout = 10 * time.Second

// DefaultMaxBodyBytes is the largest response body buffered; larger ones are refused.
const DefaultMaxBodyBytes = 8 * 1024 * 1024

// Request is one outbound HTTP call.
type Request struct {
	// Method defaults to GET.
	Method string
	URL    string
	// Headers in order, as name/value pairs.
	Headers [][2]string
	Body    []byte
	// Timeout defaults to DefaultTimeout.
	Timeout time.Duration
}

// Response is a whole buffered answer.
type Response struct {
	Status int
	Body   []byte
	Header http.Header
}

// HeaderValue is the first header with this name, ignoring case.
func (r *Response) HeaderValue(name string) string {
	if r.Header == nil {
		return ""
	}
	return r.Header.Get(name)
}

// Transport sends one request. Cancelling ctx cancels it.
type Transport interface {
	Send(ctx context.Context, req Request) (*Response, error)
}

// TransportFunc adapts a function, for tests.
type TransportFunc func(ctx context.Context, req Request) (*Response, error)

// Send calls f.
func (f TransportFunc) Send(ctx context.Context, req Request) (*Response, error) {
	return f(ctx, req)
}

// HTTPTransport is the production transport over net/http.
type HTTPTransport struct {
	Client *http.Client
	// MaxBodyBytes: responses larger than this are refused rather than buffered.
	MaxBodyBytes int64
}

// ErrBodyTooLarge is a response over MaxBodyBytes.
var ErrBodyTooLarge = errors.New("provider response body too large")

// NewHTTPTransport is the one outbound client: 5 s to connect, at most 5
// redirects, idle connections kept 60 s. Each call's own timeout bounds the rest,
// so a provider that is down fails in seconds.
func NewHTTPTransport() *HTTPTransport {
	transport := &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   5 * time.Second,
		IdleConnTimeout:       60 * time.Second,
		MaxIdleConnsPerHost:   16,
		ExpectContinueTimeout: time.Second,
		ForceAttemptHTTP2:     true,
	}
	client := &http.Client{
		Transport: transport,
		CheckRedirect: func(_ *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("stopped after 5 redirects")
			}
			return nil
		},
	}
	return &HTTPTransport{Client: client, MaxBodyBytes: DefaultMaxBodyBytes}
}

// Send performs the request; the timeout bounds the whole call, body included.
func (t *HTTPTransport) Send(ctx context.Context, req Request) (*Response, error) {
	timeout := req.Timeout
	if timeout <= 0 {
		timeout = DefaultTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	method := req.Method
	if method == "" {
		method = http.MethodGet
	}
	var body io.Reader
	if req.Body != nil {
		body = bytes.NewReader(req.Body)
	}
	httpReq, err := http.NewRequestWithContext(ctx, method, req.URL, body)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	for _, h := range req.Headers {
		httpReq.Header.Add(h[0], h[1])
	}
	client := t.Client
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send %s %s: %w", method, redact(req.URL), err)
	}
	defer func() { _ = resp.Body.Close() }()
	limit := t.MaxBodyBytes
	if limit <= 0 {
		limit = DefaultMaxBodyBytes
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", redact(req.URL), err)
	}
	if int64(len(data)) > limit {
		return nil, ErrBodyTooLarge
	}
	return &Response{Status: resp.StatusCode, Body: data, Header: resp.Header}, nil
}

// redact drops the query, which may carry an API key, from a URL for an error.
func redact(raw string) string {
	if i := strings.IndexByte(raw, '?'); i >= 0 {
		return raw[:i]
	}
	return raw
}
