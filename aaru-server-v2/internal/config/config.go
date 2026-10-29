// Package config loads the server's settings once at boot. Names match the Swift
// server's, so the deployment's environment does not change: a dotted key
// (`postgres.host`) is read from its environment variable (`POSTGRES_HOST`) or
// from a `--postgres-host` flag, and `.env` in the working directory is read
// first if present. A missing required key fails boot and names the variable.
package config

import (
	"bufio"
	"crypto/aes"
	"encoding/base64"
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
	Host               string
	Port               int
	User               string
	Password           string
	Database           string
	PoolSize           int
	PoolTimeoutSeconds int
}

// LoadPostgres reads POSTGRES_*.
func LoadPostgres(r *Reader) (Postgres, error) {
	var err error
	p := Postgres{
		Host:               r.String("postgres.host", "127.0.0.1"),
		Port:               r.Int("postgres.port", 5432),
		PoolSize:           max(1, r.Int("postgres.pool.size", 10)),
		PoolTimeoutSeconds: max(1, r.Int("postgres.pool.timeout", 10)),
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

// App is everything serving needs.
type App struct {
	Postgres           Postgres
	HTTP               HTTP
	TMDBAPIKey         string
	AppleAudiences     []string
	GoogleAudiences    []string
	Email              *Email
	ProviderUserAgent  string
	Trakt              *OAuthProvider
	MAL                *OAuthProvider
	Push               *Push
	VAPIDConfigJSON    *string
	PublicBaseURL      *url.URL
	WebBaseURL         *url.URL
	OAuthCookieDomain  *string
	RealtimeOrigins    []string
	Anthropic          *Anthropic
	TicketmasterAPIKey *string
	TheSportsDBAPIKey  *string
	LastFMAPIKey       *string
	MetricsSecret      string
	WebClientSecret    string
	MetricsPort        int
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
		Postgres:           pg,
		HTTP:               HTTP{Host: r.String("http.host", "127.0.0.1"), Port: r.Int("http.port", 8080)},
		TMDBAPIKey:         tmdb,
		AppleAudiences:     list(r.String("apple.audiences", DefaultAppleAudiences)),
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
		LogLevel:           r.String("log.level", "info"),
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
	if cfg.Trakt, err = loadOAuthProvider(r, "trakt", "TRAKT", "https://api.aaruapp.com/v1/imports/trakt/callback"); err != nil {
		return nil, err
	}
	if cfg.MAL, err = loadOAuthProvider(r, "mal", "MAL", "https://api.aaruapp.com/v1/connections/mal/callback"); err != nil {
		return nil, err
	}
	if cfg.Push, err = loadPush(r); err != nil {
		return nil, err
	}
	if cfg.Anthropic, err = loadAnthropic(r); err != nil {
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
		return nil, nil //nolint:nilnil // unset turns the feature off
	}
	link, err := url.Parse(r.String("magic.link.base.url", "https://aaruapp.com/auth/verify"))
	if err != nil {
		return nil, MissingError{Env: "MAGIC_LINK_BASE_URL", Key: "magic.link.base.url"}
	}
	return &Email{ResendAPIKey: key, From: r.String("email.from", "Aaru <signin@aaruapp.com>"), LinkBaseURL: link}, nil
}

func loadOAuthProvider(r *Reader, prefix, env, defaultRedirect string) (*OAuthProvider, error) {
	clientID, ok := r.Lookup(prefix + ".client.id")
	if !ok || clientID == "" {
		return nil, nil //nolint:nilnil // unset turns the provider off
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
		return nil, nil //nolint:nilnil // unset turns push off
	}
	keyID, err := r.required("apns.key.id", "APNS_KEY_ID")
	if err != nil {
		return nil, err
	}
	return &Push{KeyID: keyID, TeamID: r.String("apns.team.id", "84X9WYBF36"), PrivateKeyPEM: key}, nil
}

func loadAnthropic(r *Reader) (*Anthropic, error) {
	key, ok := r.Lookup("anthropic.api.key")
	if !ok || key == "" {
		return nil, nil //nolint:nilnil // unset leaves @aaru off
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
