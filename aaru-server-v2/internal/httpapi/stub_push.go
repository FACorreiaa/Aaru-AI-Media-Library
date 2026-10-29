// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) RegisterDevice(context.Context, api.RegisterDeviceRequestObject) (api.RegisterDeviceResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UnregisterDevice(context.Context, api.UnregisterDeviceRequestObject) (api.UnregisterDeviceResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetNotificationSettings(context.Context, api.GetNotificationSettingsRequestObject) (api.GetNotificationSettingsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UpdateNotificationSettings(context.Context, api.UpdateNotificationSettingsRequestObject) (api.UpdateNotificationSettingsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetWebPushKey(context.Context, api.GetWebPushKeyRequestObject) (api.GetWebPushKeyResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteWebPushSubscription(context.Context, api.DeleteWebPushSubscriptionRequestObject) (api.DeleteWebPushSubscriptionResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SaveWebPushSubscription(context.Context, api.SaveWebPushSubscriptionRequestObject) (api.SaveWebPushSubscriptionResponseObject, error) {
	return nil, errNotImplemented
}
