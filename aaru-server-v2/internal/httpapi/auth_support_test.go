package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/oauth"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"
)

// withAuthDefaults wires auth as production does, but with no outbound client a
// test could reach the network with: verifiers and senders are replaced per test.
func withAuthDefaults(t testing.TB, d *Deps) {
	t.Helper()
	var err error
	d.Auth, d.AgentTokens, err = auth.FromConfig(d.Config, d.Pool, &http.Client{Transport: refuseNetwork{}})
	require.NoError(t, err)
	d.OAuth = oauth.FromConfig(d.Config, d.Pool)
}

type refuseNetwork struct{}

func (refuseNetwork) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, http.ErrHandlerTimeout
}
