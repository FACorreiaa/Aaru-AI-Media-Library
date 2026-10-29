// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListChannelItems(context.Context, api.ListChannelItemsRequestObject) (api.ListChannelItemsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) AddChannelItem(context.Context, api.AddChannelItemRequestObject) (api.AddChannelItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RemoveChannelItem(context.Context, api.RemoveChannelItemRequestObject) (api.RemoveChannelItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetWatchParty(context.Context, api.GetWatchPartyRequestObject) (api.GetWatchPartyResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) OpenWatchParty(context.Context, api.OpenWatchPartyRequestObject) (api.OpenWatchPartyResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) EndWatchParty(context.Context, api.EndWatchPartyRequestObject) (api.EndWatchPartyResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SetWatchPartyReady(context.Context, api.SetWatchPartyReadyRequestObject) (api.SetWatchPartyReadyResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) StartWatchParty(context.Context, api.StartWatchPartyRequestObject) (api.StartWatchPartyResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) MarkWatchPartyWatched(context.Context, api.MarkWatchPartyWatchedRequestObject) (api.MarkWatchPartyWatchedResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetChannelProgress(context.Context, api.GetChannelProgressRequestObject) (api.GetChannelProgressResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UpdateMyMembership(context.Context, api.UpdateMyMembershipRequestObject) (api.UpdateMyMembershipResponseObject, error) {
	return nil, errNotImplemented
}
