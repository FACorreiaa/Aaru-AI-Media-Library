// Package config loads the server's settings once at boot. Names match the Swift
// server's, so the deployment's environment does not change: a dotted key
// (`postgres.host`) is read from its environment variable (`POSTGRES_HOST`) or
// from a `--postgres-host` flag, and `.env` in the working directory is read
// first if present. A missing required key fails boot and names the variable.
package config

import (
	"bufio"
	"crypto/aes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// MissingError names a required key that is not set.
type MissingError struct {
	Env string
	Key string
}

func (e MissingError) Error() string {
	return fmt.Sprintf("Missing required configuration %s (%s). Set it in the environment or in .env.", e.Env, e.Key)
}

// Reader resolves dotted keys from flags, then the environment, then `.env`.
type Reader struct {
	flags  map[string]string
	env    func(string) (string, bool)
	dotenv map[string]string
}

// NewReader parses `--key value`, `--key=value` and bare `--flag` arguments.
func NewReader(args []string) *Reader {
	r := &Reader{flags: map[string]string{}, env: os.LookupEnv, dotenv: readDotenv(".env")}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "--") {
			continue
		}
		name := strings.TrimPrefix(arg, "--")
		if k, v, ok := strings.Cut(name, "="); ok {
			r.flags[flagKey(k)] = v
			continue
		}
		if i+1 < len(args) && !strings.HasPrefix(args[i+1], "--") {
			r.flags[flagKey(name)] = args[i+1]
			i++
			continue
		}
		r.flags[flagKey(name)] = "true"
	}
	return r
}

// NewReaderFrom is for tests: values keyed by dotted key.
func NewReaderFrom(values map[string]string) *Reader {
	env := map[string]string{}
	for k, v := range values {
		env[envName(k)] = v
	}
	return &Reader{flags: map[string]string{}, env: func(k string) (string, bool) { v, ok := env[k]; return v, ok }}
}

func flagKey(flag string) string { return strings.ReplaceAll(flag, "-", ".") }

func envName(key string) string {
	return strings.ToUpper(strings.NewReplacer(".", "_", "-", "_").Replace(key))
}

func readDotenv(path string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(path) //nolint:gosec // a fixed local file
	if err != nil {
		return out
	}
	defer func() { _ = f.Close() }()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		out[strings.TrimSpace(k)] = strings.Trim(strings.TrimSpace(v), `"'`)
	}
	return out
}

// Lookup returns a key's value and whether it is set at all.
func (r *Reader) Lookup(key string) (string, bool) {
	if v, ok := r.flags[key]; ok {
		return v, true
	}
	name := envName(key)
	if v, ok := r.env(name); ok {
		return v, true
	}
	if v, ok := r.dotenv[name]; ok {
		return v, true
	}
	return "", false
}

// String returns the value or def when unset.
func (r *Reader) String(key, def string) string {
	if v, ok := r.Lookup(key); ok {
		return v
	}
	return def
}

// Optional returns nil when unset or blank.
func (r *Reader) Optional(key string) *string {
	v, ok := r.Lookup(key)
	if !ok || strings.TrimSpace(v) == "" {
		return nil
	}
	return &v
}

// Int returns the value or def when unset or not a number.
func (r *Reader) Int(key string, def int) int {
	v, ok := r.Lookup(key)
	if !ok {
		return def
	}
	n, err := strconv.Atoi(strings.TrimSpace(v))
	if err != nil {
		return def
	}
	return n
}

// Bool reads true/false/1/0/yes/no.
func (r *Reader) Bool(key string) bool {
	v, _ := r.Lookup(key)
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "true", "1", "yes":
		return true
	}
	return false
}

func (r *Reader) required(key, env string) (string, error) {
	v, ok := r.Lookup(key)
	if !ok || v == "" {
		return "", MissingError{Env: env, Key: key}
	}
	return v, nil
}

// Postgres settings, needed to serve and to migrate.
type Postgres struct {
	Host     string
	Port     int
	User     string
	Password string
	Database string
	PoolSize int
	// PoolTimeoutSeconds is how long a query waits for a free connection (Swift's meaning),
	// and also bounds dialing a new one (POSTGRES_POOL_TIMEOUT, default 10).
	PoolTimeoutSeconds int
	// StatementTimeoutSeconds is Postgres' statement_timeout for the API's connections
	// (POSTGRES_STATEMENT_TIMEOUT, default 30; 0 leaves the server's default).
	StatementTimeoutSeconds int
	// IdleInTransactionTimeoutSeconds is idle_in_transaction_session_timeout
	// (POSTGRES_IDLE_TRANSACTION_TIMEOUT, default 60; 0 leaves the server's default).
	IdleInTransactionTimeoutSeconds int
}

// WithoutSessionTimeouts is s for the one-shot modes (`--db-migrate`, `--anime-mappings`): a
// migration or a bulk load runs as long as it needs, never cut by the API's statement timeouts.
func (s Postgres) WithoutSessionTimeouts() Postgres {
	s.StatementTimeoutSeconds, s.IdleInTransactionTimeoutSeconds = 0, 0
	return s
}

// LoadPostgres reads POSTGRES_*.
func LoadPostgres(r *Reader) (Postgres, error) {
	var err error
	p := Postgres{
		Host:                            r.String("postgres.host", "127.0.0.1"),
		Port:                            r.Int("postgres.port", 5432),
		PoolSize:                        max(1, r.Int("postgres.pool.size", 10)),
		PoolTimeoutSeconds:              max(1, r.Int("postgres.pool.timeout", 10)),
		StatementTimeoutSeconds:         max(0, r.Int("postgres.statement.timeout", 30)),
		IdleInTransactionTimeoutSeconds: max(0, r.Int("postgres.idle.transaction.timeout", 60)),
	}
	if p.User, err = r.required("postgres.user", "POSTGRES_USER"); err != nil {
		return p, err
	}
	if p.Password, err = r.required("postgres.password", "POSTGRES_PASSWORD"); err != nil {
		return p, err
	}
	if p.Database, err = r.required("postgres.database", "POSTGRES_DATABASE"); err != nil {
		return p, err
	}
	return p, nil
}

// HTTP is where the API listens (`--http-host`, `--http-port`).
type HTTP struct {
	Host string
	Port int
	// RequestTimeoutSeconds bounds each request but the long-lived ones (the WebSocket,
	// uploads, the export, MCP) (HTTP_REQUEST_TIMEOUT, default 30; 0 turns it off).
	RequestTimeoutSeconds int
	// TrustedProxyHops is how many proxies in front of the API append to `X-Forwarded-For`
	// (TRUSTED_PROXY_HOPS, default 1: Traefik). 0 ignores the header.
	TrustedProxyHops int
}

// Workers is how many jobs each queue runs at once in this process.
type Workers struct {
	Imports      int
	AgentReplies int
}

// Email is set when RESEND_API_KEY is: email sign-in answers 503 without it.
type Email struct {
	ResendAPIKey string
	From         string
	LinkBaseURL  *url.URL
}

// Review is App Review's way in: one address whose sign-in code is always Code and
// is never emailed, because a reviewer cannot read an inbox. Set by REVIEW_EMAIL and
// REVIEW_CODE together; unset, no address is special.
type Review struct {
	Email string
	Code  string
}

// OAuthProvider is Trakt's or MyAnimeList's settings (connect answers 503 without them).
type OAuthProvider struct {
	ClientID       string
	ClientSecret   *string
	RedirectURI    *url.URL
	ReturnPrefixes []string
	// TokenKey is the 32-byte AES-GCM key provider tokens are sealed with.
	TokenKey []byte
}

// Push is APNs; nil turns push off.
type Push struct {
	KeyID         string
	TeamID        string
	PrivateKeyPEM string
}

// AppleSignIn is the Sign in with Apple key (AUTH-006); nil leaves token revocation off:
// sign-in stores nothing more and deleting an account calls nobody. With it, a sign-in that
// carries an authorization code keeps Apple's refresh token, sealed, and account deletion
// revokes it with Apple (App Store rule 5.1.1(v)). It is not the APNs key unless that key
// also has Sign in with Apple switched on.
type AppleSignIn struct {
	KeyID  string
	TeamID string
	// PrivateKey signs the client secret Apple's token and revoke endpoints ask for (ES256).
	PrivateKey *ecdsa.PrivateKey
	// ClientIDs are the bundle ids and Services IDs the key may sign for: the primary App ID
	// the key was made for and the ids grouped with it. A sign-in for any other is not exchanged.
	ClientIDs []string
	// TokenKey is the 32-byte AES-GCM key the refresh tokens are sealed with.
	TokenKey []byte
}

// Anthropic is the agent's model; nil leaves `@aaru` off.
type Anthropic struct {
	APIKey             string
	Model              string
	Effort             *string
	BaseURL            *url.URL
	WorkspaceID        *string
	PriceInputPerMTok  float64
	PriceOutputPerMTok float64
}

// Transcription is the speech-to-text service, in the OpenAI wire format; nil leaves
// voice input off. Model is required with the URL.
type Transcription struct {
	BaseURL *url.URL
	Model   string
}

// Sentry is set when SENTRY_DSN is: server errors are reported, not just logged.
type Sentry struct {
	DSN         string
	Environment string
	Release     *string
}

// PostHog is set when POSTHOG_PROJECT_TOKEN is.
type PostHog struct {
	ProjectToken string
	Host         *url.URL
}

// Pprof is Go's profiler on the internal port (PPROF_ENABLED, on unless "false";
// PPROF_BLOCK_RATE and PPROF_MUTEX_FRACTION sample block and mutex contention, off at 0).
type Pprof struct {
	Enabled       bool
	BlockRate     int
	MutexFraction int
}

// App is everything serving needs.
type App struct {
	Postgres       Postgres
	HTTP           HTTP
	TMDBAPIKey     string
	AppleAudiences []string
	// AcceptSandbox (BILLING_ACCEPT_SANDBOX, off unless true): whether App Store Sandbox
	// transactions, which TestFlight purchases are, grant Plus. Production ones always do.
	AcceptSandbox      bool
	GoogleAudiences    []string
	Email              *Email
	Review             *Review
	ProviderUserAgent  string
	Trakt              *OAuthProvider
	MAL                *OAuthProvider
	Push               *Push
	AppleSignIn        *AppleSignIn
	VAPIDConfigJSON    *string
	PublicBaseURL      *url.URL
	WebBaseURL         *url.URL
	OAuthCookieDomain  *string
	RealtimeOrigins    []string
	Anthropic          *Anthropic
	Transcription      *Transcription
	TicketmasterAPIKey *string
	TheSportsDBAPIKey  *string
	LastFMAPIKey       *string
	MetricsSecret      string
	WebClientSecret    string
	MetricsPort        int
	Pprof              Pprof
	Sentry             *Sentry
	PostHog            *PostHog
	Workers            Workers
	LogLevel           string
}

// Defaults shared with the Swift server.
const (
	DefaultProviderUserAgent = "Aaru/0.1 (media library; contact: signin@aaruapp.com)"
	DefaultAppleAudiences    = "com.fernandocorreia.aaru,com.fernandocorreia.aaru.beta"
	DefaultRealtimeOrigins   = "https://aaruapp.com,https://www.aaruapp.com,https://beta.aaruapp.com"
	defaultReturnPrefixes    = "aaru://,https://aaruapp.com/,https://beta.aaruapp.com/"
)

// Load reads every setting serving needs.
func Load(r *Reader) (*App, error) {
	pg, err := LoadPostgres(r)
	if err != nil {
		return nil, err
	}
	tmdb, err := r.required("tmdb.api.key", "TMDB_API_KEY")
	if err != nil {
		return nil, err
	}
	cfg := &App{
		Postgres: pg,
		HTTP: HTTP{
			Host: r.String("http.host", "127.0.0.1"), Port: r.Int("http.port", 8080),
			RequestTimeoutSeconds: max(0, r.Int("http.request.timeout", 30)),
			TrustedProxyHops:      max(0, r.Int("trusted.proxy.hops", 1)),
		},
		TMDBAPIKey:         tmdb,
		AppleAudiences:     list(r.String("apple.audiences", DefaultAppleAudiences)),
		AcceptSandbox:      r.Bool("billing.accept_sandbox"),
		GoogleAudiences:    list(r.String("google.client.ids", "")),
		ProviderUserAgent:  r.String("open.library.user.agent", DefaultProviderUserAgent),
		VAPIDConfigJSON:    r.Optional("vapid.config"),
		OAuthCookieDomain:  r.Optional("oauth.cookie.domain"),
		RealtimeOrigins:    list(r.String("realtime.origins", DefaultRealtimeOrigins)),
		TicketmasterAPIKey: r.Optional("ticketmaster.api.key"),
		TheSportsDBAPIKey:  r.Optional("thesportsdb.api.key"),
		LastFMAPIKey:       r.Optional("lastfm.api.key"),
		MetricsSecret:      r.String("metrics.secret", ""),
		WebClientSecret:    r.String("web.client.secret", ""),
		MetricsPort:        r.Int("metrics.port", 9090),
		Pprof: Pprof{
			Enabled:       r.String("pprof.enabled", "true") != "false",
			BlockRate:     max(0, r.Int("pprof.block.rate", 0)),
			MutexFraction: max(0, r.Int("pprof.mutex.fraction", 0)),
		},
		LogLevel: r.String("log.level", "info"),
		Workers: Workers{
			Imports:      min(8, max(1, r.Int("imports.workers", 1))),
			AgentReplies: min(8, max(1, r.Int("agent.reply.workers", 1))),
		},
	}
	if _, set := r.Lookup("oauth.cookie.domain"); !set {
		d := "aaruapp.com"
		cfg.OAuthCookieDomain = &d
	}
	if cfg.PublicBaseURL, err = httpURL(r.String("public.base.url", "https://api.aaruapp.com"), "PUBLIC_BASE_URL", "public.base.url"); err != nil {
		return nil, err
	}
	if cfg.WebBaseURL, err = url.Parse(r.String("web.base.url", "https://aaruapp.com")); err != nil {
		cfg.WebBaseURL, _ = url.Parse("https://aaruapp.com")
	}
	if cfg.Email, err = loadEmail(r); err != nil {
		return nil, err
	}
	if cfg.Review, err = loadReview(r); err != nil {
		return nil, err
	}
	if cfg.Trakt, err = loadOAuthProvider(r, "trakt", "TRAKT", "https://api.aaruapp.com/v1/imports/trakt/callback"); err != nil {
		return nil, err
	}
	if cfg.MAL, err = loadOAuthProvider(r, "mal", "MAL", "https://api.aaruapp.com/v1/connections/mal/callback"); err != nil {
		return nil, err
	}
	if cfg.Push, err = loadPush(r); err != nil {
		return nil, err
	}
	if cfg.AppleSignIn, err = loadAppleSignIn(r, cfg.AppleAudiences); err != nil {
		return nil, err
	}
	if cfg.Anthropic, err = loadAnthropic(r); err != nil {
		return nil, err
	}
	if cfg.Transcription, err = loadTranscription(r); err != nil {
		return nil, err
	}
	if dsn := r.Optional("sentry.dsn"); dsn != nil {
		cfg.Sentry = &Sentry{DSN: *dsn, Environment: r.String("sentry.environment", "production"), Release: r.Optional("aaru.release")}
	}
	if token := r.Optional("posthog.project.token"); token != nil {
		host, err := httpURL(r.String("posthog.host", "https://eu.i.posthog.com"), "POSTHOG_HOST", "posthog.host")
		if err != nil {
			return nil, err
		}
		cfg.PostHog = &PostHog{ProjectToken: *token, Host: host}
	}
	return cfg, nil
}

func list(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func httpURL(raw, env, key string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") {
		return nil, MissingError{Env: env, Key: key}
	}
	return u, nil
}

func loadEmail(r *Reader) (*Email, error) {
	key, ok := r.Lookup("resend.api.key")
	if !ok || key == "" {
		return nil, nil // unset turns the feature off
	}
	link, err := url.Parse(r.String("magic.link.base.url", "https://aaruapp.com/auth/verify"))
	if err != nil {
		return nil, MissingError{Env: "MAGIC_LINK_BASE_URL", Key: "magic.link.base.url"}
	}
	return &Email{ResendAPIKey: key, From: r.String("email.from", "Aaru <signin@aaruapp.com>"), LinkBaseURL: link}, nil
}

// loadReview reads the review account. Half of the pair, or a code that is not six digits, is
// refused at boot: a review account that silently does not work costs a rejected submission.
func loadReview(r *Reader) (*Review, error) {
	email := strings.ToLower(strings.TrimSpace(r.String("review.email", "")))
	code := strings.TrimSpace(r.String("review.code", ""))
	if email == "" && code == "" {
		return nil, nil // unset turns the feature off
	}
	if !strings.Contains(email, "@") {
		return nil, MissingError{Env: "REVIEW_EMAIL", Key: "review.email"}
	}
	if len(code) != 6 || strings.Trim(code, "0123456789") != "" {
		return nil, MissingError{Env: "REVIEW_CODE", Key: "review.code"}
	}
	return &Review{Email: email, Code: code}, nil
}

func loadOAuthProvider(r *Reader, prefix, env, defaultRedirect string) (*OAuthProvider, error) {
	clientID, ok := r.Lookup(prefix + ".client.id")
	if !ok || clientID == "" {
		return nil, nil // unset turns the provider off
	}
	redirect, err := url.Parse(r.String(prefix+".redirect.uri", defaultRedirect))
	if err != nil {
		return nil, MissingError{Env: env + "_REDIRECT_URI", Key: prefix + ".redirect.uri"}
	}
	rawKey, err := r.required(prefix+".token.key", env+"_TOKEN_KEY")
	if err != nil {
		return nil, err
	}
	key, err := TokenKey(rawKey)
	if err != nil {
		return nil, MissingError{Env: env + "_TOKEN_KEY (32 bytes, base64)", Key: prefix + ".token.key"}
	}
	p := &OAuthProvider{
		ClientID:       clientID,
		RedirectURI:    redirect,
		ReturnPrefixes: list(r.String(prefix+".return.prefixes", defaultReturnPrefixes)),
		TokenKey:       key,
	}
	if prefix == "mal" {
		p.ClientSecret = r.Optional("mal.client.secret")
	}
	return p, nil
}

// TokenKey decodes a base64 32-byte AES-256 key, as TokenCipher in the Swift server did.
func TokenKey(b64 string) ([]byte, error) {
	key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil {
		return nil, fmt.Errorf("token key is not base64: %w", err)
	}
	if len(key) != 32 {
		return nil, errors.New("token key must be 32 bytes")
	}
	if _, err := aes.NewCipher(key); err != nil {
		return nil, fmt.Errorf("token key: %w", err)
	}
	return key, nil
}

func loadPush(r *Reader) (*Push, error) {
	key, ok := r.Lookup("apns.private.key")
	if !ok || key == "" {
		return nil, nil // unset turns push off
	}
	keyID, err := r.required("apns.key.id", "APNS_KEY_ID")
	if err != nil {
		return nil, err
	}
	return &Push{KeyID: keyID, TeamID: r.String("apns.team.id", defaultAppleTeamID), PrivateKeyPEM: key}, nil
}

// defaultAppleTeamID is the team the APNs key defaults to as well.
const defaultAppleTeamID = "84X9WYBF36"

// loadAppleSignIn reads the Sign in with Apple key. The private key, its id and the sealing key
// come together or not at all: a part without the rest, or a key that does not parse, is refused
// at boot, because revocation that silently does nothing costs a rejected submission.
func loadAppleSignIn(r *Reader, audiences []string) (*AppleSignIn, error) {
	pemText := strings.TrimSpace(r.String("apple.signin.private.key", ""))
	keyID := strings.TrimSpace(r.String("apple.signin.key.id", ""))
	rawTokenKey := strings.TrimSpace(r.String("apple.signin.token.key", ""))
	if pemText == "" && keyID == "" && rawTokenKey == "" {
		return nil, nil // unset turns the feature off
	}
	if keyID == "" {
		return nil, MissingError{Env: "APPLE_SIGNIN_KEY_ID", Key: "apple.signin.key.id"}
	}
	key, err := p256PrivateKey(pemText)
	if err != nil {
		return nil, MissingError{Env: "APPLE_SIGNIN_PRIVATE_KEY (a P-256 .p8)", Key: "apple.signin.private.key"}
	}
	tokenKey, err := TokenKey(rawTokenKey)
	if err != nil {
		return nil, MissingError{Env: "APPLE_SIGNIN_TOKEN_KEY (32 bytes, base64)", Key: "apple.signin.token.key"}
	}
	clientIDs := list(r.String("apple.signin.client.ids", ""))
	if len(clientIDs) == 0 {
		clientIDs = audiences
	}
	return &AppleSignIn{
		KeyID:      keyID,
		TeamID:     r.String("apple.signin.team.id", r.String("apns.team.id", defaultAppleTeamID)),
		PrivateKey: key,
		ClientIDs:  clientIDs,
		TokenKey:   tokenKey,
	}, nil
}

// p256PrivateKey parses an Apple .p8 (PKCS#8, or SEC 1 "EC PRIVATE KEY").
func p256PrivateKey(pemText string) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemText))
	if block == nil {
		return nil, errors.New("the private key is not PEM")
	}
	var key any
	var err error
	if block.Type == "EC PRIVATE KEY" {
		key, err = x509.ParseECPrivateKey(block.Bytes)
	} else {
		key, err = x509.ParsePKCS8PrivateKey(block.Bytes)
	}
	if err != nil {
		return nil, fmt.Errorf("private key: %w", err)
	}
	ec, ok := key.(*ecdsa.PrivateKey)
	if !ok || ec.Curve != elliptic.P256() {
		return nil, errors.New("the private key is not a P-256 key")
	}
	return ec, nil
}

func loadTranscription(r *Reader) (*Transcription, error) {
	raw := r.Optional("transcription.base.url")
	if raw == nil {
		return nil, nil // unset leaves voice input off
	}
	base, err := httpURL(*raw, "TRANSCRIPTION_BASE_URL", "transcription.base.url")
	if err != nil {
		return nil, err
	}
	model := r.Optional("transcription.model")
	if model == nil {
		return nil, MissingError{Env: "TRANSCRIPTION_MODEL", Key: "transcription.model"}
	}
	return &Transcription{BaseURL: base, Model: strings.TrimSpace(*model)}, nil
}

func loadAnthropic(r *Reader) (*Anthropic, error) {
	key, ok := r.Lookup("anthropic.api.key")
	if !ok || key == "" {
		return nil, nil // unset leaves @aaru off
	}
	base, err := httpURL(r.String("anthropic.base.url", "https://api.anthropic.com"), "ANTHROPIC_BASE_URL", "anthropic.base.url")
	if err != nil {
		return nil, err
	}
	price := func(k string, def float64) float64 {
		f, err := strconv.ParseFloat(r.String(k, ""), 64)
		if err != nil {
			return def
		}
		return f
	}
	a := &Anthropic{
		APIKey:             key,
		Model:              r.String("anthropic.model", "claude-haiku-5-5"),
		BaseURL:            base,
		PriceInputPerMTok:  price("anthropic.price.input", 0.10),
		PriceOutputPerMTok: price("anthropic.price.output", 0.50),
	}
	if effort := r.String("anthropic.effort", "low"); effort != "" {
		a.Effort = &effort
	}
	if ws := r.String("anthropic.workspace.id", ""); ws != "" {
		a.WorkspaceID = &ws
	}
	return a, nil
}
