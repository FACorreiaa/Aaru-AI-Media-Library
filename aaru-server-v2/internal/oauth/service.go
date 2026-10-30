// Package oauth is OUT-004's OAuth 2.1 front door, the one the MCP authorization
// spec asks of a remote server, so Claude (claude.ai, Desktop, mobile) can add
// Aaru as a custom connector. Clients register themselves, the user approves on
// the web (`/oauth/consent`), and the tokens are an ordinary agent token: the
// same scopes, the same MCP surface, revocable in Settings.
package oauth

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/token"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Error is an OAuth error as RFC 6749 §5.2 shapes it, safe to show the client.
type Error struct {
	Status      int
	Code        string
	Description string
}

func (e *Error) Error() string { return e.Code + ": " + e.Description }

func oauthError(code, description string) *Error {
	return &Error{Status: http.StatusBadRequest, Code: code, Description: description}
}

// Settings come from PUBLIC_BASE_URL, WEB_BASE_URL and OAUTH_COOKIE_DOMAIN.
type Settings struct {
	// PublicBaseURL is this API: issuer, endpoints and the MCP resource.
	PublicBaseURL *url.URL
	// WebBaseURL is where the consent page lives.
	WebBaseURL *url.URL
	// CookieDomain is the binding cookie's `Domain`, so the web app can read what the API set. Nil: host-only.
	CookieDomain *string
}

// Lifetimes and names, as the Swift OAuthService had them.
const (
	AccessLifetime    = time.Hour
	RefreshLifetime   = 30 * 24 * time.Hour
	RequestLifetime   = 10 * time.Minute
	CodeLifetime      = time.Minute
	BindingCookieName = "aaru_oauth"
	ClientPrefix      = "aaru_oc_"
	RefreshPrefix     = "aaru_ort_"
)

// Service is OAuthService.
type Service struct {
	store    *Store
	settings Settings
	// registrations per client address per hour: registering is anonymous.
	registrations *ratelimit.FixedWindow
	Now           func() time.Time
}

// NewService builds the service.
func NewService(store *Store, settings Settings) *Service {
	return &Service{store: store, settings: settings, registrations: ratelimit.New(20, time.Hour), Now: time.Now}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Issuer is PUBLIC_BASE_URL without a trailing slash.
func (s *Service) Issuer() string {
	return strings.TrimSuffix(s.settings.PublicBaseURL.String(), "/")
}

// Resource is the MCP endpoint.
func (s *Service) Resource() string {
	return auth.MCPEndpoint(s.settings.PublicBaseURL)
}

// ResourceMetadataURL is what an unauthenticated MCP call's `WWW-Authenticate` points at.
func (s *Service) ResourceMetadataURL() string {
	return s.Issuer() + "/.well-known/oauth-protected-resource/v1/mcp"
}

var supportedScopes = []any{"library:read", "library:write"}

// ProtectedResource is RFC 9728's document.
func (s *Service) ProtectedResource() map[string]any {
	return map[string]any{
		"resource":                 s.Resource(),
		"resource_name":            "Aaru",
		"authorization_servers":    []any{s.Issuer()},
		"scopes_supported":         supportedScopes,
		"bearer_methods_supported": []any{"header"},
	}
}

// AuthorizationServer is RFC 8414's document.
func (s *Service) AuthorizationServer() map[string]any {
	issuer := s.Issuer()
	return map[string]any{
		"issuer":                                issuer,
		"authorization_endpoint":                issuer + "/oauth/authorize",
		"token_endpoint":                        issuer + "/oauth/token",
		"registration_endpoint":                 issuer + "/oauth/register",
		"revocation_endpoint":                   issuer + "/oauth/revoke",
		"response_types_supported":              []any{"code"},
		"grant_types_supported":                 []any{"authorization_code", "refresh_token"},
		"code_challenge_methods_supported":      []any{"S256"},
		"token_endpoint_auth_methods_supported": []any{"none"},
		"scopes_supported":                      supportedScopes,
	}
}

// Registration is RFC 7591's client metadata, the two fields Aaru reads.
type Registration struct {
	ClientName   *string  `json:"client_name"`
	RedirectURIs []string `json:"redirect_uris"`
}

// Register registers a public client. Whatever auth method it asks for, it is
// registered with `none` (RFC 7591 lets the server substitute); PKCE protects the code.
func (s *Service) Register(ctx context.Context, body Registration, clientAddress string) (map[string]any, error) {
	if !s.registrations.Allow(clientAddress, s.now()) {
		return nil, &Error{Status: http.StatusTooManyRequests, Code: "slow_down", Description: "Too many registrations."}
	}
	uris := body.RedirectURIs
	ok := len(uris) >= 1 && len(uris) <= 10
	for _, u := range uris {
		ok = ok && AcceptableRedirect(u)
	}
	if !ok {
		return nil, oauthError("invalid_redirect_uri", "Redirect URIs must be https, or http on localhost, without a fragment.")
	}
	name := "MCP client"
	if body.ClientName != nil {
		name = *body.ClientName
	}
	name = prefixRunes(strings.Trim(name, " \t"), 80)
	if name == "" {
		name = "MCP client"
	}
	client := Client{ID: ClientPrefix + token.Generate()[:22], Name: name, RedirectURIs: uris, CreatedAt: s.now()}
	if err := s.store.register(ctx, client); err != nil {
		return nil, err
	}
	redirects := make([]any, len(uris))
	for i, u := range uris {
		redirects[i] = u
	}
	return map[string]any{
		"client_id":                  client.ID,
		"client_name":                client.Name,
		"redirect_uris":              redirects,
		"grant_types":                []any{"authorization_code", "refresh_token"},
		"response_types":             []any{"code"},
		"token_endpoint_auth_method": "none",
		"client_id_issued_at":        client.CreatedAt.Unix(),
	}, nil
}

// Authorization is what `/oauth/authorize` answers: exactly one field is set.
type Authorization struct {
	// Refuse: the client or redirect cannot be trusted; say so here, never redirect.
	Refuse string
	// Redirect: a protocol error the client should hear about, at its redirect URI.
	Redirect string
	// Consent: off to the consent page, with the binding cookie for this browser.
	Consent string
	Binding string
}

// Authorize starts an authorization request from the query parameters.
func (s *Service) Authorize(ctx context.Context, query map[string]string) (Authorization, error) {
	clientID, has := query["client_id"]
	var client Client
	if has {
		var found bool
		var err error
		if client, found, err = s.store.client(ctx, clientID); err != nil {
			return Authorization{}, err
		}
		has = found
	}
	if !has {
		return Authorization{Refuse: "This app is not registered with Aaru. Try connecting again from the app."}, nil
	}
	presented, ok := query["redirect_uri"]
	redirect := ""
	if ok {
		redirect, ok = Registered(presented, client.RedirectURIs)
	}
	if !ok {
		return Authorization{Refuse: "This app's return address does not match what it registered."}, nil
	}
	var state *string
	if v, ok := query["state"]; ok {
		state = &v
	}
	fail := func(code, description string) Authorization {
		return Authorization{Redirect: RedirectURL(redirect, map[string]*string{
			"error": &code, "error_description": &description, "state": state, "iss": ptr(s.Issuer()),
		})}
	}
	if query["response_type"] != "code" {
		return fail("unsupported_response_type", "Only the code flow is supported."), nil
	}
	challenge, hasChallenge := query["code_challenge"]
	if n := utf8.RuneCountInString(challenge); query["code_challenge_method"] != "S256" || !hasChallenge || n < 43 || n > 128 {
		return fail("invalid_request", "PKCE with S256 is required."), nil
	}
	var resource *string
	if r, ok := query["resource"]; ok {
		if strings.TrimSuffix(r, "/") != s.Resource() {
			return fail("invalid_target", "Aaru's MCP endpoint is "+s.Resource()+"."), nil
		}
		resource = &r
	}
	binding := token.Generate()
	request := Request{
		ID: uuid.New(), ClientID: client.ID, RedirectURI: redirect, State: state, CodeChallenge: challenge,
		Resource: resource, BindingHash: token.Hash(binding), ExpiresAt: s.now().Add(RequestLifetime),
	}
	if err := s.store.createRequest(ctx, request); err != nil {
		return Authorization{}, err
	}
	consent := auth.AppendPath(s.settings.WebBaseURL, "oauth", "consent") + "?request=" + request.ID.String()
	return Authorization{Consent: consent, Binding: binding}, nil
}

// BindingCookie is the `Set-Cookie` value that ties the request to this browser.
func (s *Service) BindingCookie(binding string) string {
	cookie := fmt.Sprintf("%s=%s; Path=/; Max-Age=%d; HttpOnly; SameSite=Lax", BindingCookieName, binding, int(RequestLifetime.Seconds()))
	if s.settings.PublicBaseURL.Scheme == "https" {
		cookie += "; Secure"
	}
	if d := s.settings.CookieDomain; d != nil && *d != "" {
		cookie += "; Domain=" + *d
	}
	return cookie
}

// Pending is a live request and its client, for the consent page.
func (s *Service) Pending(ctx context.Context, id uuid.UUID) (Request, Client, error) {
	request, found, err := s.store.request(ctx, id, s.now())
	if err != nil {
		return Request{}, Client{}, err
	}
	var client Client
	if found {
		if client, found, err = s.store.client(ctx, request.ClientID); err != nil {
			return Request{}, Client{}, err
		}
	}
	if !found {
		return Request{}, Client{}, apperr.NotFound("This connection request expired. Start again from the app.")
	}
	return request, client, nil
}

// Approve answers yes: a one-minute code for the client, at its redirect URI.
func (s *Service) Approve(ctx context.Context, id, userID uuid.UUID, binding string, name *string, allowWrites bool) (string, error) {
	request, client, err := s.answer(ctx, id, binding)
	if err != nil {
		return "", err
	}
	code := token.Generate()
	kind := KindForClientName(client.Name)
	trimmed := ""
	if name != nil {
		trimmed = strings.TrimSpace(*name)
	}
	if trimmed == "" {
		trimmed = kind.Label()
	} else {
		trimmed = prefixRunes(trimmed, 80)
	}
	if err := s.store.createCode(ctx, Code{
		ClientID: client.ID, UserID: userID, RedirectURI: request.RedirectURI, CodeChallenge: request.CodeChallenge,
		Resource: request.Resource, Name: trimmed, Kind: kind, AllowWrites: allowWrites, ExpiresAt: s.now().Add(CodeLifetime),
	}, token.Hash(code)); err != nil {
		return "", err
	}
	return RedirectURL(request.RedirectURI, map[string]*string{"code": &code, "state": request.State, "iss": ptr(s.Issuer())}), nil
}

// Deny answers no, at the client's redirect URI.
func (s *Service) Deny(ctx context.Context, id uuid.UUID, binding string) (string, error) {
	request, _, err := s.answer(ctx, id, binding)
	if err != nil {
		return "", err
	}
	return RedirectURL(request.RedirectURI, map[string]*string{
		"error": ptr("access_denied"), "error_description": ptr("The user said no."), "state": request.State, "iss": ptr(s.Issuer()),
	}), nil
}

// answer: only the browser that started the request may answer it, and only once.
func (s *Service) answer(ctx context.Context, id uuid.UUID, binding string) (Request, Client, error) {
	request, client, err := s.Pending(ctx, id)
	if err != nil {
		return Request{}, Client{}, err
	}
	if token.Hash(binding) != request.BindingHash {
		return Request{}, Client{}, apperr.Forbidden("Open this from the app you are connecting, in this browser.")
	}
	consumed, err := s.store.consumeRequest(ctx, id, s.now())
	if err != nil {
		return Request{}, Client{}, err
	}
	if !consumed {
		return Request{}, Client{}, apperr.NotFound("This connection request was already answered.")
	}
	return request, client, nil
}

// Token is the token endpoint: `authorization_code` or `refresh_token`.
func (s *Service) Token(ctx context.Context, form map[string]string) (map[string]any, error) {
	switch form["grant_type"] {
	case "authorization_code":
		return s.exchange(ctx, form)
	case "refresh_token":
		return s.refresh(ctx, form)
	}
	return nil, oauthError("unsupported_grant_type", "Use authorization_code or refresh_token.")
}

func (s *Service) exchange(ctx context.Context, form map[string]string) (map[string]any, error) {
	invalid := oauthError("invalid_grant", "The code is invalid, used or expired.")
	code, ok1 := form["code"]
	verifier, ok2 := form["code_verifier"]
	clientID, ok3 := form["client_id"]
	if !ok1 || !ok2 || !ok3 {
		return nil, oauthError("invalid_request", "code, code_verifier and client_id are required.")
	}
	codeHash := token.Hash(code)
	grant, outcome, err := s.store.redeemCode(ctx, codeHash, s.now())
	if err != nil {
		return nil, err
	}
	if outcome != redemptionFresh || grant.ClientID != clientID || Challenge(verifier) != grant.CodeChallenge {
		return nil, invalid
	}
	if r, ok := form["redirect_uri"]; ok && r != grant.RedirectURI {
		return nil, invalid
	}
	if r, ok := form["resource"]; ok && strings.TrimSuffix(r, "/") != s.Resource() {
		return nil, invalid
	}
	scopes := []auth.Scope{auth.ScopeLibraryRead}
	if grant.AllowWrites {
		scopes = append(scopes, auth.ScopeLibraryWrite)
	}
	now := s.now()
	t := auth.AgentToken{ID: uuid.New(), Name: grant.Name, Kind: grant.Kind, Scopes: scopes, CreatedAt: now}
	access := auth.OAuthPrefix + token.Generate()
	refresh := RefreshPrefix + token.Generate()
	if err := s.store.issue(ctx, issue{
		token: t, userID: grant.UserID, clientID: clientID, codeHash: codeHash,
		accessHash: token.Hash(access), accessExpiresAt: now.Add(AccessLifetime),
		refreshHash: token.Hash(refresh), refreshExpiresAt: now.Add(RefreshLifetime),
	}); err != nil {
		return nil, err
	}
	return tokens(access, refresh, scopes), nil
}

func (s *Service) refresh(ctx context.Context, form map[string]string) (map[string]any, error) {
	presented, ok1 := form["refresh_token"]
	clientID, ok2 := form["client_id"]
	if !ok1 || !ok2 {
		return nil, oauthError("invalid_request", "refresh_token and client_id are required.")
	}
	access := auth.OAuthPrefix + token.Generate()
	refresh := RefreshPrefix + token.Generate()
	now := s.now()
	scopes, outcome, err := s.store.rotate(ctx, rotation{
		refreshHash: token.Hash(presented), clientID: clientID, now: now,
		accessHash: token.Hash(access), accessExpiresAt: now.Add(AccessLifetime),
		newRefreshHash: token.Hash(refresh), refreshExpiresAt: now.Add(RefreshLifetime),
	})
	if err != nil {
		return nil, err
	}
	if outcome != refreshRotated {
		return nil, oauthError("invalid_grant", "Connect Aaru again.")
	}
	return tokens(access, refresh, scopes), nil
}

// Revoke is RFC 7009: revokes the connection the token belongs to; unknown tokens are ignored.
func (s *Service) Revoke(ctx context.Context, form map[string]string) error {
	if t := form["token"]; t != "" {
		return s.store.revoke(ctx, token.Hash(t), s.now())
	}
	return nil
}

func tokens(access, refresh string, scopes []auth.Scope) map[string]any {
	return map[string]any{
		"access_token":  access,
		"token_type":    "Bearer",
		"expires_in":    int(AccessLifetime.Seconds()),
		"refresh_token": refresh,
		"scope":         strings.Join(auth.SortedScopes(scopes), " "),
	}
}

// Challenge is base64url(SHA-256(verifier)), RFC 7636 §4.2.
func Challenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// KindForClientName is which agent a registered client is, by the name it gave, for Settings' label.
func KindForClientName(name string) auth.TokenKind {
	name = strings.ToLower(name)
	switch {
	case strings.Contains(name, "claude code"):
		return auth.KindClaudeCode
	case strings.Contains(name, "claude"):
		return auth.KindClaude
	}
	for _, kind := range []auth.TokenKind{auth.KindCodex, auth.KindGemini, auth.KindHermes} {
		if strings.Contains(name, string(kind)) {
			return kind
		}
	}
	return auth.KindOther
}

// parsedURL splits a URL as Foundation's URLComponents does where it matters
// here: the scheme as written (Go lowercases it), and whether a fragment exists at all.
type parsedURL struct {
	scheme      string
	u           *url.URL
	hasFragment bool
}

func parse(raw string) (parsedURL, bool) {
	scheme, _, ok := strings.Cut(raw, ":")
	if !ok {
		return parsedURL{}, false
	}
	u, err := url.Parse(raw)
	if err != nil {
		return parsedURL{}, false
	}
	return parsedURL{scheme: scheme, u: u, hasFragment: strings.Contains(raw, "#")}, true
}

// host is URLComponents.host: an IPv6 literal keeps its brackets.
func (p parsedURL) host() string {
	h := p.u.Hostname()
	if strings.Contains(h, ":") {
		return "[" + h + "]"
	}
	return h
}

func isLoopback(host string) bool {
	switch host {
	case "localhost", "127.0.0.1", "::1", "[::1]":
		return true
	}
	return false
}

// AcceptableRedirect: https anywhere, or http on the loopback interface (RFC 8252); never a fragment or userinfo.
func AcceptableRedirect(raw string) bool {
	p, ok := parse(raw)
	if !ok || p.host() == "" || p.hasFragment || p.u.User != nil {
		return false
	}
	return p.scheme == "https" || (p.scheme == "http" && isLoopback(p.host()))
}

// Registered is the registered URI a presented one matches: exactly, or for loopback on any port.
func Registered(presented string, uris []string) (string, bool) {
	for _, u := range uris {
		if u == presented {
			return presented, true
		}
	}
	asked, ok := parse(presented)
	if !ok || asked.scheme != "http" || !isLoopback(asked.host()) {
		return "", false
	}
	for _, u := range uris {
		known, ok := parse(u)
		if ok && known.scheme == asked.scheme && known.host() == asked.host() && known.u.User == nil && asked.u.User == nil &&
			known.u.EscapedPath() == asked.u.EscapedPath() && known.u.RawQuery == asked.u.RawQuery &&
			known.u.ForceQuery == asked.u.ForceQuery && known.hasFragment == asked.hasFragment && known.u.Fragment == asked.u.Fragment {
			return presented, true
		}
	}
	return "", false
}

// RedirectURL appends the parameters (sorted by name, nil ones left out) to base's
// query, encoded as Foundation's URLComponents.queryItems encodes them.
func RedirectURL(base string, parameters map[string]*string) string {
	names := make([]string, 0, len(parameters))
	for name, value := range parameters {
		if value != nil {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	head, fragment, hasFragment := strings.Cut(base, "#")
	out := head
	sep := "?"
	if strings.Contains(head, "?") {
		sep = "&"
		if strings.HasSuffix(head, "?") {
			sep = ""
		}
	}
	for _, name := range names {
		out += sep + queryItemEncode(name) + "=" + queryItemEncode(*parameters[name])
		sep = "&"
	}
	if hasFragment {
		out += "#" + fragment
	}
	return out
}

// queryItemEncode leaves what a URL query allows except `&` and `=`, as Foundation does.
func queryItemEncode(s string) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || strings.IndexByte("-._~!$'()*+,;:@/?", c) >= 0 {
			b.WriteByte(c)
			continue
		}
		fmt.Fprintf(&b, "%%%02X", c)
	}
	return b.String()
}

func prefixRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n])
}

func ptr(s string) *string { return &s }
