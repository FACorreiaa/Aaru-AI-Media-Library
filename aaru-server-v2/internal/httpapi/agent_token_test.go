package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/token"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Agent tokens (OUT-001): create, list, revoke, scopes, setup.

func TestAgentTokenLifecycleShowsTheSecretOnceAndNeverStoresIt(t *testing.T) {
	h := newHarness(t)
	userID, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]string{"kind": "stremio"})
	require.Equal(t, http.StatusCreated, rec.Code, rec.Body.String())
	created := decode[api.AgentTokenCreated](t, rec)
	secret := created.Secret
	assert.True(t, strings.HasPrefix(secret, "aaru_st_"))
	assert.Equal(t, "Stremio", created.Token.Name)
	assert.Equal(t, []api.AgentTokenScopes{"library:read", "scrobble:write"}, created.Token.Scopes)
	require.NotNil(t, created.Stremio)
	assert.Equal(t, "https://api.aaruapp.com/stremio/"+secret+"/manifest.json", created.Stremio.ManifestUrl)
	assert.Equal(t, "stremio://api.aaruapp.com/stremio/"+secret+"/manifest.json", created.Stremio.InstallUrl)
	assert.Equal(t, "https://web.stremio.com/#/addons?addon=https%3A%2F%2Fapi.aaruapp.com%2Fstremio%2F"+secret+"%2Fmanifest.json", created.Stremio.WebInstallUrl)
	assert.Nil(t, created.Setup)
	assert.Nil(t, created.Music)

	var stored string
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT token_hash FROM agent_tokens WHERE id = $1`, created.Token.Id).Scan(&stored))
	assert.Equal(t, token.Hash(secret), stored)
	assert.NotContains(t, stored, secret)

	listRec := h.do(http.MethodGet, "/v1/agent/tokens", bearer, nil)
	assert.NotContains(t, listRec.Body.String(), "secret")
	listed := decode[api.ListAgentTokens200JSONResponse](t, listRec).Items
	require.Len(t, listed, 1)
	assert.Equal(t, created.Token.Id, listed[0].Id)

	svc := h.server.AgentTokens
	ctx := context.Background()
	caller, ok, err := svc.Authenticate(ctx, secret, auth.GroupStremio)
	require.NoError(t, err)
	require.True(t, ok)
	assert.Equal(t, userID, caller.UserID)
	assert.True(t, caller.Has(auth.ScopeScrobbleWrite))
	assert.False(t, caller.Has(auth.ScopeLibraryWrite))
	_, ok, _ = svc.Authenticate(ctx, "aaru_st_wrong", auth.GroupStremio)
	assert.False(t, ok)
	_, ok, _ = svc.Authenticate(ctx, strings.TrimPrefix(secret, "aaru_st_"), auth.GroupStremio)
	assert.False(t, ok, "prefix required")
	_, ok, _ = svc.Authenticate(ctx, secret, auth.GroupMCP)
	assert.False(t, ok, "a Stremio secret opens no other surface")

	var lastUsed *string
	require.NoError(t, h.pool.QueryRow(ctx, `SELECT last_used_at::text FROM agent_tokens WHERE id = $1`, created.Token.Id).Scan(&lastUsed))
	assert.NotNil(t, lastUsed, "use is recorded")

	path := "/v1/agent/tokens/" + created.Token.Id.String()
	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, path, bearer, nil).Code)
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodDelete, path, bearer, nil).Code)
	_, ok, _ = svc.Authenticate(ctx, secret, auth.GroupStremio)
	assert.False(t, ok, "revoked")
	assert.Empty(t, decode[api.ListAgentTokens200JSONResponse](t, h.do(http.MethodGet, "/v1/agent/tokens", bearer, nil)).Items)
}

func TestLibraryWritesAreOptInAndAnotherUserCannotRevoke(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]any{"kind": "stremio", "name": "  Living room ", "allowLibraryWrites": true})
	require.Equal(t, http.StatusCreated, rec.Code)
	created := decode[api.AgentTokenCreated](t, rec)
	assert.Equal(t, "Living room", created.Token.Name)
	assert.Equal(t, []api.AgentTokenScopes{"library:read", "library:write", "scrobble:write"}, created.Token.Scopes)

	_, other := h.signIn()
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodDelete, "/v1/agent/tokens/"+created.Token.Id.String(), other, nil).Code)
	rec = h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]any{"kind": "stremio", "name": strings.Repeat("x", 81)})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Equal(t, "At most 80 characters.", (*decode[api.ErrorResponse](t, rec).Details)["name"])
}

func TestMCPTokensHaveTheirOwnPrefixScopesSetupAndList(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]any{"kind": "codex", "allowImports": true})
	require.Equal(t, http.StatusCreated, rec.Code)
	created := decode[api.AgentTokenCreated](t, rec)
	assert.True(t, strings.HasPrefix(created.Secret, "aaru_mcp_"))
	assert.Equal(t, api.AgentTokenKind("codex"), created.Token.Kind)
	assert.Equal(t, "Codex", created.Token.Name)
	assert.Equal(t, []api.AgentTokenScopes{"imports:write", "library:read"}, created.Token.Scopes, "never scrobble:write")
	assert.Nil(t, created.Stremio)
	require.NotNil(t, created.Setup)
	assert.Equal(t, "https://api.aaruapp.com/v1/mcp", created.Setup.Url)
	assert.Equal(t, api.AgentSetupAuthToken, created.Setup.Auth)
	var hasSecret, hasAdd bool
	for _, s := range created.Setup.Steps {
		hasSecret = hasSecret || strings.Contains(s.Text, created.Secret)
		hasAdd = hasAdd || strings.Contains(s.Text, "codex mcp add aaru")
	}
	assert.True(t, hasSecret)
	assert.True(t, hasAdd)

	_, ok, err := h.server.AgentTokens.Authenticate(context.Background(), created.Secret, auth.GroupMCP)
	require.NoError(t, err)
	assert.True(t, ok)

	require.Equal(t, http.StatusCreated, h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]string{"kind": "stremio"}).Code)
	kinds := func(path string) []api.AgentTokenKind {
		var out []api.AgentTokenKind
		for _, item := range decode[api.ListAgentTokens200JSONResponse](t, h.do(http.MethodGet, path, bearer, nil)).Items {
			out = append(out, item.Kind)
		}
		return out
	}
	assert.Equal(t, []api.AgentTokenKind{"stremio"}, kinds("/v1/agent/tokens"), "default stays Stremio")
	assert.Equal(t, []api.AgentTokenKind{"codex"}, kinds("/v1/agent/tokens?for=mcp"))
	assert.Equal(t, http.StatusBadRequest, h.do(http.MethodGet, "/v1/agent/tokens?for=nope", bearer, nil).Code)

	preview := decode[api.AgentSetup](t, h.do(http.MethodGet, "/v1/agent/setup/hermes", bearer, nil))
	var hasHermes, hasPlaceholder bool
	for _, s := range preview.Steps {
		hasHermes = hasHermes || strings.Contains(s.Text, "hermes mcp add aaru")
		hasPlaceholder = hasPlaceholder || (s.Note != nil && strings.Contains(*s.Note, agentSetupPlaceholder))
	}
	assert.True(t, hasHermes)
	assert.True(t, hasPlaceholder)
	assert.Equal(t, http.StatusBadRequest, h.do(http.MethodGet, "/v1/agent/setup/stremio", bearer, nil).Code)
	claude := decode[api.AgentSetup](t, h.do(http.MethodGet, "/v1/agent/setup/claude", bearer, nil))
	assert.Equal(t, api.AgentSetupAuthOauth, claude.Auth)
	assert.Equal(t, "Claude", claude.Title)
}

func TestScrobbleAndMusicTokensOnlyScrobble(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	browser := decode[api.AgentTokenCreated](t, h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]any{"kind": "browser", "allowLibraryWrites": true}))
	assert.True(t, strings.HasPrefix(browser.Secret, "aaru_scr_"))
	assert.Equal(t, []api.AgentTokenScopes{"scrobble:write"}, browser.Token.Scopes)
	assert.Equal(t, "Browser extension", browser.Token.Name)
	assert.Nil(t, browser.Setup)

	music := decode[api.AgentTokenCreated](t, h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]any{"kind": "music", "scrobbler": "navidrome"}))
	assert.True(t, strings.HasPrefix(music.Secret, "aaru_lb_"))
	assert.Equal(t, "Navidrome", music.Token.Name, "named for its scrobbler")
	require.NotNil(t, music.Music)
	assert.Equal(t, "https://api.aaruapp.com/listenbrainz/", music.Music.BaseUrl)
	assert.Equal(t, "https://api.aaruapp.com/listenbrainz/1/submit-listens", music.Music.SubmitUrl)
	require.NotNil(t, music.Music.Steps[0].Fields)
	assert.Equal(t, "https://api.aaruapp.com/listenbrainz/1/", (*music.Music.Steps[0].Fields)[0].Value)
	assert.Equal(t, music.Secret, (*music.Music.Steps[1].Fields)[0].Value)
	assert.True(t, *(*music.Music.Steps[1].Fields)[0].Secret)

	other := decode[api.AgentTokenCreated](t, h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]any{"kind": "music"}))
	assert.Equal(t, "Music scrobbler", other.Token.Name)
	assert.Equal(t, api.MusicScrobblerOther, other.Music.Scrobbler)

	ctx := context.Background()
	_, ok, _ := h.server.AgentTokens.Authenticate(ctx, music.Secret, auth.GroupMusic)
	assert.True(t, ok)
	_, ok, _ = h.server.AgentTokens.Authenticate(ctx, browser.Secret, auth.GroupScrobble)
	assert.True(t, ok)
	_, ok, _ = h.server.AgentTokens.Authenticate(ctx, music.Secret, auth.GroupScrobble)
	assert.False(t, ok)
}

func TestClaudeConnectsOverOAuthNeverWithAPastedToken(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]string{"kind": "claude"})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Equal(t, "Claude connects over OAuth.", (*decode[api.ErrorResponse](t, rec).Details)["kind"])
	assert.Equal(t, http.StatusBadRequest, h.do(http.MethodPost, "/v1/agent/tokens", bearer, map[string]string{"kind": "nope"}).Code)
}

func TestAgentTokenBudgetIs120AMinute(t *testing.T) {
	h := newHarness(t)
	caller := auth.AgentCaller{Token: auth.AgentToken{}}
	for range auth.RequestsPerMinute {
		require.True(t, h.server.AgentTokens.Allow(caller))
	}
	assert.False(t, h.server.AgentTokens.Allow(caller))
}
