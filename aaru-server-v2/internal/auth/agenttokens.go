package auth

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/token"
	"context"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Scope is what an agent token may do (OUT-001). A token never has more than a signed-in session.
type Scope string

// The scopes agent_tokens allows.
const (
	ScopeLibraryRead   Scope = "library:read"
	ScopeLibraryWrite  Scope = "library:write"
	ScopeScrobbleWrite Scope = "scrobble:write"
	// ScopeImportsWrite queues an import for the user to review (`plan_import`). Never an apply.
	ScopeImportsWrite Scope = "imports:write"
)

func knownScope(s string) bool {
	switch Scope(s) {
	case ScopeLibraryRead, ScopeLibraryWrite, ScopeScrobbleWrite, ScopeImportsWrite:
		return true
	}
	return false
}

// TokenKind is which outside caller a token is for.
type TokenKind string

// The kinds agent_tokens allows. The MCP kinds differ only in the setup Settings shows.
const (
	KindStremio    TokenKind = "stremio"
	KindClaudeCode TokenKind = "claude_code"
	KindCodex      TokenKind = "codex"
	KindHermes     TokenKind = "hermes"
	KindGemini     TokenKind = "gemini"
	KindOther      TokenKind = "other"
	// KindClaude is Claude (claude.ai, Desktop, mobile) through its custom connector, over OAuth.
	KindClaude TokenKind = "claude"
	// KindBrowser is Aaru's browser extension: scrobbles plays on streaming sites, nothing else (SCR-007).
	KindBrowser TokenKind = "browser"
	// KindMusic is a music scrobbler speaking ListenBrainz's protocol (MUS-005): sends listens, nothing else.
	KindMusic TokenKind = "music"
)

// ParseTokenKind is the kind for a stored or requested value.
func ParseTokenKind(s string) (TokenKind, bool) {
	switch k := TokenKind(s); k {
	case KindStremio, KindClaudeCode, KindCodex, KindHermes, KindGemini, KindOther, KindClaude, KindBrowser, KindMusic:
		return k, true
	}
	return "", false
}

// TokenGroup is which surface a token opens. A token for one never authenticates on another.
type TokenGroup string

// The surfaces.
const (
	GroupStremio  TokenGroup = "stremio"
	GroupMCP      TokenGroup = "mcp"
	GroupScrobble TokenGroup = "scrobble"
	GroupMusic    TokenGroup = "music"
)

// ParseTokenGroup is the group for `?for=`.
func ParseTokenGroup(s string) (TokenGroup, bool) {
	switch g := TokenGroup(s); g {
	case GroupStremio, GroupMCP, GroupScrobble, GroupMusic:
		return g, true
	}
	return "", false
}

// Group is the surface a kind opens.
func (k TokenKind) Group() TokenGroup {
	switch k {
	case KindStremio:
		return GroupStremio
	case KindBrowser:
		return GroupScrobble
	case KindMusic:
		return GroupMusic
	default:
		return GroupMCP
	}
}

// Label is the default token name, and the client's name in Settings.
func (k TokenKind) Label() string {
	switch k {
	case KindStremio:
		return "Stremio"
	case KindClaudeCode:
		return "Claude Code"
	case KindCodex:
		return "Codex"
	case KindHermes:
		return "Hermes"
	case KindGemini:
		return "Gemini CLI"
	case KindClaude:
		return "Claude"
	case KindBrowser:
		return "Browser extension"
	case KindMusic:
		return "Music scrobbler"
	default:
		return "MCP client"
	}
}

// AgentToken is one agent token as its owner sees it. The secret is never stored, only its SHA-256.
type AgentToken struct {
	ID         uuid.UUID
	Name       string
	Kind       TokenKind
	Scopes     []Scope // sorted
	CreatedAt  time.Time
	LastUsedAt *time.Time
}

// Has reports whether the token carries scope.
func (t AgentToken) Has(scope Scope) bool {
	for _, s := range t.Scopes {
		if s == scope {
			return true
		}
	}
	return false
}

// SortedScopes is the scopes as stored: raw values, sorted.
func SortedScopes(scopes []Scope) []string {
	out := make([]string, 0, len(scopes))
	seen := map[Scope]bool{}
	for _, s := range scopes {
		if !seen[s] {
			seen[s] = true
			out = append(out, string(s))
		}
	}
	sort.Strings(out)
	return out
}

func parseScopes(raw []string) []Scope {
	known := []Scope{}
	for _, s := range raw {
		if knownScope(s) {
			known = append(known, Scope(s))
		}
	}
	sorted := SortedScopes(known)
	out := make([]Scope, len(sorted))
	for i, s := range sorted {
		out[i] = Scope(s)
	}
	return out
}

// AgentCaller is a request made with an agent token: whose library, through which token, allowed to do what.
type AgentCaller struct {
	UserID uuid.UUID
	Token  AgentToken
}

// Has reports whether the caller's token carries scope.
func (c AgentCaller) Has(scope Scope) bool { return c.Token.Has(scope) }

// StremioLinks is the addon's manifest over HTTPS, and the same link for the Stremio app and Stremio Web.
type StremioLinks struct {
	ManifestURL   string
	InstallURL    string
	WebInstallURL string
}

// MintedAgentToken is a freshly minted token: the only time its secret exists outside the caller's hands.
type MintedAgentToken struct {
	Token  AgentToken
	Secret string
	// Stremio is set only for a Stremio token.
	Stremio *StremioLinks
}

// Secret prefixes per surface.
const (
	StremioPrefix  = "aaru_st_"
	MCPPrefix      = "aaru_mcp_"
	ScrobblePrefix = "aaru_scr_"
	ListenPrefix   = "aaru_lb_"
	// OAuthPrefix is an access token the OAuth front door issued (one hour). Also an MCP credential.
	OAuthPrefix = "aaru_oat_"
)

const (
	// touchInterval: `last_used_at` is written at most this often, so a busy addon does not write per request.
	touchInterval = time.Hour
	// RequestsPerMinute per token. Stremio asks for a few catalogs per screen.
	RequestsPerMinute = 120
)

// PrefixFor is the secret prefix of a surface.
func PrefixFor(group TokenGroup) string {
	switch group {
	case GroupStremio:
		return StremioPrefix
	case GroupMCP:
		return MCPPrefix
	case GroupScrobble:
		return ScrobblePrefix
	default:
		return ListenPrefix
	}
}

// AgentTokenService is OUT-001: per-user tokens for outside callers — the Stremio
// addon, MCP clients (OUT-004), the browser extension (SCR-007) and music
// scrobblers (MUS-005). The secret is a per-surface prefix + 32 random bytes;
// Postgres keeps only its SHA-256.
type AgentTokenService struct {
	q *sqlc.Queries
	// PublicBaseURL is where this API is reachable from outside, for install links.
	PublicBaseURL *url.URL
	Now           func() time.Time
	limiter       *ratelimit.FixedWindow
}

// NewAgentTokenService builds the service.
func NewAgentTokenService(pool *pgxpool.Pool, publicBaseURL *url.URL) *AgentTokenService {
	return &AgentTokenService{q: sqlc.New(pool), PublicBaseURL: publicBaseURL, Now: time.Now, limiter: ratelimit.New(RequestsPerMinute, time.Minute)}
}

func (s *AgentTokenService) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Create mints a token. Claude connects over OAuth and is refused here.
func (s *AgentTokenService) Create(ctx context.Context, userID uuid.UUID, kind TokenKind, name *string, allowLibraryWrites, allowImports bool) (MintedAgentToken, error) {
	if kind == KindClaude {
		return MintedAgentToken{}, (&apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed",
			Message: "Claude connects through its connector: add Aaru in Claude and approve it there.",
		}).WithDetails(map[string]string{"kind": "Claude connects over OAuth."})
	}
	trimmed := ""
	if name != nil {
		trimmed = strings.TrimSpace(*name)
	}
	if core.Length(trimmed) > 80 {
		return MintedAgentToken{}, (&apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed", Message: "Names are at most 80 characters.",
		}).WithDetails(map[string]string{"name": "At most 80 characters."})
	}
	// An MCP client reads and, if allowed, writes the library; only a player scrobbles. The
	// browser extension and music scrobblers only scrobble: they never read the library.
	group := kind.Group()
	var scopes []Scope
	switch group {
	case GroupStremio:
		scopes = []Scope{ScopeLibraryRead, ScopeScrobbleWrite}
	case GroupMCP:
		scopes = []Scope{ScopeLibraryRead}
	default:
		scopes = []Scope{ScopeScrobbleWrite}
	}
	if allowLibraryWrites && (group == GroupStremio || group == GroupMCP) {
		scopes = append(scopes, ScopeLibraryWrite)
	}
	if allowImports && group == GroupMCP {
		scopes = append(scopes, ScopeImportsWrite)
	}
	if trimmed == "" {
		trimmed = kind.Label()
	}
	t := AgentToken{ID: uuid.New(), Name: trimmed, Kind: kind, Scopes: parseScopes(SortedScopes(scopes)), CreatedAt: s.now()}
	secret := PrefixFor(group) + token.Generate()
	if err := s.q.CreateAgentToken(ctx, sqlc.CreateAgentTokenParams{
		ID: t.ID, UserID: userID, Name: t.Name, Kind: string(kind), TokenHash: token.Hash(secret),
		Scopes: SortedScopes(t.Scopes), CreatedAt: t.CreatedAt,
	}); err != nil {
		return MintedAgentToken{}, fmt.Errorf("create agent token: %w", err)
	}
	minted := MintedAgentToken{Token: t, Secret: secret}
	if group == GroupStremio {
		links := s.stremioLinks(secret)
		minted.Stremio = &links
	}
	return minted, nil
}

// Tokens is the live tokens for one surface, newest first. Old Apple builds
// decode only Stremio kinds, so the list never mixes surfaces.
func (s *AgentTokenService) Tokens(ctx context.Context, userID uuid.UUID, group TokenGroup) ([]AgentToken, error) {
	rows, err := s.q.ListAgentTokens(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("list agent tokens: %w", err)
	}
	out := []AgentToken{}
	for _, r := range rows {
		kind, ok := ParseTokenKind(r.Kind)
		if !ok || kind.Group() != group {
			continue
		}
		out = append(out, AgentToken{ID: r.ID, Name: r.Name, Kind: kind, Scopes: parseScopes(r.Scopes), CreatedAt: r.CreatedAt, LastUsedAt: r.LastUsedAt})
	}
	return out, nil
}

// Revoke revokes the user's live token, expiring its waiting plans; 404 when there is none.
func (s *AgentTokenService) Revoke(ctx context.Context, id, userID uuid.UUID) error {
	if _, err := s.q.RevokeAgentToken(ctx, sqlc.RevokeAgentTokenParams{Now: s.now(), ID: id, UserID: userID}); err != nil {
		if db.IsNoRows(err) {
			return apperr.NotFound()
		}
		return fmt.Errorf("revoke agent token: %w", err)
	}
	return nil
}

// Authenticate is the live token for a presented secret on one surface, or
// false. MCP also takes OAuth access tokens (`aaru_oat_`). Records use at most hourly.
//
// This is what the MCP, scrobble, Stremio and ListenBrainz transports call with
// the presented secret; a false answer is a 401 (or 404 for a Stremio link).
func (s *AgentTokenService) Authenticate(ctx context.Context, secret string, group TokenGroup) (AgentCaller, bool, error) {
	prefixes := []string{PrefixFor(group)}
	if group == GroupMCP {
		prefixes = []string{MCPPrefix, OAuthPrefix}
	}
	hasPrefix := false
	for _, p := range prefixes {
		if strings.HasPrefix(secret, p) {
			hasPrefix = true
		}
	}
	if !hasPrefix || core.Length(secret) >= 200 {
		return AgentCaller{}, false, nil
	}
	now := s.now()
	row, err := s.q.AgentTokenByHash(ctx, sqlc.AgentTokenByHashParams{TokenHash: token.Hash(secret), Now: now})
	if err != nil {
		if db.IsNoRows(err) {
			return AgentCaller{}, false, nil
		}
		return AgentCaller{}, false, fmt.Errorf("agent token: %w", err)
	}
	kind, ok := ParseTokenKind(row.Kind)
	if !ok || kind.Group() != group {
		return AgentCaller{}, false, nil
	}
	t := AgentToken{ID: row.ID, Name: row.Name, Kind: kind, Scopes: parseScopes(row.Scopes), CreatedAt: row.CreatedAt, LastUsedAt: row.LastUsedAt}
	if t.LastUsedAt == nil || now.Sub(*t.LastUsedAt) >= touchInterval {
		// Best effort, as the Swift `try?`: a failed touch never fails the request.
		_ = s.q.TouchAgentToken(ctx, sqlc.TouchAgentTokenParams{At: now, ID: t.ID})
	}
	return AgentCaller{UserID: row.UserID, Token: t}, true, nil
}

// Allow reports whether this token is inside its request budget (120 a minute).
func (s *AgentTokenService) Allow(caller AgentCaller) bool {
	return s.limiter.Allow(strings.ToUpper(caller.Token.ID.String()), s.now())
}

// AppendPath is Foundation's `appendingPathComponent` for each component, on an absolute URL string.
func AppendPath(base *url.URL, components ...string) string {
	out := strings.TrimSuffix(base.String(), "/")
	for _, c := range components {
		out += "/" + c
	}
	return out
}

// MCPEndpoint is `<PUBLIC_BASE_URL>/v1/mcp`, the MCP resource.
func MCPEndpoint(publicBaseURL *url.URL) string {
	return AppendPath(publicBaseURL, "v1", "mcp")
}

func (s *AgentTokenService) stremioLinks(secret string) StremioLinks {
	manifest := AppendPath(s.PublicBaseURL, "stremio", secret, "manifest.json")
	install := manifest
	if _, rest, ok := strings.Cut(manifest, "://"); ok {
		install = "stremio://" + rest
	}
	// Stremio Web reads the addon from its hash route.
	return StremioLinks{
		ManifestURL:   manifest,
		InstallURL:    install,
		WebInstallURL: "https://web.stremio.com/#/addons?addon=" + percentEncodeUnreserved(manifest),
	}
}

// percentEncodeUnreserved escapes everything but ASCII letters, digits and `-._~`.
func percentEncodeUnreserved(s string) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' || c == '~' {
			b.WriteByte(c)
			continue
		}
		fmt.Fprintf(&b, "%%%02X", c)
	}
	return b.String()
}
