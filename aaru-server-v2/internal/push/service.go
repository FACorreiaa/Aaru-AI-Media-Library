package push

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Settings is what a user asked to hear about. Everything is off until they turn it on.
type Settings struct {
	// Airing: a new episode of a show they are watching aired.
	Airing bool
	// GroupMentions: someone tagged them in a group they have not muted.
	GroupMentions bool
	// GroupInvites: a friend invited them into a group.
	GroupInvites bool
}

// Service holds the rules behind the device, notification and web push routes (PushHandlers.swift).
type Service struct {
	Q *sqlc.Queries
	// Web is nil when VAPID_CONFIG is unset: browsers cannot subscribe.
	Web WebSender
}

var errWebPushOff = apperr.Unavailable("push_unavailable", "Browser notifications are not set up yet.")

// RegisterDevice saves an APNs token for the user, replacing whoever held it.
func (s *Service) RegisterDevice(ctx context.Context, userID uuid.UUID, token string, env Environment, bundleID string) error {
	token = strings.ToLower(strings.Trim(token, " \t"))
	if len(token) < 32 || len(token) > 200 || !isHex(token) {
		return &apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed",
			Message: "That is not an APNs device token.", Details: map[string]string{"token": "Hex, as the device gave it."},
		}
	}
	if !AllowedTopics[bundleID] {
		return &apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed",
			Message: "Unknown app.", Details: map[string]string{"bundleId": "Not an Aaru app."},
		}
	}
	if env != Production {
		env = Sandbox
	}
	if err := s.Q.RegisterPushDevice(ctx, sqlc.RegisterPushDeviceParams{
		Token: token, UserID: userID, Environment: string(env), Topic: bundleID,
	}); err != nil {
		return fmt.Errorf("register device: %w", err)
	}
	return nil
}

// UnregisterDevice forgets the user's own token.
func (s *Service) UnregisterDevice(ctx context.Context, userID uuid.UUID, token string) error {
	if err := s.Q.UnregisterPushDevice(ctx, sqlc.UnregisterPushDeviceParams{Token: strings.ToLower(token), UserID: userID}); err != nil {
		return fmt.Errorf("unregister device: %w", err)
	}
	return nil
}

// Devices are the user's registered Apple devices.
func (s *Service) Devices(ctx context.Context, userID uuid.UUID) ([]Device, error) {
	rows, err := s.Q.PushDevices(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("push devices: %w", err)
	}
	out := make([]Device, 0, len(rows))
	for _, r := range rows {
		env := Environment(r.Environment)
		if env != Sandbox && env != Production {
			continue
		}
		out = append(out, Device{Token: r.Token, Environment: env, Topic: r.Topic})
	}
	return out, nil
}

// NotificationSettings reads the user's switches; all off when never saved.
func (s *Service) NotificationSettings(ctx context.Context, userID uuid.UUID) (Settings, error) {
	row, err := s.Q.NotificationSettings(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return Settings{}, nil
	}
	if err != nil {
		return Settings{}, fmt.Errorf("notification settings: %w", err)
	}
	return Settings{Airing: row.Airing, GroupMentions: row.GroupMentions, GroupInvites: row.GroupInvites}, nil
}

// SaveNotificationSettings writes the switches. Turning airing on starts its clock at now, so
// episodes that aired before are never announced.
func (s *Service) SaveNotificationSettings(ctx context.Context, userID uuid.UUID, settings Settings, now time.Time) error {
	var since *time.Time
	if settings.Airing {
		since = &now
	}
	if err := s.Q.SaveNotificationSettings(ctx, sqlc.SaveNotificationSettingsParams{
		UserID: userID, Airing: settings.Airing, AiringSince: since,
		GroupMentions: settings.GroupMentions, GroupInvites: settings.GroupInvites,
	}); err != nil {
		return fmt.Errorf("save notification settings: %w", err)
	}
	return nil
}

// UpdateNotificationSettings changes only the switches that are set and returns the result.
func (s *Service) UpdateNotificationSettings(ctx context.Context, userID uuid.UUID, airing, mentions, invites *bool) (Settings, error) {
	settings, err := s.NotificationSettings(ctx, userID)
	if err != nil {
		return Settings{}, err
	}
	if airing != nil {
		settings.Airing = *airing
	}
	if mentions != nil {
		settings.GroupMentions = *mentions
	}
	if invites != nil {
		settings.GroupInvites = *invites
	}
	if err := s.SaveNotificationSettings(ctx, userID, settings, time.Now()); err != nil {
		return Settings{}, err
	}
	return s.NotificationSettings(ctx, userID)
}

// WebPushKey is the VAPID public key browsers subscribe with; 503 when web push is off.
func (s *Service) WebPushKey() (string, error) {
	if s.Web == nil {
		return "", errWebPushOff
	}
	return s.Web.PublicKey(), nil
}

// SaveWebPush stores a browser subscription made with the current VAPID key.
func (s *Service) SaveWebPush(ctx context.Context, userID uuid.UUID, endpoint, p256dh, auth string) error {
	if s.Web == nil {
		return errWebPushOff
	}
	if !EndpointAllowed(endpoint) {
		return &apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed",
			Message: "That is not a browser push service.", Details: map[string]string{"endpoint": "Not a known push service."},
		}
	}
	for _, key := range []string{p256dh, auth} {
		if n := len([]rune(key)); n < 16 || n > 200 || !isBase64URL(key) {
			return &apperr.Error{
				Status: http.StatusUnprocessableEntity, Code: "validation_failed",
				Message: "Those subscription keys are not valid.",
				Details: map[string]string{"keys": "base64url, as the browser gave them."},
			}
		}
	}
	if err := s.Q.SaveWebPushSubscription(ctx, sqlc.SaveWebPushSubscriptionParams{
		Endpoint: endpoint, UserID: userID, P256dh: p256dh, Auth: auth, VapidKeyID: s.Web.PublicKey(),
	}); err != nil {
		return fmt.Errorf("save web push: %w", err)
	}
	return nil
}

// DeleteWebPush forgets the user's own browser subscription.
func (s *Service) DeleteWebPush(ctx context.Context, userID uuid.UUID, endpoint string) error {
	if err := s.Q.DeleteWebPushSubscription(ctx, sqlc.DeleteWebPushSubscriptionParams{Endpoint: endpoint, UserID: userID}); err != nil {
		return fmt.Errorf("delete web push: %w", err)
	}
	return nil
}

// WebSubscriptions are the user's browsers, most recently saved first.
func (s *Service) WebSubscriptions(ctx context.Context, userID uuid.UUID) ([]WebSubscription, error) {
	rows, err := s.Q.WebPushSubscriptions(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("web push subscriptions: %w", err)
	}
	out := make([]WebSubscription, 0, len(rows))
	for _, r := range rows {
		out = append(out, WebSubscription{Endpoint: r.Endpoint, P256dh: r.P256dh, Auth: r.Auth, VAPIDKeyID: r.VapidKeyID})
	}
	return out, nil
}

func isHex(s string) bool {
	for _, c := range s {
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
			return false
		}
	}
	return true
}

func isBase64URL(s string) bool {
	for _, c := range s {
		if (c < '0' || c > '9') && (c < 'a' || c > 'z') && (c < 'A' || c > 'Z') && c != '-' && c != '_' && c != '=' {
			return false
		}
	}
	return true
}
