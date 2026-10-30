package push

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// APNSSettings are the token-based key (`.p8`) that signs for both apps and both gateways:
// APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY.
type APNSSettings struct {
	KeyID  string
	TeamID string
	// PrivateKeyPEM is the `.p8` contents. Sealed in `aaru-env`, never on disk in the image.
	PrivateKeyPEM string
}

// The APNs gateways (APNSwift's APNSEnvironment).
const (
	ProductionGateway  = "https://api.push.apple.com:443"
	DevelopmentGateway = "https://api.development.push.apple.com:443"
)

// deadReasons are the reasons Apple gives for a token that is gone for good.
var deadReasons = map[string]bool{"BadDeviceToken": true, "Unregistered": true, "DeviceTokenNotForTopic": true}

// tokenLifetime is how long a provider token is reused. Apple refuses one older than an hour
// and throttles one refreshed more often than every 20 minutes.
const tokenLifetime = 50 * time.Minute

// APNSSender is the real sender over HTTP/2: one gateway per environment, so Xcode builds
// (sandbox) and TestFlight or App Store builds (production) reach the same API.
// It sends alerts (Sender) and Live Activity pushes (LiveActivitySender).
type APNSSender struct {
	keyID  string
	teamID string
	key    *ecdsa.PrivateKey
	client *http.Client
	// Gateways by environment; tests point both at a stub.
	Sandbox    string
	Production string
	now        func() time.Time

	mu       sync.Mutex
	token    string
	issuedAt time.Time
}

// NewAPNSSender parses the `.p8` key. A nil client gets an HTTP/2 client.
func NewAPNSSender(settings APNSSettings, client *http.Client) (*APNSSender, error) {
	key, err := parseP8(settings.PrivateKeyPEM)
	if err != nil {
		return nil, err
	}
	if client == nil {
		client = &http.Client{
			Transport: &http.Transport{ForceAttemptHTTP2: true, TLSHandshakeTimeout: 10 * time.Second, IdleConnTimeout: 90 * time.Second},
			Timeout:   30 * time.Second,
		}
	}
	return &APNSSender{
		keyID: settings.KeyID, teamID: settings.TeamID, key: key, client: client,
		Sandbox: DevelopmentGateway, Production: ProductionGateway, now: time.Now,
	}, nil
}

func parseP8(pemText string) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(strings.TrimSpace(pemText)))
	if block == nil {
		return nil, errors.New("apns: the private key is not PEM")
	}
	var key any
	var err error
	if block.Type == "EC PRIVATE KEY" {
		key, err = x509.ParseECPrivateKey(block.Bytes)
	} else {
		key, err = x509.ParsePKCS8PrivateKey(block.Bytes)
	}
	if err != nil {
		return nil, fmt.Errorf("apns: private key: %w", err)
	}
	ec, ok := key.(*ecdsa.PrivateKey)
	if !ok || ec.Curve != elliptic.P256() {
		return nil, errors.New("apns: the private key is not a P-256 key")
	}
	return ec, nil
}

// alertPayload is APNSwift's APNSAlertNotification: the payload's keys beside `aps`, and the
// sound inside the alert, as APNSwift encodes `APNSAlertNotificationContent(sound:)`.
func alertPayload(m Message) ([]byte, error) {
	body := make(map[string]any, len(m.Payload)+1)
	for k, v := range m.Payload {
		body[k] = v
	}
	body["aps"] = map[string]any{
		"alert": map[string]string{"title": m.Title, "body": m.Body, "sound": "default"},
	}
	return json.Marshal(body)
}

// Send sends one alert (push type `alert`, priority 10, no expiration).
func (s *APNSSender) Send(ctx context.Context, m Message, d Device) (Outcome, error) {
	body, err := alertPayload(m)
	if err != nil {
		return 0, fmt.Errorf("apns payload: %w", err)
	}
	return s.post(ctx, request{
		environment: d.Environment, token: d.Token, pushType: "alert", priority: 10, topic: d.Topic, body: body,
	}, false)
}

type request struct {
	environment Environment
	token       string
	pushType    string
	priority    int
	topic       string
	body        []byte
}

// Error is an APNs refusal: the HTTP status and Apple's reason.
type Error struct {
	Status int
	Reason string
}

func (e *Error) Error() string { return "apns: " + strconv.Itoa(e.Status) + " " + e.Reason }

func (s *APNSSender) post(ctx context.Context, r request, expiredIsDead bool) (Outcome, error) {
	gateway := s.Sandbox
	if r.environment == Production {
		gateway = s.Production
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, gateway+"/3/device/"+r.token, bytes.NewReader(r.body))
	if err != nil {
		return 0, fmt.Errorf("apns request: %w", err)
	}
	token, err := s.providerToken()
	if err != nil {
		return 0, err
	}
	req.Header.Set("content-type", "application/json")
	req.Header.Set("apns-push-type", r.pushType)
	req.Header.Set("apns-priority", strconv.Itoa(r.priority))
	req.Header.Set("apns-topic", r.topic)
	req.Header.Set("authorization", "bearer "+token)
	resp, err := s.client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("apns: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
	if resp.StatusCode == http.StatusOK {
		return Sent, nil
	}
	var refusal struct {
		Reason string `json:"reason"`
	}
	_ = json.Unmarshal(data, &refusal)
	if deadReasons[refusal.Reason] || (expiredIsDead && refusal.Reason == "ExpiredToken") {
		return DeadToken, nil
	}
	return 0, &Error{Status: resp.StatusCode, Reason: refusal.Reason}
}

// providerToken is the ES256 JWT Apple authenticates the key with, reused for tokenLifetime.
func (s *APNSSender) providerToken() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if s.token != "" && now.Sub(s.issuedAt) < tokenLifetime {
		return s.token, nil
	}
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": s.keyID, "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{"iss": s.teamID, "iat": now.Unix()})
	token, err := signES256(s.key, header, claims)
	if err != nil {
		return "", err
	}
	s.token, s.issuedAt = token, now
	return token, nil
}

// signES256 is a compact JWS: base64url(header).base64url(claims).base64url(r||s).
func signES256(key *ecdsa.PrivateKey, header, claims []byte) (string, error) {
	enc := base64.RawURLEncoding
	message := enc.EncodeToString(header) + "." + enc.EncodeToString(claims)
	sig, err := es256(key, []byte(message))
	if err != nil {
		return "", err
	}
	return message + "." + enc.EncodeToString(sig), nil
}

// es256 signs SHA-256(message) and returns the 64-byte r||s form JWS uses.
func es256(key *ecdsa.PrivateKey, message []byte) ([]byte, error) {
	digest := sha256.Sum256(message)
	r, sv, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		return nil, fmt.Errorf("es256: %w", err)
	}
	out := make([]byte, 64)
	r.FillBytes(out[:32])
	sv.FillBytes(out[32:])
	return out, nil
}
