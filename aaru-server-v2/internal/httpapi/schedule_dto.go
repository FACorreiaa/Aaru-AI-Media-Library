package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/schedule"
)

// Library DTO mapping for the reads this area serves (Watching, export).
// TODO: fold into library_dto.go after merge with go-v2/library.

// TitleSummaryDTO is Components.Schemas.TitleSummary(Title).
func TitleSummaryDTO(t core.Title) api.TitleSummary {
	return api.TitleSummary{
		Id: apiid.From(t.ID), Type: api.MediaType(t.Type), Title: t.Title, OriginalTitle: t.OriginalTitle,
		Year: t.Year, PosterUrl: t.PosterURL, BackdropUrl: t.BackdropURL, Network: t.Network, Byline: t.Byline,
		PageCount: t.PageCount, ChapterCount: t.ChapterCount, VolumeCount: t.VolumeCount, IsAnime: t.IsAnime,
		Ids: ExternalIDsDTO(t.IDs),
	}
}

// LibraryEntryDTO is Components.Schemas.LibraryEntry(LibraryEntry), without watchedEpisodes.
func LibraryEntryDTO(e schedule.LibraryEntry) api.LibraryEntry {
	item := e.Item
	out := api.LibraryEntry{
		Id: apiid.From(item.ID), Title: TitleSummaryDTO(e.Title), Status: api.LibraryStatus(item.Status),
		Notes: item.Notes, IsOwned: item.IsOwned, AddedAt: apitime.From(item.AddedAt),
		UpdatedAt: apitime.From(item.UpdatedAt), FinishedAt: apitime.PtrOrNil(item.FinishedAt),
		LastWatchedAt: apitime.PtrOrNil(e.LastWatchedAt), InBacklog: e.InBacklog(),
	}
	if item.Rating != nil {
		r := item.Rating.Value()
		out.Rating = &r
	}
	if p := e.Progress; p != nil {
		out.Progress = &api.ShowProgress{WatchedCount: p.WatchedCount, AiredCount: p.AiredCount}
		if p.NextEpisode != nil {
			out.Progress.NextEpisode = &api.EpisodeRef{Season: p.NextEpisode.Season, Number: p.NextEpisode.Episode}
		}
	}
	if e.HasBookProgress && (e.BookPage != nil || e.BookPercent != nil) {
		out.BookProgress = &api.BookProgress{Page: e.BookPage, Percent: e.BookPercent}
	}
	if e.HasMangaProgress && (e.MangaChapter != nil || e.MangaVolume != nil) {
		out.MangaProgress = &api.MangaProgress{Chapter: e.MangaChapter, Volume: e.MangaVolume}
	}
	return out
}

// EpisodeRefsDTO is a sorted list of ticks on the wire.
func EpisodeRefsDTO(keys []core.EpisodeKey) []api.EpisodeRef {
	out := make([]api.EpisodeRef, 0, len(keys))
	for _, k := range keys {
		out = append(out, api.EpisodeRef{Season: k.Season, Number: k.Episode})
	}
	return out
}
