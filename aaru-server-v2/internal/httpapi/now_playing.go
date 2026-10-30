package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/scrobble"
	"context"
	"net/http"
	"strings"
	"time"
)

// NowPlayingHandlers.swift (SCR-008, SCR-009).

func (s *Server) GetNowPlaying(ctx context.Context, _ api.GetNowPlayingRequestObject) (api.GetNowPlayingResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	playing, err := s.Scrobble.NowPlaying(ctx, user)
	if err != nil {
		return nil, err
	}
	entries, err := s.Scrobble.PlayingNow(ctx, user)
	if err != nil {
		return nil, err
	}
	out := api.GetNowPlaying200JSONResponse{Items: make([]api.NowPlayingItem, len(entries))}
	if playing != nil {
		v := nowPlayingDTO(*playing)
		out.NowPlaying = &v
	}
	for i, e := range entries {
		out.Items[i] = nowPlayingItemDTO(e)
	}
	return out, nil
}

func liveActivityInvalid(field, hint string) *apperr.Error {
	return apperr.New(http.StatusUnprocessableEntity, "validation_failed", "That Live Activity token cannot be registered.").
		WithDetails(map[string]string{field: hint})
}

func isHex(s string) bool {
	for _, r := range s {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') && (r < 'A' || r > 'F') {
			return false
		}
	}
	return true
}

func (s *Server) RegisterLiveActivityToken(ctx context.Context, req api.RegisterLiveActivityTokenRequestObject) (api.RegisterLiveActivityTokenResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	body := *req.Body
	// `.whitespaces`: spaces and tabs, not newlines.
	token := strings.ToLower(trimSpaces(body.Token))
	if n := len([]rune(token)); n < 32 || n > 400 || !isHex(token) {
		return nil, liveActivityInvalid("token", "Hex, as ActivityKit gave it.")
	}
	if !push.AllowedTopics[body.BundleId] {
		return nil, liveActivityInvalid("bundleId", "Not an Aaru app.")
	}
	// `watchEventId` is ignored since SCR-009: one activity shows everything that plays.
	kind := push.LiveActivityTokenStart
	if body.Kind == "update" {
		kind = push.LiveActivityTokenUpdate
	}
	environment := push.Sandbox
	if body.Environment == "production" {
		environment = push.Production
	}
	registration := push.LiveActivityToken{Token: token, Kind: kind, Environment: environment, Topic: body.BundleId}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Scrobble.Store.RegisterLiveActivity(ctx, registration, user, time.Now()); err != nil {
		return nil, err
	}
	if kind == push.LiveActivityTokenUpdate && s.Scrobble.Notifier != nil {
		s.Scrobble.Notifier.CaughtUp(ctx, registration, user, time.Now())
	}
	return api.RegisterLiveActivityToken204Response{}, nil
}

func episodeRef(k *core.EpisodeKey) *api.EpisodeRef {
	if k == nil {
		return nil
	}
	return &api.EpisodeRef{Season: k.Season, Number: k.Episode}
}

func nowPlayingDTO(p scrobble.NowPlaying) api.NowPlaying {
	s := p.Session
	state := api.NowPlayingStatePlaying
	if s.State == scrobble.Paused {
		state = api.NowPlayingStatePaused
	}
	return api.NowPlaying{
		WatchEventId: apiid.From(s.ID), LibraryItemId: apiid.PtrOrNil(s.LibraryItemID), Title: TitleSummaryDTO(p.Title),
		Episode: episodeRef(s.Episode), EpisodeName: s.EpisodeName, Source: api.NowPlayingSource(s.Source),
		State: state, PositionMs: s.PositionMs, DurationMs: s.KnownDurationMs(), UpdatedAt: apitime.From(s.UpdatedAt),
	}
}

func nowPlayingItemDTO(e scrobble.Entry) api.NowPlayingItem {
	item := e.ActivityItem()
	if p := e.Play; p != nil {
		kind, source := api.NowPlayingItemKindTrack, api.NowPlayingItemSourceListenbrainz
		position := p.PositionMs
		if p.Kind == scrobble.PlayVideo {
			kind = api.NowPlayingItemKindVideo
		} else {
			// A track's scrobbler says only when it began.
			position = max(0, p.UpdatedAt.Sub(p.StartedAt).Milliseconds())
		}
		if p.Source == scrobble.PlayYouTube {
			source = api.NowPlayingItemSourceYoutube
		}
		state := api.NowPlayingItemStatePlaying
		if p.State == scrobble.Paused {
			state = api.NowPlayingItemStatePaused
		}
		return api.NowPlayingItem{
			Id: item.ID, Kind: kind, Name: p.Title, Subtitle: p.Subtitle, Service: p.Service, Source: source,
			State: state, PositionMs: position, DurationMs: p.DurationMs, UpdatedAt: apitime.From(p.UpdatedAt),
			ArtworkUrl: p.ArtworkURL, OriginUrl: p.OriginURL,
		}
	}
	s, t := e.Session, e.Title
	kind := api.NowPlayingItemKindEpisode
	if t.Type == core.MediaMovie {
		kind = api.NowPlayingItemKindMovie
	}
	state := api.NowPlayingItemStatePlaying
	if s.State == scrobble.Paused {
		state = api.NowPlayingItemStatePaused
	}
	summary := TitleSummaryDTO(*t)
	return api.NowPlayingItem{
		Id: item.ID, Kind: kind, Name: t.Title, Subtitle: item.Subtitle, Service: item.Service,
		Source: api.NowPlayingItemSource(s.Source), State: state, PositionMs: s.PositionMs,
		DurationMs: s.KnownDurationMs(), UpdatedAt: apitime.From(s.UpdatedAt), ArtworkUrl: item.ArtworkURL,
		LibraryItemId: apiid.PtrOrNil(s.LibraryItemID), Title: &summary, Episode: episodeRef(s.Episode),
	}
}
