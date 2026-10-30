package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"slices"
	"strings"

	"github.com/google/uuid"
)

// Catalog routes (API/CatalogHandlers.swift): search, Discover rows, seasons, the
// on-air guide, title detail and resolve.

// SearchCatalog is GET /v1/catalog/search.
func (s *Server) SearchCatalog(ctx context.Context, req api.SearchCatalogRequestObject) (api.SearchCatalogResponseObject, error) {
	result, err := s.Catalog.Service.Search(ctx, req.Params.Q, catalog.SearchScope(req.Params.Type))
	if err != nil {
		return nil, err
	}
	return api.SearchCatalog200JSONResponse(api.SearchResults{
		Items: catalogHits(result.Hits), Incomplete: result.Incomplete, Notice: result.Notice,
	}), nil
}

// GetDiscover is GET /v1/discover.
func (s *Server) GetDiscover(ctx context.Context, _ api.GetDiscoverRequestObject) (api.GetDiscoverResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.Catalog.Discover.Rows(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]api.DiscoverRow, 0, len(rows))
	for _, row := range rows {
		out = append(out, api.DiscoverRow{
			Id: string(row.List), Kind: api.DiscoverRowKind(row.List.Kind()), Title: row.Title,
			Items: discoverHits(row.Items), Note: row.Note,
		})
	}
	return api.GetDiscover200JSONResponse(api.DiscoverRows{Rows: out}), nil
}

// GetDiscoverSeason is GET /v1/discover/seasons.
func (s *Server) GetDiscoverSeason(ctx context.Context, req api.GetDiscoverSeasonRequestObject) (api.GetDiscoverSeasonResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	q := req.Params
	key := catalog.SeasonKey{Season: catalog.SeasonOfYear(q.Season), Year: q.Year}
	page := 1
	if q.Page != nil {
		page = *q.Page
	}
	result, err := s.Catalog.Discover.Season(ctx, key, catalog.SeasonKind(q.Kind), page, userID)
	if err != nil {
		return nil, err
	}
	from, until := key.Days()
	return api.GetDiscoverSeason200JSONResponse(api.SeasonPage{
		Kind: api.SeasonPageKind(q.Kind), Season: api.SeasonPageSeason(q.Season), Year: key.Year,
		From: from, Until: until, Title: key.Title(), Items: discoverHits(result.Items), Page: result.Page,
		HasMore: result.HasMore, Total: result.Total, Unavailable: result.Unavailable,
	}), nil
}

// GetDiscoverOnAir is GET /v1/discover/on-air.
func (s *Server) GetDiscoverOnAir(ctx context.Context, req api.GetDiscoverOnAirRequestObject) (api.GetDiscoverOnAirResponseObject, error) {
	region := ""
	if req.Params.Region != nil {
		region = strings.ToUpper(*req.Params.Region)
		if !isRegion(region) {
			return nil, apperr.Validation("region", "Two letters, as ISO 3166-1.")
		}
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	guide, err := s.Catalog.Discover.OnAir(ctx, userID, region)
	if err != nil {
		return nil, err
	}
	channels := make([]api.OnAirChannel, 0, len(guide.Channels))
	for _, group := range guide.Channels {
		shows := make([]api.OnAirShow, 0, len(group.Shows))
		for _, show := range group.Shows {
			out := api.OnAirShow{
				Item: catalogHit(show.Item.Hit, show.Item.LibraryItemID),
				NextEpisode: api.OnAirEpisode{
					Season: show.Next.Season, Number: show.Next.Number, Name: show.Next.Name,
					AirsAt: apitime.From(show.Next.AirsAt), AirTimeKnown: show.Next.AirTimeKnown,
				},
			}
			if len(show.StreamsOn) > 0 {
				streams := make([]api.WatchProvider, 0, len(show.StreamsOn))
				for _, p := range show.StreamsOn {
					streams = append(streams, api.WatchProvider{Name: p.Name, LogoUrl: p.LogoURL})
				}
				out.StreamsOn = &streams
				out.WatchLink = show.WatchLink
			}
			shows = append(shows, out)
		}
		channels = append(channels, api.OnAirChannel{Name: group.Channel.Name, LogoUrl: group.Channel.LogoURL, Shows: shows})
	}
	return api.GetDiscoverOnAir200JSONResponse(api.DiscoverOnAir{
		Channels: channels, UpdatedAt: apitime.PtrOrNil(guide.UpdatedAt),
	}), nil
}

// isRegion is two ASCII letters.
func isRegion(region string) bool {
	if len(region) != 2 {
		return false
	}
	for _, r := range region {
		if r < 'A' || r > 'Z' {
			return false
		}
	}
	return true
}

// GetTitle is GET /v1/titles/{id}. A malformed id reads as uuid.Nil and is a 404.
func (s *Server) GetTitle(ctx context.Context, req api.GetTitleRequestObject) (api.GetTitleResponseObject, error) {
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound()
	}
	detail, err := s.Catalog.Service.Detail(ctx, req.Id.ID())
	if err != nil {
		return nil, err
	}
	return api.GetTitle200JSONResponse(TitleDetailDTO(*detail)), nil
}

// ResolveTitle is POST /v1/titles/resolve (LIB-006): the page for a title the user
// may not have. Resolving fills the catalog (a provider row becomes a `titles` row,
// as an add would) and writes nothing to the library.
func (s *Server) ResolveTitle(ctx context.Context, req api.ResolveTitleRequestObject) (api.ResolveTitleResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	title, err := s.Catalog.Resolver().Resolve(ctx, MediaRefFromAPI(*req.Body), nil)
	if err != nil {
		return nil, err
	}
	detail, err := s.Catalog.Service.Detail(ctx, title.ID)
	if err != nil {
		return nil, err
	}
	itemID, err := s.Catalog.Store.LibraryItemID(ctx, userID, title.ID)
	if err != nil {
		return nil, err
	}
	return api.ResolveTitle200JSONResponse(api.TitlePreview{
		Title: TitleDetailDTO(*detail), LibraryItemId: apiid.PtrOrNil(itemID),
	}), nil
}

// MARK: - DTO mapping, exported for the other areas that return catalog shapes.

// ExternalIDsDTO is the wire shape of a title's ids; unknown ids are absent.
func ExternalIDsDTO(ids core.ExternalIDs) api.ExternalIds {
	p := func(s string) *string {
		if s == "" {
			return nil
		}
		return &s
	}
	return api.ExternalIds{
		Tmdb: p(ids.TMDB), Imdb: p(ids.IMDB), Trakt: p(ids.Trakt), Tvdb: p(ids.TVDB), Isbn: p(ids.ISBN),
		OpenLibrary: p(ids.OpenLibrary), Anilist: p(ids.AniList), Mal: p(ids.MAL), Anidb: p(ids.AniDB),
		Musicbrainz: p(ids.MusicBrainz),
	}
}

// ExternalIDsFromAPI reads wire ids; absent and blank are unknown.
func ExternalIDsFromAPI(ids *api.ExternalIds) core.ExternalIDs {
	if ids == nil {
		return core.ExternalIDs{}
	}
	v := func(s *string) string {
		if s == nil {
			return ""
		}
		return *s
	}
	return core.ExternalIDs{
		TMDB: v(ids.Tmdb), IMDB: v(ids.Imdb), Trakt: v(ids.Trakt), TVDB: v(ids.Tvdb), ISBN: v(ids.Isbn),
		OpenLibrary: v(ids.OpenLibrary), AniList: v(ids.Anilist), MAL: v(ids.Mal), AniDB: v(ids.Anidb),
		MusicBrainz: v(ids.Musicbrainz),
	}
}

// MediaRefFromAPI reads a wire MediaRef.
func MediaRefFromAPI(ref api.MediaRef) core.MediaRef {
	out := core.MediaRef{Type: core.MediaType(ref.Type), IDs: ExternalIDsFromAPI(ref.Ids), Title: ref.Title, Year: ref.Year}
	// A malformed id reads as uuid.Nil, which Swift read as no id at all.
	if ref.TitleId != nil && ref.TitleId.ID() != uuid.Nil {
		id := ref.TitleId.ID()
		out.TitleID = &id
	}
	return out
}

func catalogHits(hits []catalog.Hit) []api.CatalogHit {
	out := make([]api.CatalogHit, 0, len(hits))
	for _, h := range hits {
		out = append(out, catalogHit(h, nil))
	}
	return out
}

func discoverHits(items []catalog.DiscoverItem) []api.CatalogHit {
	out := make([]api.CatalogHit, 0, len(items))
	for _, item := range items {
		out = append(out, catalogHit(item.Hit, item.LibraryItemID))
	}
	return out
}

// CatalogHitDTO is a search or Discover hit on the wire, with the caller's library
// item when they have one (upper-case, like Swift's uuidString).
func CatalogHitDTO(h catalog.Hit, libraryItemID *uuid.UUID) api.CatalogHit {
	return catalogHit(h, libraryItemID)
}

func catalogHit(h catalog.Hit, libraryItemID *uuid.UUID) api.CatalogHit {
	var item *string
	if libraryItemID != nil {
		s := apiid.From(*libraryItemID).String()
		item = &s
	}
	return api.CatalogHit{
		Type: api.MediaType(h.Type), Title: h.Title, OriginalTitle: h.OriginalTitle, Year: h.Year,
		PosterUrl: h.PosterURL, Overview: h.Overview, Byline: h.Byline, IsAnime: h.IsAnime,
		Ids: ExternalIDsDTO(h.IDs), LibraryItemId: item, ReleaseDate: h.ReleaseDate,
	}
}

// TitleDetailDTO is a title detail on the wire: seasons grouped by number, genres
// for albums only, tracks once a tracklist was fetched.
func TitleDetailDTO(d catalog.TitleDetail) api.TitleDetail {
	t := d.Title
	out := api.TitleDetail{
		Id: apiid.From(t.ID), Type: api.MediaType(t.Type), Title: t.Title, OriginalTitle: t.OriginalTitle,
		Year: t.Year, Synopsis: t.Synopsis, PosterUrl: t.PosterURL, IsAnime: t.IsAnime, Ids: ExternalIDsDTO(t.IDs),
		RuntimeMinutes: d.RuntimeMinutes, Byline: t.Byline,
	}
	if d.Status != nil {
		status := api.TitleDetailStatus(*d.Status)
		out.Status = &status
	}
	if d.Episodes != nil {
		bySeason := map[int][]api.Episode{}
		for _, e := range d.Episodes {
			bySeason[e.Season] = append(bySeason[e.Season], api.Episode{
				Season: e.Season, Number: e.Episode, Name: e.Name, Overview: e.Overview, StillUrl: e.StillURL,
				AirsAt: apitime.PtrOrNil(e.AirsAt), AirTimeKnown: e.AirTimeKnown, RuntimeMinutes: e.RuntimeMinutes,
			})
		}
		numbers := make([]int, 0, len(bySeason))
		for n := range bySeason {
			numbers = append(numbers, n)
		}
		slices.Sort(numbers)
		seasons := make([]api.Season, 0, len(numbers))
		for _, n := range numbers {
			seasons = append(seasons, api.Season{Number: n, Episodes: bySeason[n]})
		}
		out.Seasons = &seasons
	}
	if t.Type == core.MediaAlbum {
		genres := d.Genres
		if genres == nil {
			genres = []string{}
		}
		out.Genres = &genres
	}
	if d.Tracks != nil {
		tracks := make([]api.AlbumTrack, 0, len(d.Tracks))
		for _, tr := range d.Tracks {
			tracks = append(tracks, api.AlbumTrack{Disc: tr.Disc, Position: tr.Position, Name: tr.Name, LengthMs: tr.LengthMs})
		}
		out.Tracks = &tracks
	}
	return out
}
