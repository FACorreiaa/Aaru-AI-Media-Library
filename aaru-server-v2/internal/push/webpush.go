package push

import (
	"aaru-go-api/internal/core"
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	mathrand "math/rand/v2"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// VAPIDConfig is swift-webpush's `VAPID.Configuration` as VAPID_CONFIG holds it (JSON):
//
//	{"primaryKey": "<base64 P-256 scalar>", "keys": [...], "deprecatedKeys": [...],
//	 "contactInformation": "mailto:…" | "https://…", "expirationDuration": 79200, "validityDuration": 72000}
//
// A key is the raw 32-byte private scalar in standard base64; its id is the base64url
// (unpadded) uncompressed public key, which is what a browser subscribed with.
type VAPIDConfig struct {
	PrimaryKey *vapidKey
	// Keys sign new subscriptions (with the primary); deprecated keys still sign for old ones.
	Keys           []*vapidKey
	DeprecatedKeys []*vapidKey
	// Contact is the JWT `sub`: a mailto: or http(s) URL.
	Contact    string
	Expiration time.Duration
	Validity   time.Duration
}

type vapidKey struct {
	private *ecdsa.PrivateKey
	id      string
}

func parseVAPIDKey(raw string) (*vapidKey, error) {
	data, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return nil, fmt.Errorf("vapid key: %w", err)
	}
	key, err := ecdsa.ParseRawPrivateKey(elliptic.P256(), data)
	if err != nil {
		return nil, fmt.Errorf("vapid key: %w", err)
	}
	pub, err := key.PublicKey.Bytes()
	if err != nil {
		return nil, fmt.Errorf("vapid key: %w", err)
	}
	return &vapidKey{private: key, id: base64.RawURLEncoding.EncodeToString(pub)}, nil
}

// ParseVAPIDConfig reads VAPID_CONFIG.
func ParseVAPIDConfig(data string) (*VAPIDConfig, error) {
	var raw struct {
		PrimaryKey         *string  `json:"primaryKey"`
		Keys               []string `json:"keys"`
		DeprecatedKeys     []string `json:"deprecatedKeys"`
		ContactInformation *string  `json:"contactInformation"`
		ExpirationDuration *int     `json:"expirationDuration"`
		ValidityDuration   *int     `json:"validityDuration"`
	}
	if err := json.Unmarshal([]byte(data), &raw); err != nil {
		return nil, fmt.Errorf("vapid config: %w", err)
	}
	if raw.ContactInformation == nil || raw.ExpirationDuration == nil || raw.ValidityDuration == nil {
		return nil, errors.New("vapid config: contactInformation, expirationDuration and validityDuration are required")
	}
	contact, err := url.Parse(*raw.ContactInformation)
	if err != nil {
		return nil, fmt.Errorf("vapid config: contactInformation: %w", err)
	}
	switch strings.ToLower(contact.Scheme) {
	case "mailto":
		if len(*raw.ContactInformation) <= len("mailto:") {
			return nil, errors.New("vapid config: a mailto contact has no email")
		}
	case "http", "https":
	default:
		return nil, errors.New("vapid config: contactInformation is neither mailto nor http(s)")
	}
	cfg := &VAPIDConfig{
		Contact:    *raw.ContactInformation,
		Expiration: time.Duration(*raw.ExpirationDuration) * time.Second,
		Validity:   time.Duration(*raw.ValidityDuration) * time.Second,
	}
	seen := map[string]bool{}
	if raw.PrimaryKey != nil {
		if cfg.PrimaryKey, err = parseVAPIDKey(*raw.PrimaryKey); err != nil {
			return nil, err
		}
		cfg.Keys = append(cfg.Keys, cfg.PrimaryKey)
		seen[cfg.PrimaryKey.id] = true
	}
	for _, k := range raw.Keys {
		key, err := parseVAPIDKey(k)
		if err != nil {
			return nil, err
		}
		if !seen[key.id] {
			cfg.Keys = append(cfg.Keys, key)
			seen[key.id] = true
		}
	}
	if len(cfg.Keys) == 0 {
		return nil, errors.New("vapid config: no keys")
	}
	for _, k := range raw.DeprecatedKeys {
		key, err := parseVAPIDKey(k)
		if err != nil {
			return nil, err
		}
		if !seen[key.id] {
			cfg.DeprecatedKeys = append(cfg.DeprecatedKeys, key)
			seen[key.id] = true
		}
	}
	return cfg, nil
}

// WebApp is where a tap lands when the browser opens the alert itself (declarative push).
const WebApp = "https://aaruapp.com"

// Web push constants from swift-webpush 0.4.2.
const (
	maxEncryptedPayload = 4096
	maxMessageSize      = maxEncryptedPayload - 103 // 3993: every message pads to this
	webPushTTL          = 30 * 24 * 60 * 60         // Expiration.recommendedMaximum, in seconds
)

// ErrNoVAPIDKey is a subscription made with a key this configuration does not hold.
var ErrNoVAPIDKey = errors.New("web push: no VAPID key matches this subscription")

// VAPIDSender is the real web push sender: RFC 8030 delivery, encrypted per RFC 8291
// (aes128gcm), signed with VAPID per RFC 8292, the way swift-webpush does it.
type VAPIDSender struct {
	cfg     *VAPIDConfig
	client  *http.Client
	lookup  map[string]*vapidKey
	nextKey string
	log     *slog.Logger
	now     func() time.Time
	// Retries are the waits before resending a 429, 500 or 503.
	Retries []time.Duration

	mu    sync.Mutex
	cache map[string]cachedAuth
}

type cachedAuth struct {
	header     string
	validUntil time.Time
}

// NewVAPIDSender builds a sender from VAPID_CONFIG. A nil client gets a default one.
func NewVAPIDSender(configJSON string, client *http.Client, log *slog.Logger) (*VAPIDSender, error) {
	cfg, err := ParseVAPIDConfig(configJSON)
	if err != nil {
		return nil, err
	}
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	if log == nil {
		log = slog.Default()
	}
	s := &VAPIDSender{
		cfg: cfg, client: client, lookup: map[string]*vapidKey{}, log: log, now: time.Now,
		Retries: []time.Duration{500 * time.Millisecond, 2 * time.Second, 10 * time.Second},
		cache:   map[string]cachedAuth{},
	}
	for _, k := range append(append([]*vapidKey{}, cfg.Keys...), cfg.DeprecatedKeys...) {
		s.lookup[k.id] = k
	}
	if cfg.PrimaryKey != nil {
		s.nextKey = cfg.PrimaryKey.id
	} else {
		s.nextKey = cfg.Keys[mathrand.IntN(len(cfg.Keys))].id //nolint:gosec // picks a key, not a secret
	}
	return s, nil
}

// PublicKey is the VAPID key id new browsers subscribe with.
func (s *VAPIDSender) PublicKey() string { return s.nextKey }

// alertData is what the service worker reads from an alert.
type alertData struct {
	Path string `json:"path"`
}

// Notification is swift-webpush's declarative `PushMessage.Notification` as JSON.
func Notification(m Message, now time.Time) ([]byte, error) {
	path := WebPath(m.Payload)
	type notification struct {
		Title       string    `json:"title"`
		Body        string    `json:"body"`
		Destination string    `json:"navigate"`
		Timestamp   int64     `json:"timestamp"`
		Data        alertData `json:"data"`
	}
	message := struct {
		WebPush      int          `json:"web_push"`
		Notification notification `json:"notification"`
	}{
		WebPush: 8030,
		Notification: notification{
			Title: m.Title, Body: m.Body, Destination: WebApp + path, Timestamp: now.UnixMilli(),
			// The service worker opens this path on its own origin, so the staging web app stays put.
			Data: alertData{Path: path},
		},
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(message); err != nil {
		return nil, fmt.Errorf("web push notification: %w", err)
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// Send encrypts and posts one alert. A 404 or 410, or a browser key that does not agree, is a
// dead subscription.
func (s *VAPIDSender) Send(ctx context.Context, m Message, sub WebSubscription) (Outcome, error) {
	endpoint, err := url.Parse(sub.Endpoint)
	if err != nil || endpoint.Scheme == "" || endpoint.Host == "" {
		return 0, errors.New("web push: the endpoint is not a URL")
	}
	uaPublic, err := decodeBase64URL(sub.P256dh)
	if err != nil {
		return 0, fmt.Errorf("web push: p256dh: %w", err)
	}
	uaKey, err := ecdh.P256().NewPublicKey(uaPublic)
	if err != nil {
		return 0, fmt.Errorf("web push: p256dh: %w", err)
	}
	authSecret, err := decodeBase64URL(sub.Auth)
	if err != nil {
		return 0, fmt.Errorf("web push: auth: %w", err)
	}
	signing, ok := s.lookup[sub.VAPIDKeyID]
	if !ok {
		return 0, ErrNoVAPIDKey
	}
	authorization, err := s.authorization(endpoint, signing)
	if err != nil {
		return 0, err
	}
	message, err := Notification(m, s.now())
	if err != nil {
		return 0, err
	}
	content, err := Encrypt(message, uaKey, authSecret)
	if err != nil {
		return 0, err
	}
	return s.post(ctx, sub.Endpoint, authorization, content, s.Retries)
}

func (s *VAPIDSender) post(ctx context.Context, endpoint, authorization string, content []byte, retries []time.Duration) (Outcome, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(content))
	if err != nil {
		return 0, fmt.Errorf("web push request: %w", err)
	}
	req.Header.Set("Authorization", authorization)
	req.Header.Set("Content-Encoding", "aes128gcm")
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("TTL", strconv.Itoa(webPushTTL))
	req.Header.Set("Urgency", "high")
	resp, err := s.client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("web push: %w", err)
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	_ = resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusCreated:
		return Sent, nil
	case http.StatusNotFound, http.StatusGone:
		return DeadToken, nil
	case http.StatusRequestEntityTooLarge:
		s.log.Error("The encrypted payload was too large and was rejected by the push service.")
		return 0, fmt.Errorf("web push: message too large")
	case http.StatusTooManyRequests, http.StatusInternalServerError, http.StatusServiceUnavailable:
		if len(retries) == 0 {
			return 0, fmt.Errorf("web push: push service answered %d", resp.StatusCode)
		}
		select {
		case <-ctx.Done():
			return 0, fmt.Errorf("web push: %w", ctx.Err())
		case <-time.After(retries[0]):
		}
		return s.post(ctx, endpoint, authorization, content, retries[1:])
	default:
		return 0, fmt.Errorf("web push: push service answered %d", resp.StatusCode)
	}
}

// authorization is the `vapid t=<JWT>, k=<key id>` header for the endpoint's origin, cached
// until the configuration's validity duration passes.
func (s *VAPIDSender) authorization(endpoint *url.URL, key *vapidKey) (string, error) {
	origin := Origin(endpoint)
	cacheKey := key.id + "|" + origin
	now := s.now()
	s.mu.Lock()
	defer s.mu.Unlock()
	if cached, ok := s.cache[cacheKey]; ok && now.Before(cached.validUntil) {
		return cached.header, nil
	}
	expiration := now.Add(min(s.cfg.Expiration, 24*time.Hour))
	renewal := now.Add(s.cfg.Validity)
	if renewal.After(expiration) {
		renewal = expiration
	}
	// Sorted keys, slashes unescaped, as swift-webpush encodes its token.
	var claims bytes.Buffer
	enc := json.NewEncoder(&claims)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(struct {
		Aud string `json:"aud"`
		Exp int64  `json:"exp"`
		Sub string `json:"sub"`
	}{origin, expiration.Unix(), s.cfg.Contact}); err != nil {
		return "", fmt.Errorf("vapid token: %w", err)
	}
	jwt, err := signES256(key.private, []byte(`{"typ":"JWT","alg":"ES256"}`), bytes.TrimSuffix(claims.Bytes(), []byte("\n")))
	if err != nil {
		return "", err
	}
	header := "vapid t=" + jwt + ", k=" + key.id
	s.cache[cacheKey] = cachedAuth{header: header, validUntil: renewal}
	return header, nil
}

// Origin is a URL's web origin (scheme, host, and a non-default port), "null" without one.
func Origin(u *url.URL) string {
	host := u.Hostname()
	if host == "" {
		return "null"
	}
	port := u.Port()
	switch strings.ToLower(u.Scheme) {
	case "http":
		if port == "" || port == "80" {
			return "http://" + host
		}
		return "http://" + host + ":" + port
	case "https":
		if port == "" || port == "443" {
			return "https://" + host
		}
		return "https://" + host + ":" + port
	default:
		return "null"
	}
}

// Encrypt is RFC 8291's aes128gcm content coding for one record, padded to 3993 bytes as
// swift-webpush pads every message, so its size does not leak.
func Encrypt(message []byte, uaPublic *ecdh.PublicKey, authSecret []byte) ([]byte, error) {
	asPrivate, err := ecdh.P256().GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	return encrypt(message, uaPublic, authSecret, asPrivate, salt)
}

func encrypt(message []byte, uaPublic *ecdh.PublicKey, authSecret []byte, asPrivate *ecdh.PrivateKey, salt []byte) ([]byte, error) {
	shared, err := asPrivate.ECDH(uaPublic)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	asPublic := asPrivate.PublicKey().Bytes()
	keyInfo := append(append([]byte("WebPush: info\x00"), uaPublic.Bytes()...), asPublic...)
	ikm, err := hkdf.Key(sha256.New, shared, authSecret, string(keyInfo), 32)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	cek, err := hkdf.Key(sha256.New, ikm, salt, "Content-Encoding: aes128gcm\x00", 16)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	nonce, err := hkdf.Key(sha256.New, ikm, salt, "Content-Encoding: nonce\x00", 12)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	padded := max(len(message), maxMessageSize)
	plaintext := make([]byte, 0, padded+1)
	plaintext = append(plaintext, message...)
	plaintext = append(plaintext, 0x02)
	plaintext = append(plaintext, make([]byte, padded-len(message))...)
	block, err := aes.NewCipher(cek)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("web push: %w", err)
	}
	header := make([]byte, 0, 16+4+1+len(asPublic))
	header = append(header, salt...)
	header = binary.BigEndian.AppendUint32(header, uint32(len(plaintext)+16)) //nolint:gosec // at most a few KB
	header = append(header, byte(len(asPublic)))                              //nolint:gosec // an uncompressed P-256 key is 65 bytes
	header = append(header, asPublic...)
	return gcm.Seal(header, nonce, plaintext, nil), nil
}

func decodeBase64URL(s string) ([]byte, error) {
	s = strings.TrimRight(s, "=")
	return base64.RawURLEncoding.DecodeString(s)
}

// WebPath is the web app's page for an alert's payload.
func WebPath(payload map[string]string) string {
	if group, ok := payload["groupId"]; ok {
		if channel, ok := payload["channelId"]; ok {
			return "/app/groups/" + group + "/" + channel
		}
	}
	if v, ok := payload["planId"]; ok {
		return "/app/plans/" + v
	}
	if v, ok := payload["importId"]; ok {
		return "/app/imports/" + v
	}
	if v, ok := payload["libraryItemId"]; ok {
		return "/app/title/" + v
	}
	if _, ok := payload["groupInvite"]; ok {
		return "/app/groups"
	}
	return "/app"
}

// Which endpoints a browser may hand us. The server POSTs to whatever is saved, so only the
// browsers' own push services are accepted (no request forgery against anything else).
var (
	pushHosts    = []string{"fcm.googleapis.com", "updates.push.services.mozilla.com", "web.push.apple.com"}
	pushSuffixes = []string{".push.apple.com", ".push.services.mozilla.com", ".notify.windows.com"}
)

// EndpointAllowed says whether a subscription endpoint is a known browser push service over https.
func EndpointAllowed(endpoint string) bool {
	if core.Length(endpoint) > 2048 {
		return false
	}
	u, err := url.Parse(endpoint)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" {
		return false
	}
	host := strings.ToLower(u.Hostname())
	if host == "" {
		return false
	}
	for _, h := range pushHosts {
		if host == h {
			return true
		}
	}
	for _, suffix := range pushSuffixes {
		if strings.HasSuffix(host, suffix) {
			return true
		}
	}
	return false
}
