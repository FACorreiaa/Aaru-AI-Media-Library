package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/stats"
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ListenHandlers.swift (MUS-005, MUS-008).

func (s *Server) ListListens(ctx context.Context, req api.ListListensRequestObject) (api.ListListensResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	limit := music.PageSize(req.Params.Limit)
	var before *time.Time
	if req.Params.Before != nil {
		before = &req.Params.Before.Time
	}
	listens, err := s.Listens.Listens(ctx, user, before, &limit)
	if err != nil {
		return nil, err
	}
	page := api.ListListens200JSONResponse{Items: make([]api.Listen, len(listens))}
	for i, l := range listens {
		page.Items[i] = listenDTO(l)
	}
	if len(listens) == limit {
		page.Next = apitime.Ptr(listens[len(listens)-1].ListenedAt)
	}
	return page, nil
}

func (s *Server) GetTopListens(ctx context.Context, req api.GetTopListensRequestObject) (api.GetTopListensResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	p := req.Params
	var span *stats.Span
	if p.Span != nil {
		v := stats.Span(*p.Span)
		span = &v
	}
	period, err := s.Listens.Period(span, p.Year, p.Month, p.Tz)
	if err != nil {
		return nil, err
	}
	grouping := music.Grouping(p.By)
	switch grouping {
	case music.ByArtist, music.ByTrack, music.ByAlbum:
	default:
		grouping = music.ByArtist
	}
	top, err := s.Listens.Top(ctx, user, grouping, period, p.Limit, p.Artist)
	if err != nil {
		return nil, err
	}
	out := api.GetTopListens200JSONResponse{
		By: api.ListenTopBy(grouping), Span: api.ListenTopSpan(period.Span), Year: period.Year, Month: period.Month,
		TimeZone: period.TimeZone.String(), Listens: top.Listens, Minutes: int(top.DurationMs / 60000),
	}
	out.Items = make([]struct {
		Album    *string       `json:"album,omitempty"`
		AlbumRef *api.MediaRef `json:"albumRef,omitempty"`
		Artist   string        `json:"artist"`
		Count    int           `json:"count"`
		CoverUrl *string       `json:"coverUrl,omitempty"` //nolint:revive // the generated type's field name
		Minutes  int           `json:"minutes"`
		Track    *string       `json:"track,omitempty"`
	}, len(top.Items))
	for i, item := range top.Items {
		row := &out.Items[i]
		row.Artist, row.Track, row.Album, row.Count = item.Artist, item.Track, item.Album, item.Count
		row.Minutes = int(item.DurationMs / 60000)
		if item.ReleaseGroupMBID != nil {
			row.CoverUrl = catalog.MusicBrainzCoverURL(*item.ReleaseGroupMBID)
			// An artist spans albums; only a track or an album row points at one.
			if grouping != music.ByArtist {
				row.AlbumRef = albumRef(*item.ReleaseGroupMBID, item.AlbumTitleID, item.Album)
			}
		}
	}
	return out, nil
}

// albumRef is an album by its MusicBrainz release-group id, and by Aaru's title id once it is in the catalog.
func albumRef(mbid string, titleID *uuid.UUID, title *string) *api.MediaRef {
	return &api.MediaRef{
		TitleId: apiid.PtrOrNil(titleID), Type: api.MediaType("album"), Ids: &api.ExternalIds{Musicbrainz: &mbid},
		Title: title,
	}
}

func listenDTO(l music.Listen) api.Listen {
	out := api.Listen{
		Id: strings.ToLower(l.ID.String()), ListenedAt: apitime.From(l.ListenedAt), Artist: l.Artist, Track: l.Track,
		Album: l.Album, DurationMs: l.DurationMs, OriginUrl: l.OriginURL, Client: l.Client, MusicService: l.MusicService,
	}
	if l.ReleaseGroupMBID != nil {
		// Swift's URL(string:) refuses a malformed cover link; the field is then left out.
		if cover := catalog.MusicBrainzCoverURL(*l.ReleaseGroupMBID); validURL(*cover) {
			out.CoverUrl = cover
		}
		out.AlbumRef = albumRef(*l.ReleaseGroupMBID, l.AlbumTitleID, l.Album)
	}
	return out
}
