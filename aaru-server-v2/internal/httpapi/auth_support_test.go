package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/oauth"
	"net/http"
)

// withAuthDefaults wires auth as production does, but with no outbound client a
// test could reach the network with: verifiers and senders are replaced per test.
func withAuthDefaults(d *Deps) {
	d.Auth, d.AgentTokens = auth.FromConfig(d.Config, d.Pool, &http.Client{Transport: refuseNetwork{}})
	d.OAuth = oauth.FromConfig(d.Config, d.Pool)
}

type refuseNetwork struct{}

func (refuseNetwork) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, http.ErrHandlerTimeout
}
