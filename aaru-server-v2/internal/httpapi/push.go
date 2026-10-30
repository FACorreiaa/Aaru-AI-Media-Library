package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/push"
	"context"
)

// PushHandlers.swift: devices, notification switches, web push.

func (s *Server) RegisterDevice(ctx context.Context, req api.RegisterDeviceRequestObject) (api.RegisterDeviceResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil || !req.Body.Environment.Valid() {
		return nil, apperr.BadRequest()
	}
	env := push.Sandbox
	if req.Body.Environment == api.DeviceRegistrationEnvironmentProduction {
		env = push.Production
	}
	if err := s.pushService().RegisterDevice(ctx, userID, req.Body.Token, env, req.Body.BundleId); err != nil {
		return nil, err
	}
	return api.RegisterDevice204Response{}, nil
}

func (s *Server) UnregisterDevice(ctx context.Context, req api.UnregisterDeviceRequestObject) (api.UnregisterDeviceResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.pushService().UnregisterDevice(ctx, userID, req.Token); err != nil {
		return nil, err
	}
	return api.UnregisterDevice204Response{}, nil
}

func (s *Server) GetNotificationSettings(ctx context.Context, _ api.GetNotificationSettingsRequestObject) (api.GetNotificationSettingsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	settings, err := s.pushService().NotificationSettings(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetNotificationSettings200JSONResponse(notificationSettingsDTO(settings)), nil
}

func (s *Server) UpdateNotificationSettings(ctx context.Context, req api.UpdateNotificationSettingsRequestObject) (api.UpdateNotificationSettingsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	settings, err := s.pushService().UpdateNotificationSettings(ctx, userID, req.Body.Airing, req.Body.GroupMentions, req.Body.GroupInvites)
	if err != nil {
		return nil, err
	}
	return api.UpdateNotificationSettings200JSONResponse(notificationSettingsDTO(settings)), nil
}

func notificationSettingsDTO(s push.Settings) api.NotificationSettings {
	return api.NotificationSettings{Airing: s.Airing, GroupMentions: s.GroupMentions, GroupInvites: s.GroupInvites}
}

func (s *Server) GetWebPushKey(ctx context.Context, _ api.GetWebPushKeyRequestObject) (api.GetWebPushKeyResponseObject, error) {
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	key, err := s.pushService().WebPushKey()
	if err != nil {
		return nil, err
	}
	return api.GetWebPushKey200JSONResponse{PublicKey: key}, nil
}

func (s *Server) SaveWebPushSubscription(ctx context.Context, req api.SaveWebPushSubscriptionRequestObject) (api.SaveWebPushSubscriptionResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.pushService().SaveWebPush(ctx, userID, req.Body.Endpoint, req.Body.Keys.P256dh, req.Body.Keys.Auth); err != nil {
		return nil, err
	}
	return api.SaveWebPushSubscription204Response{}, nil
}

func (s *Server) DeleteWebPushSubscription(ctx context.Context, req api.DeleteWebPushSubscriptionRequestObject) (api.DeleteWebPushSubscriptionResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.pushService().DeleteWebPush(ctx, userID, req.Params.Endpoint); err != nil {
		return nil, err
	}
	return api.DeleteWebPushSubscription204Response{}, nil
}

// pushService is the push rules over this server's queries and web push sender.
func (s *Server) pushService() *push.Service {
	return &push.Service{Q: s.q, Web: s.WebPush}
}
