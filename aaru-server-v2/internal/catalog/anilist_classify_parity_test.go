package catalog

import (
	"aaru-go-api/internal/provider"
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ProviderClientTests.aniListDisabled: AniList's "disabled" 403 is an outage, asked once; any
// other provider's 403 stays unauthorized.
func TestAniListDisabledIsAnOutageAskedOnce(t *testing.T) {
	body := `{"errors":[{"message":"The AniList API has been temporarily disabled due to ` +
		`severe stability issues.","status":403}]}`
	respond := func(status int, body string) *stubTransport {
		return stubFunc(func(provider.Request) provider.Response {
			return provider.Response{Status: status, Body: []byte(body)}
		})
	}
	get := func(transport *stubTransport, classify bool) error {
		c := testClient(transport, "test")
		if classify {
			c.Classify = ClassifyAniList
		}
		_, err := c.Data(context.Background(), provider.Request{URL: "https://provider.test/x"})
		return err
	}

	disabled := respond(403, body)
	require.ErrorIs(t, get(disabled, true), provider.NewError("test", provider.KindUnavailable))
	assert.Len(t, disabled.all(), 1, "asked once")

	behindCDN := respond(403, "<html>blocked</html>")
	assert.ErrorIs(t, get(behindCDN, true), provider.NewError("test", provider.KindUnavailable))

	plain := respond(403, body)
	assert.ErrorIs(t, get(plain, false), provider.NewError("test", provider.KindUnauthorized))
}
