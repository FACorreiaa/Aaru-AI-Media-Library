package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/stats"
	"context"
)

// GetStats is GAM-006a…e and MUS-008: a period's numbers for Insights and the Recap.
func (s *Server) GetStats(ctx context.Context, req api.GetStatsRequestObject) (api.GetStatsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var span *stats.Span
	if req.Params.Span != nil {
		v := stats.Span(*req.Params.Span)
		span = &v
	}
	period, err := s.Stats.Stats(ctx, userID, span, req.Params.Year, req.Params.Month, req.Params.Tz)
	if err != nil {
		return nil, err
	}
	return api.GetStats200JSONResponse(statsDTO(period)), nil
}

// GetProfileStats is GAM-006b: the profile's all-time numbers.
func (s *Server) GetProfileStats(ctx context.Context, _ api.GetProfileStatsRequestObject) (api.GetProfileStatsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	profile, err := s.Stats.Profile(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetProfileStats200JSONResponse(profileStatsDTO(profile)), nil
}

func profileStatsDTO(p stats.ProfileStats) api.ProfileStats {
	return api.ProfileStats{
		MemberSince: apitime.PtrOrNil(p.MemberSince), EpisodesWatched: p.EpisodesWatched,
		MinutesWatched: p.MinutesWatched, PagesRead: p.PagesRead,
		Shows: countsDTO(p.Shows), Anime: countsDTO(p.Anime), Movies: countsDTO(p.Movies), Books: countsDTO(p.Books),
		ByKind: kindsDTO(p.ByKind), TopGenres: genresDTO(p.TopGenres), TopNetworks: genresDTO(p.TopNetworks),
		MostWatched: titleTimesDTO(p.MostWatched), Ratings: ratingsDTO(p.Ratings),
	}
}

func countsDTO(c stats.Counts) api.LibraryCounts {
	return api.LibraryCounts{
		Wishlist: c.Wishlist, InProgress: c.InProgress, OnHold: c.OnHold, Finished: c.Finished, Dropped: c.Dropped,
	}
}

func kindsDTO(kinds []stats.KindTotals) []api.StatsKind {
	out := make([]api.StatsKind, 0, len(kinds))
	for _, k := range kinds {
		out = append(out, api.StatsKind{Kind: api.StatsKindKind(k.Kind), Episodes: k.Episodes, Minutes: k.Minutes, Finished: k.Finished})
	}
	return out
}

func genresDTO(genres []stats.GenreTime) []api.StatsGenre {
	out := make([]api.StatsGenre, 0, len(genres))
	for _, g := range genres {
		out = append(out, api.StatsGenre{Name: g.Name, Minutes: g.Minutes, Titles: g.Titles})
	}
	return out
}

func titleTimesDTO(titles []stats.TitleTime) []api.StatsTitle {
	out := make([]api.StatsTitle, 0, len(titles))
	for _, t := range titles {
		out = append(out, api.StatsTitle{Title: TitleSummaryDTO(t.Title), Episodes: t.Episodes, Minutes: t.Minutes})
	}
	return out
}

func ratingsDTO(r stats.Ratings) api.StatsRatings {
	out := api.StatsRatings{Count: r.Count, Mean: r.Mean, HighestRating: r.HighestRating, Distribution: r.Distribution}
	if out.Distribution == nil {
		out.Distribution = make([]int, 10)
	}
	if r.Highest != nil {
		h := TitleSummaryDTO(*r.Highest)
		out.Highest = &h
	}
	return out
}

func bucketDTO(b stats.Bucket) api.StatsBucket {
	return api.StatsBucket{Start: b.Start.String(), Episodes: b.Episodes, Minutes: b.Minutes, Finished: b.Finished}
}

func bucketPtrDTO(b *stats.Bucket) *api.StatsBucket {
	if b == nil {
		return nil
	}
	out := bucketDTO(*b)
	return &out
}

func totalsDTO(t stats.Totals) api.StatsTotals {
	manga := t.MangaFinished
	return api.StatsTotals{
		EpisodesWatched: t.EpisodesWatched, MinutesWatched: t.MinutesWatched, ActiveDays: t.ActiveDays,
		MoviesFinished: t.MoviesFinished, ShowsFinished: t.ShowsFinished, AnimeFinished: t.AnimeFinished,
		BooksFinished: t.BooksFinished, AlbumsFinished: t.AlbumsFinished, MangaFinished: &manga,
	}
}

func momentDTO(m *stats.Moment) *api.StatsMoment {
	if m == nil {
		return nil
	}
	return &api.StatsMoment{Title: TitleSummaryDTO(m.Title), At: apitime.From(m.At)}
}

func statsDTO(p stats.PeriodStats) api.Stats {
	period := p.Period
	out := api.Stats{
		Span: api.StatsSpan(period.Span), Year: period.Year, Month: period.Month, TimeZone: period.TimeZone.String(),
		IsPartial: p.IsPartial, Totals: totalsDTO(p.Totals), ByKind: kindsDTO(p.ByKind),
		Busiest: bucketPtrDTO(p.Busiest), MostEpisodes: bucketPtrDTO(p.MostEpisodes),
		TopTitles: titleTimesDTO(p.TopTitles), Ratings: ratingsDTO(p.Ratings), First: momentDTO(p.First),
		Last: momentDTO(p.Last), TopGenres: genresDTO(p.TopGenres), BiggestDay: bucketPtrDTO(p.BiggestDay),
	}
	if period.Span.Days() > 0 {
		from, until := period.Start.String(), period.LastDay().String()
		out.From, out.Until = &from, &until
	}
	if p.Prior != nil {
		prior := totalsDTO(*p.Prior)
		out.Prior = &prior
	}
	out.Buckets = make([]api.StatsBucket, 0, len(p.Buckets))
	for _, b := range p.Buckets {
		out.Buckets = append(out.Buckets, bucketDTO(b))
	}
	if r := p.LongestRun; r != nil {
		out.LongestRun = &api.StatsRun{Days: r.Days, Start: r.Start.String(), End: r.End.String()}
	}
	if p.Persona != nil {
		persona := api.StatsPersona(*p.Persona)
		out.Persona = &persona
	}
	if p.Music != nil {
		out.Music = musicDTO(*p.Music)
	}
	return out
}

func musicDTO(m stats.ListenSummary) *api.StatsMusic {
	out := &api.StatsMusic{Listens: m.Listens, Minutes: int(m.DurationMs / 60000), PriorListens: m.PriorListens}
	if m.PriorDurationMs != nil {
		minutes := int(*m.PriorDurationMs / 60000)
		out.PriorMinutes = &minutes
	}
	if top := m.TopArtist; top != nil {
		out.TopArtist = &struct {
			Artist   string  `json:"artist"`
			Count    int     `json:"count"`
			CoverUrl *string `json:"coverUrl,omitempty"`
			Minutes  int     `json:"minutes"`
		}{Artist: top.Artist, Count: top.Count, Minutes: int(top.DurationMs / 60000)}
		if top.ReleaseGroupMBID != nil {
			out.TopArtist.CoverUrl = catalog.MusicBrainzCoverURL(*top.ReleaseGroupMBID)
		}
	}
	out.TopArtistTracks = make([]struct {
		Count int    `json:"count"`
		Track string `json:"track"`
	}, 0, len(m.TopArtistTracks))
	for _, t := range m.TopArtistTracks {
		track := ""
		if t.Track != nil {
			track = *t.Track
		}
		out.TopArtistTracks = append(out.TopArtistTracks, struct {
			Count int    `json:"count"`
			Track string `json:"track"`
		}{Count: t.Count, Track: track})
	}
	return out
}
