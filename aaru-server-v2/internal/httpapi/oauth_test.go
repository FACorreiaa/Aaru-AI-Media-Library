package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/oauth"
	"aaru-go-api/internal/token"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// OAuth front door for Claude's connector (OUT-004).

const (
	oauthCallback = "https://claude.ai/api/mcp/auth_callback"
	oauthResource = "https://api.aaruapp.com/v1/mcp"
)

func jsonMap(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var m map[string]any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &m), rec.Body.String())
	return m
}

func (h *harness) form(path string, fields map[string]string) *httptest.ResponseRecorder {
	h.t.Helper()
	values := url.Values{}
	for k, v := range fields {
		values.Set(k, v)
	}
	return h.send(http.MethodPost, path, map[string]string{"Content-Type": "application/x-www-form-urlencoded"}, values.Encode())
}

func (h *harness) registerClient(name string) string {
	h.t.Helper()
	rec := h.send(http.MethodPost, "/oauth/register", map[string]string{"Content-Type": "application/json"},
		`{"client_name":"`+name+`","redirect_uris":["`+oauthCallback+`"]}`)
	require.Equal(h.t, http.StatusCreated, rec.Code, rec.Body.String())
	id, _ := jsonMap(h.t, rec)["client_id"].(string)
	require.True(h.t, strings.HasPrefix(id, "aaru_oc_"))
	return id
}

// authorize starts an authorization and approves it as the signed-in user; returns the code and verifier.
func (h *harness) authorize(bearer, clientID string, allowWrites bool) (code, verifier string) {
	h.t.Helper()
	t := h.t
	verifier = token.Generate() + token.Generate()
	q := url.Values{
		"client_id": {clientID}, "redirect_uri": {oauthCallback}, "response_type": {"code"}, "state": {"xyz"},
		"code_challenge": {oauth.Challenge(verifier)}, "code_challenge_method": {"S256"}, "resource": {oauthResource},
	}
	started := h.send(http.MethodGet, "/oauth/authorize?"+q.Encode(), nil, "")
	require.Equal(t, http.StatusFound, started.Code, started.Body.String())
	assert.Equal(t, "no-store", started.Header().Get("Cache-Control"))
	consent, err := url.Parse(started.Header().Get("Location"))
	require.NoError(t, err)
	assert.Equal(t, "aaruapp.com", consent.Host)
	assert.Equal(t, "/oauth/consent", consent.Path)
	requestID := consent.Query().Get("request")
	cookie := started.Header().Get("Set-Cookie")
	assert.Contains(t, cookie, "HttpOnly")
	assert.Contains(t, cookie, "Domain=aaruapp.com")
	assert.Contains(t, cookie, "; Secure")
	assert.Contains(t, cookie, "Max-Age=600")
	first, _, _ := strings.Cut(cookie, ";")
	_, binding, _ := strings.Cut(first, "=")

	shown := h.do(http.MethodGet, "/v1/oauth/requests/"+requestID, bearer, nil)
	require.Equal(t, http.StatusOK, shown.Code)
	assert.Equal(t, "claude.ai", jsonMap(t, shown)["redirectHost"])
	assert.Equal(t, http.StatusForbidden, h.do(http.MethodPost, "/v1/oauth/requests/"+requestID+"/approve", bearer, map[string]any{"binding": "stolen"}).Code,
		"another browser cannot answer")

	approved := h.do(http.MethodPost, "/v1/oauth/requests/"+requestID+"/approve", bearer, map[string]any{"binding": binding, "allowLibraryWrites": allowWrites})
	require.Equal(t, http.StatusOK, approved.Code, approved.Body.String())
	back, err := url.Parse(jsonMap(t, approved)["redirectTo"].(string))
	require.NoError(t, err)
	assert.Equal(t, "claude.ai", back.Host)
	assert.Equal(t, "xyz", back.Query().Get("state"))
	assert.Equal(t, "https://api.aaruapp.com", back.Query().Get("iss"))
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodPost, "/v1/oauth/requests/"+requestID+"/approve", bearer, map[string]any{"binding": binding}).Code,
		"answered once")
	return back.Query().Get("code"), verifier
}

func (h *harness) exchange(clientID, code, verifier string) *httptest.ResponseRecorder {
	return h.form("/oauth/token", map[string]string{
		"grant_type": "authorization_code", "code": code, "client_id": clientID, "code_verifier": verifier,
		"redirect_uri": oauthCallback, "resource": oauthResource,
	})
}

// mcpOpens is whether the access token authenticates on the MCP surface.
func (h *harness) mcpOpens(access string) bool {
	h.t.Helper()
	_, ok, err := h.server.AgentTokens.Authenticate(context.Background(), access, auth.GroupMCP)
	require.NoError(h.t, err)
	return ok
}

func TestOAuthDiscoveryNamesAarusEndpoints(t *testing.T) {
	h := newHarness(t)
	resource := h.send(http.MethodGet, "/.well-known/oauth-protected-resource/v1/mcp", nil, "")
	require.Equal(t, http.StatusOK, resource.Code)
	assert.JSONEq(t, `{"authorization_servers":["https://api.aaruapp.com"],"bearer_methods_supported":["header"],`+
		`"resource":"https://api.aaruapp.com/v1/mcp","resource_name":"Aaru","scopes_supported":["library:read","library:write"]}`, resource.Body.String())
	assert.Contains(t, resource.Body.String(), `"resource":"https://api.aaruapp.com/v1/mcp"`, "slashes are not escaped")
	assert.Equal(t, http.StatusOK, h.send(http.MethodGet, "/.well-known/oauth-protected-resource", nil, "").Code)

	server := h.send(http.MethodGet, "/.well-known/oauth-authorization-server", nil, "")
	assert.Equal(t, "*", server.Header().Get("Access-Control-Allow-Origin"))
	assert.Equal(t, "no-store", server.Header().Get("Cache-Control"))
	assert.Equal(t, "application/json", server.Header().Get("Content-Type"))
	metadata := jsonMap(t, server)
	assert.Equal(t, "https://api.aaruapp.com/oauth/register", metadata["registration_endpoint"])
	assert.Equal(t, []any{"S256"}, metadata["code_challenge_methods_supported"])
	assert.Equal(t, "https://api.aaruapp.com/.well-known/oauth-protected-resource/v1/mcp", h.server.OAuth.ResourceMetadataURL())

	preflight := h.send(http.MethodOptions, "/oauth/token", nil, "")
	assert.Equal(t, http.StatusNoContent, preflight.Code)
	assert.Equal(t, "GET, POST, OPTIONS", preflight.Header().Get("Access-Control-Allow-Methods"))
}

func TestOAuthRegistrationTakesHTTPSOrLoopbackAndAuthorizeNeverRedirectsElsewhere(t *testing.T) {
	h := newHarness(t)
	jsonHeader := map[string]string{"Content-Type": "application/json"}
	bad := h.send(http.MethodPost, "/oauth/register", jsonHeader, `{"client_name":"x","redirect_uris":["http://evil.example/cb"]}`)
	assert.Equal(t, http.StatusBadRequest, bad.Code)
	assert.Equal(t, "invalid_redirect_uri", jsonMap(t, bad)["error"])
	for _, uris := range []string{`[]`, `["https://x.example/cb#frag"]`, `["https://user@x.example/cb"]`, `["HTTPS://x.example/cb"]`} {
		rec := h.send(http.MethodPost, "/oauth/register", jsonHeader, `{"redirect_uris":`+uris+`}`)
		assert.Equal(t, "invalid_redirect_uri", jsonMap(t, rec)["error"], uris)
	}
	notJSON := h.send(http.MethodPost, "/oauth/register", jsonHeader, `nope`)
	assert.Equal(t, "invalid_client_metadata", jsonMap(t, notJSON)["error"])

	loopback := h.send(http.MethodPost, "/oauth/register", jsonHeader, `{"client_name":"Claude Code","redirect_uris":["http://localhost:4567/callback"]}`)
	require.Equal(t, http.StatusCreated, loopback.Code)
	reg := jsonMap(t, loopback)
	assert.Equal(t, "none", reg["token_endpoint_auth_method"])
	assert.Equal(t, "Claude Code", reg["client_name"])
	loopbackID := reg["client_id"].(string)
	// Loopback redirects match on any port (RFC 8252).
	q := url.Values{
		"client_id": {loopbackID}, "redirect_uri": {"http://localhost:9999/callback"}, "response_type": {"code"},
		"code_challenge": {strings.Repeat("a", 43)}, "code_challenge_method": {"S256"},
	}
	assert.Equal(t, http.StatusFound, h.send(http.MethodGet, "/oauth/authorize?"+q.Encode(), nil, "").Code)

	clientID := h.registerClient("Claude")
	hijack := h.send(http.MethodGet, "/oauth/authorize?client_id="+clientID+"&redirect_uri=https://evil.example/cb"+
		"&response_type=code&code_challenge="+strings.Repeat("a", 43)+"&code_challenge_method=S256", nil, "")
	assert.Equal(t, http.StatusBadRequest, hijack.Code)
	assert.Empty(t, hijack.Header().Get("Location"))
	assert.Equal(t, "text/plain; charset=utf-8", hijack.Header().Get("Content-Type"))
	assert.Equal(t, "This app's return address does not match what it registered.", hijack.Body.String())

	unknown := h.send(http.MethodGet, "/oauth/authorize?client_id=aaru_oc_nope", nil, "")
	assert.Equal(t, http.StatusBadRequest, unknown.Code)

	plain := h.send(http.MethodGet, "/oauth/authorize?client_id="+clientID+"&redirect_uri="+oauthCallback+
		"&response_type=code&code_challenge=abc&code_challenge_method=plain&state=s", nil, "")
	assert.Equal(t, http.StatusFound, plain.Code)
	assert.Equal(t, oauthCallback+"?error=invalid_request&error_description=PKCE%20with%20S256%20is%20required.&iss=https://api.aaruapp.com&state=s",
		plain.Header().Get("Location"), "S256 only, encoded as Foundation does")

	target := h.send(http.MethodGet, "/oauth/authorize?client_id="+clientID+"&redirect_uri="+oauthCallback+
		"&response_type=code&code_challenge="+strings.Repeat("a", 43)+"&code_challenge_method=S256&resource=https://other.example/mcp", nil, "")
	assert.Contains(t, target.Header().Get("Location"), "error=invalid_target")
	code := h.send(http.MethodGet, "/oauth/authorize?client_id="+clientID+"&redirect_uri="+oauthCallback+"&response_type=token", nil, "")
	assert.Contains(t, code.Header().Get("Location"), "error=unsupported_response_type")
}

func TestOAuthFullFlowRefreshRotationAndReuseDetection(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	clientID := h.registerClient("Claude")
	code, verifier := h.authorize(bearer, clientID, true)
	wrong := h.exchange(clientID, code, verifier+"x")
	assert.Equal(t, http.StatusBadRequest, wrong.Code)
	assert.Equal(t, "invalid_grant", jsonMap(t, wrong)["error"], "PKCE mismatch, and the code is spent")

	fresh, freshVerifier := h.authorize(bearer, clientID, true)
	rec := h.exchange(clientID, fresh, freshVerifier)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	tokens := jsonMap(t, rec)
	access := tokens["access_token"].(string)
	refresh := tokens["refresh_token"].(string)
	assert.True(t, strings.HasPrefix(access, "aaru_oat_"))
	assert.True(t, strings.HasPrefix(refresh, "aaru_ort_"))
	assert.Equal(t, "library:read library:write", tokens["scope"])
	assert.Equal(t, "Bearer", tokens["token_type"])
	assert.Contains(t, rec.Body.String(), `"expires_in":3600`)
	assert.True(t, h.mcpOpens(access))
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/library/items", access, nil).Code, "never a session")

	listed := h.do(http.MethodGet, "/v1/agent/tokens?for=mcp", bearer, nil)
	items := jsonMap(t, listed)["items"].([]any)
	require.Len(t, items, 1)
	assert.Equal(t, "claude", items[0].(map[string]any)["kind"])
	assert.Equal(t, "Claude", items[0].(map[string]any)["name"])

	rotated := jsonMap(t, h.form("/oauth/token", map[string]string{"grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID}))
	newAccess := rotated["access_token"].(string)
	assert.False(t, h.mcpOpens(access), "the old access token is replaced")
	assert.True(t, h.mcpOpens(newAccess))

	replay := h.form("/oauth/token", map[string]string{"grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID})
	assert.Equal(t, "invalid_grant", jsonMap(t, replay)["error"])
	assert.False(t, h.mcpOpens(newAccess), "a replayed refresh revokes the connection")
}

func TestOAuthReusedCodeRevokesWhatItIssuedAndSettingsRevokeStopsRefresh(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	clientID := h.registerClient("Claude")
	code, verifier := h.authorize(bearer, clientID, false)
	first := jsonMap(t, h.exchange(clientID, code, verifier))
	access := first["access_token"].(string)
	assert.Equal(t, "library:read", first["scope"])
	again := h.exchange(clientID, code, verifier)
	assert.Equal(t, "invalid_grant", jsonMap(t, again)["error"])
	assert.False(t, h.mcpOpens(access))

	second, secondVerifier := h.authorize(bearer, clientID, false)
	refresh := jsonMap(t, h.exchange(clientID, second, secondVerifier))["refresh_token"].(string)
	items := jsonMap(t, h.do(http.MethodGet, "/v1/agent/tokens?for=mcp", bearer, nil))["items"].([]any)
	require.Len(t, items, 1)
	id := items[0].(map[string]any)["id"].(string)
	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/agent/tokens/"+id, bearer, nil).Code)
	refused := h.form("/oauth/token", map[string]string{"grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID})
	assert.Equal(t, "invalid_grant", jsonMap(t, refused)["error"])
}

func TestOAuthDenyRevokeAndTokenErrors(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	clientID := h.registerClient("Codex CLI")
	q := url.Values{
		"client_id": {clientID}, "redirect_uri": {oauthCallback}, "response_type": {"code"},
		"code_challenge": {oauth.Challenge("v")}, "code_challenge_method": {"S256"},
	}
	started := h.send(http.MethodGet, "/oauth/authorize?"+q.Encode(), nil, "")
	consent, err := url.Parse(started.Header().Get("Location"))
	require.NoError(t, err)
	requestID := consent.Query().Get("request")
	first, _, _ := strings.Cut(started.Header().Get("Set-Cookie"), ";")
	_, binding, _ := strings.Cut(first, "=")
	assert.Equal(t, "codex", jsonMap(t, h.do(http.MethodGet, "/v1/oauth/requests/"+requestID, bearer, nil))["kind"])
	denied := h.do(http.MethodPost, "/v1/oauth/requests/"+requestID+"/deny", bearer, map[string]string{"binding": binding})
	require.Equal(t, http.StatusOK, denied.Code)
	assert.Equal(t, oauthCallback+"?error=access_denied&error_description=The%20user%20said%20no.&iss=https://api.aaruapp.com",
		jsonMap(t, denied)["redirectTo"])
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/oauth/requests/"+requestID, bearer, nil).Code)

	assert.Equal(t, "unsupported_grant_type", jsonMap(t, h.form("/oauth/token", map[string]string{"grant_type": "password"}))["error"])
	assert.Equal(t, "invalid_request", jsonMap(t, h.form("/oauth/token", map[string]string{"grant_type": "authorization_code"}))["error"])
	assert.Equal(t, "invalid_request", jsonMap(t, h.form("/oauth/token", map[string]string{"grant_type": "refresh_token"}))["error"])
	revoke := h.form("/oauth/revoke", map[string]string{"token": "aaru_oat_unknown"})
	assert.Equal(t, http.StatusOK, revoke.Code)
	assert.Equal(t, "{}", revoke.Body.String())

	big := h.send(http.MethodPost, "/oauth/token", map[string]string{"Content-Type": "application/x-www-form-urlencoded"}, "grant_type="+strings.Repeat("a", 17*1024))
	assert.Equal(t, http.StatusInternalServerError, big.Code)
	assert.Equal(t, "server_error", jsonMap(t, big)["error"])
}

func TestOAuthRevokeEndsTheConnection(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	clientID := h.registerClient("Claude")
	code, verifier := h.authorize(bearer, clientID, false)
	tokens := jsonMap(t, h.exchange(clientID, code, verifier))
	access := tokens["access_token"].(string)
	assert.Equal(t, http.StatusOK, h.form("/oauth/revoke", map[string]string{"token": tokens["refresh_token"].(string)}).Code)
	assert.False(t, h.mcpOpens(access), "revoking the refresh token ends the access token too")
}

func TestOAuthHelpers(t *testing.T) {
	assert.Equal(t, auth.KindClaudeCode, oauth.KindForClientName("Claude Code (aaru)"))
	assert.Equal(t, auth.KindClaude, oauth.KindForClientName("claude.ai"))
	assert.Equal(t, auth.KindGemini, oauth.KindForClientName("Gemini CLI"))
	assert.Equal(t, auth.KindOther, oauth.KindForClientName("Cursor"))
	assert.Equal(t, "https://x.example/cb?a=1&state=a%20b%26c%3Dd+e/f",
		oauth.RedirectURL("https://x.example/cb?a=1", map[string]*string{"state": ptrTo("a b&c=d+e/f"), "none": nil}))
	_, ok := oauth.Registered("http://127.0.0.1:1234/cb", []string{"http://127.0.0.1/cb"})
	assert.True(t, ok)
	_, ok = oauth.Registered("http://127.0.0.1:1234/other", []string{"http://127.0.0.1/cb"})
	assert.False(t, ok)
	_, ok = oauth.Registered("https://claude.ai:444/api/mcp/auth_callback", []string{oauthCallback})
	assert.False(t, ok, "only loopback ignores the port")
	assert.True(t, oauth.AcceptableRedirect("http://[::1]:8080/cb"))
	assert.False(t, oauth.AcceptableRedirect("http://192.168.1.2/cb"))
}

func ptrTo(s string) *string { return &s }
