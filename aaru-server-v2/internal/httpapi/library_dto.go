package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"

	"github.com/google/uuid"
)

// Library DTO mapping (LibraryHandlers.swift, ListHandlers.swift), exported for the other areas
// that return library shapes (imports, plans, groups' shelf channels, boards, schedule, stats).

// TitleSummaryDTO is a title on the wire (Components.Schemas.TitleSummary).
func TitleSummaryDTO(t core.Title) api.TitleSummary {
	return api.TitleSummary{
		Id: apiid.From(t.ID), Type: api.MediaType(t.Type), Title: t.Title, OriginalTitle: t.OriginalTitle, Year: t.Year,
		PosterUrl: t.PosterURL, BackdropUrl: t.BackdropURL, Network: t.Network, Byline: t.Byline, PageCount: t.PageCount,
		ChapterCount: t.ChapterCount, VolumeCount: t.VolumeCount, IsAnime: t.IsAnime, Ids: ExternalIDsDTO(t.IDs),
	}
}

// LibraryEntryDTO is a library entry on the wire, without watched episodes (lists, pages, sync).
func LibraryEntryDTO(e library.Entry) api.LibraryEntry {
	item := e.Item
	out := api.LibraryEntry{
		Id: apiid.From(item.ID), Title: TitleSummaryDTO(e.Title), Status: api.LibraryStatus(item.Status),
		Notes: item.Notes, IsOwned: item.IsOwned, AddedAt: apitime.From(item.AddedAt), UpdatedAt: apitime.From(item.UpdatedAt),
		InBacklog: e.InBacklog(),
	}
	if item.Rating != nil {
		v := item.Rating.Value()
		out.Rating = &v
	}
	if item.FinishedAt != nil {
		t := apitime.From(*item.FinishedAt)
		out.FinishedAt = &t
	}
	if e.LastWatchedAt != nil {
		t := apitime.From(*e.LastWatchedAt)
		out.LastWatchedAt = &t
	}
	if p := e.Progress; p != nil {
		out.Progress = &api.ShowProgress{WatchedCount: p.WatchedCount, AiredCount: p.AiredCount}
		if p.NextEpisode != nil {
			out.Progress.NextEpisode = &api.EpisodeRef{Season: p.NextEpisode.Season, Number: p.NextEpisode.Episode}
		}
	}
	if b := e.BookProgress; b != nil && (b.Page != nil || b.Percent != nil) {
		out.BookProgress = &api.BookProgress{Page: b.Page, Percent: b.Percent}
	}
	if m := e.MangaProgress; m != nil && (m.Chapter != nil || m.Volume != nil) {
		out.MangaProgress = &api.MangaProgress{Chapter: m.Chapter, Volume: m.Volume}
	}
	return out
}

// LibraryEntryWithWatchedDTO is a single-item response: the entry plus every watched episode of a
// show, in order, so a client can draw ticks.
func LibraryEntryWithWatchedDTO(ctx context.Context, store *library.Store, e library.Entry) (api.LibraryEntry, error) {
	out := LibraryEntryDTO(e)
	if e.Title.Type == core.MediaShow {
		keys, err := store.WatchedSorted(ctx, e.Item.ID)
		if err != nil {
			return api.LibraryEntry{}, err
		}
		refs := make([]api.EpisodeRef, len(keys))
		for i, k := range keys {
			refs[i] = api.EpisodeRef{Season: k.Season, Number: k.Episode}
		}
		out.WatchedEpisodes = &refs
	}
	return out, nil
}

// LibraryEntriesDTO maps a page of entries.
func LibraryEntriesDTO(entries []library.Entry) []api.LibraryEntry {
	out := make([]api.LibraryEntry, len(entries))
	for i, e := range entries {
		out[i] = LibraryEntryDTO(e)
	}
	return out
}

// ActionDTO is a journal row on the wire.
func ActionDTO(a library.ActionRecord) api.Action {
	out := api.Action{
		Id: apiid.From(a.ID), Actor: api.ActionActor(a.Actor), Kind: a.Kind, Summary: a.Summary,
		ItemIds: apiid.Slice(a.ItemIDs), CreatedAt: apitime.From(a.CreatedAt), UndoOf: apiid.PtrOrNil(a.UndoOf),
		AgentName: a.AgentName,
	}
	if a.UndoneAt != nil {
		t := apitime.From(*a.UndoneAt)
		out.UndoneAt = &t
	}
	return out
}

// ItemPatchFromAPI reads the patch shape the route and the agent tools share.
func ItemPatchFromAPI(dto api.LibraryItemPatch) library.ItemPatch {
	p := library.ItemPatch{
		Rating: dto.Rating, Notes: dto.Notes, IsOwned: dto.IsOwned, BookPage: dto.BookPage, BookPercent: dto.BookPercent,
		MangaChapter: dto.MangaChapter, MangaVolume: dto.MangaVolume, Clear: map[library.Clearable]bool{},
	}
	if dto.Status != nil {
		s := core.LibraryStatus(*dto.Status)
		p.Status = &s
	}
	if dto.Clear != nil {
		for _, c := range *dto.Clear {
			switch k := library.Clearable(c); k {
			case library.ClearRating, library.ClearNotes, library.ClearBookProgress, library.ClearMangaProgress:
				p.Clear[k] = true
			}
		}
	}
	return p
}

// ShelfFilterFromAPI reads a shelf filter; a malformed list id is no list filter.
func ShelfFilterFromAPI(dto api.ShelfFilter) library.Filter {
	var f library.Filter
	if dto.Type != nil {
		t := core.MediaType(*dto.Type)
		f.Type = &t
	}
	f.IsAnime = dto.Anime
	if dto.Status != nil {
		s := core.LibraryStatus(*dto.Status)
		f.Status = &s
	}
	f.IsOwned = dto.Owned
	if dto.List != nil && dto.List.ID() != uuid.Nil {
		id := dto.List.ID()
		f = f.WithList(&id)
	}
	return f
}

// ShelfDTO is a shelf on the wire.
func ShelfDTO(s library.Shelf) api.Shelf {
	f := s.Filter
	filter := api.ShelfFilter{Anime: f.IsAnime, Owned: f.IsOwned}
	if f.Type != nil {
		t := api.MediaType(*f.Type)
		filter.Type = &t
	}
	if f.Status != nil {
		st := api.LibraryStatus(*f.Status)
		filter.Status = &st
	}
	filter.List = apiid.PtrOrNil(f.List())
	return api.Shelf{Id: apiid.From(s.ID), Name: s.Name, Filter: filter, IsPinned: s.IsPinned}
}

// ListDetailDTO is a list on the wire, with its rows.
func ListDetailDTO(d library.ListDetail) api.ListDetail {
	titles := make([]api.TitleSummary, len(d.Titles))
	for i, t := range d.Titles {
		titles[i] = TitleSummaryDTO(t)
	}
	items := make([]api.ListItem, len(d.Members))
	for i, m := range d.Members {
		items[i] = ListItemDTO(m)
	}
	return api.ListDetail{
		Id: apiid.From(d.List.ID), Name: d.List.Name, Titles: titles, Items: items,
		CreatedAt: apitime.From(d.List.CreatedAt), UpdatedAt: apitime.From(d.List.UpdatedAt),
	}
}

// ListItemDTO is one list row: the title, the caller's entry, and a show's status and next airing.
func ListItemDTO(m library.ListMember) api.ListItem {
	out := api.ListItem{Title: TitleSummaryDTO(m.Title)}
	if m.Entry != nil {
		e := LibraryEntryDTO(*m.Entry)
		out.Entry = &e
	}
	if m.Airing != nil {
		if s := m.Airing.Status; s != nil {
			st := api.ListItemShowStatus(*s)
			out.ShowStatus = &st
		}
		out.NextAiring = UpcomingEpisodeDTO(m.Airing.Next)
	}
	return out
}

// UpcomingEpisodeDTO is an episode about to air; nil when it has no air date yet.
func UpcomingEpisodeDTO(ep *catalog.Episode) *api.UpcomingEpisode {
	if ep == nil || ep.AirsAt == nil {
		return nil
	}
	return &api.UpcomingEpisode{
		Season: ep.Season, Number: ep.Episode, EpisodeName: ep.Name, AirsAt: apitime.From(*ep.AirsAt),
		AirTimeKnown: ep.AirTimeKnown,
	}
}
