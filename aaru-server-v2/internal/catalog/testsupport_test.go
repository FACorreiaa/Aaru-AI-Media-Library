package catalog

import (
	"context"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"aaru-go-api/internal/provider"

	"github.com/stretchr/testify/require"
)

// stubTransport routes by URL path suffix to canned JSON; anything else is a 404.
// It records every request. No network, no real keys.
type stubTransport struct {
	mu       sync.Mutex
	handle   func(provider.Request) provider.Response
	requests []provider.Request
}

func (s *stubTransport) Send(_ context.Context, req provider.Request) (*provider.Response, error) {
	s.mu.Lock()
	s.requests = append(s.requests, req)
	s.mu.Unlock()
	resp := s.handle(req)
	return &resp, nil
}

func (s *stubTransport) all() []provider.Request {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]provider.Request(nil), s.requests...)
}

func (s *stubTransport) first(t *testing.T) provider.Request {
	t.Helper()
	reqs := s.all()
	require.NotEmpty(t, reqs)
	return reqs[0]
}

func routes(r map[string]string) *stubTransport {
	return &stubTransport{handle: func(req provider.Request) provider.Response {
		path := urlPath(req.URL)
		best := ""
		found := false
		for suffix := range r {
			if strings.HasSuffix(path, suffix) && (!found || len(suffix) > len(best)) {
				best, found = suffix, true
			}
		}
		if !found {
			return provider.Response{Status: 404}
		}
		return provider.Response{Status: 200, Body: []byte(r[best])}
	}}
}

func stubFunc(f func(provider.Request) provider.Response) *stubTransport {
	return &stubTransport{handle: f}
}

func urlPath(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	return u.Path
}

func urlQuery(raw string) url.Values {
	u, err := url.Parse(raw)
	if err != nil {
		return url.Values{}
	}
	return u.Query()
}

func testClient(t provider.Transport, name string) *provider.Client {
	c := provider.NewClient(name, t, provider.NewPacer(1000, 100))
	c.Sleep = func(context.Context, time.Duration) error { return nil }
	if name == "anilist" {
		c.Classify = ClassifyAniList
	}
	return c
}

func hasHeader(req provider.Request, name, value string) bool {
	for _, h := range req.Headers {
		if h[0] == name && h[1] == value {
			return true
		}
	}
	return false
}

func ptr[T any](v T) *T { return &v }
