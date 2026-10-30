package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/schedule"
	"context"

	"golang.org/x/sync/errgroup"
)

// ScheduleHandlers.swift: calendar, Up Next, Watching.

func (s *Server) GetCalendar(ctx context.Context, req api.GetCalendarRequestObject) (api.GetCalendarResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var (
		entries []schedule.CalendarEntry
		pending int
	)
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) {
		entries, err = s.Schedule.Calendar(gctx, userID, req.Params.From.Time, req.Params.To.Time)
		return err
	})
	g.Go(func() (err error) {
		pending, err = s.Schedule.PendingShows(gctx, userID)
		return err
	})
	if err := g.Wait(); err != nil {
		return nil, err
	}
	items := CalendarEntriesDTO(entries)
	return api.GetCalendar200JSONResponse{Items: items, PendingShows: &pending}, nil
}

func (s *Server) GetUpNext(ctx context.Context, _ api.GetUpNextRequestObject) (api.GetUpNextResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.Schedule.UpNext(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetUpNext200JSONResponse(UpNextDTO(rows)), nil
}

func (s *Server) ListWatching(ctx context.Context, _ api.ListWatchingRequestObject) (api.ListWatchingResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.Schedule.Watching(ctx, userID)
	if err != nil {
		return nil, err
	}
	items := make([]api.WatchingItem, 0, len(rows))
	for _, row := range rows {
		item := api.WatchingItem{Entry: LibraryEntryDTO(row.Entry)}
		if a := row.Airing; a != nil {
			if a.Status != nil {
				status := api.WatchingItemShowStatus(*a.Status)
				item.ShowStatus = &status
			}
			if n := a.Next; n != nil && n.AirsAt != nil {
				item.NextAiring = &api.UpcomingEpisode{
					Season: n.Season, Number: n.Episode, EpisodeName: n.Name, AirsAt: apitime.From(*n.AirsAt),
					AirTimeKnown: n.AirTimeKnown,
				}
			}
		}
		if n := row.Next; n != nil {
			item.NextName, item.NextRuntimeMinutes = n.NextName, n.NextRuntimeMinutes
			item.RemainingCount, item.RemainingMinutes = &n.RemainingCount, &n.RemainingMinutes
		}
		items = append(items, item)
	}
	return api.ListWatching200JSONResponse{Items: items}, nil
}

func continueEntryDTO(c schedule.ContinueEntry) api.ContinueEntry {
	return api.ContinueEntry{
		LibraryItemId: apiid.From(c.LibraryItemID), Title: TitleSummaryDTO(c.Title),
		Next: api.EpisodeRef{Season: c.Next.Season, Number: c.Next.Episode}, NextName: c.NextName,
		NextRuntimeMinutes: c.NextRuntimeMinutes, RemainingCount: c.RemainingCount,
		RemainingMinutes: c.RemainingMinutes, IsFinale: c.IsFinale,
	}
}

// CalendarEntriesDTO maps calendar entries (the calendar route and the agent's list_airs).
func CalendarEntriesDTO(entries []schedule.CalendarEntry) []api.CalendarEntry {
	items := make([]api.CalendarEntry, 0, len(entries))
	for _, e := range entries {
		items = append(items, api.CalendarEntry{
			LibraryItemId: apiid.From(e.LibraryItemID), Title: TitleSummaryDTO(e.Title), Season: e.Key.Season,
			Number: e.Key.Episode, EpisodeName: e.EpisodeName, EpisodeOverview: e.EpisodeOverview,
			StillUrl: e.StillURL, AirsAt: apitime.From(e.AirsAt), AirTimeKnown: e.AirTimeKnown,
			RuntimeMinutes: e.RuntimeMinutes, Watched: e.Watched, Kind: api.CalendarEntryKind(e.Kind),
		})
	}
	return items
}

// UpNextDTO maps Up Next (the route and the agent's list_airs).
func UpNextDTO(rows schedule.UpNext) api.UpNext {
	out := api.UpNext{
		ContinueWatching: make([]api.ContinueEntry, 0, len(rows.ContinueWatching)),
		StartWatching:    make([]api.StartEntry, 0, len(rows.StartWatching)),
		Counts: &api.LibraryCounts{
			Wishlist: rows.Counts.Wishlist, InProgress: rows.Counts.InProgress, OnHold: rows.Counts.OnHold,
			Finished: rows.Counts.Finished, Dropped: rows.Counts.Dropped,
		},
	}
	for _, c := range rows.ContinueWatching {
		out.ContinueWatching = append(out.ContinueWatching, continueEntryDTO(c))
	}
	for _, e := range rows.StartWatching {
		out.StartWatching = append(out.StartWatching, api.StartEntry{
			LibraryItemId: apiid.From(e.LibraryItemID), Title: TitleSummaryDTO(e.Title), RuntimeMinutes: e.RuntimeMinutes,
		})
	}
	unfinished := make([]api.UnfinishedEntry, 0, len(rows.Unfinished))
	for _, u := range rows.Unfinished {
		dto := api.UnfinishedEntry{
			LibraryItemId: apiid.From(u.LibraryItemID), Title: TitleSummaryDTO(u.Title),
			Reason: api.UnfinishedEntryReason(u.Reason), Since: apitime.From(u.Since),
		}
		if u.Next != nil {
			dto.Next = &api.EpisodeRef{Season: u.Next.Season, Number: u.Next.Episode}
		}
		unfinished = append(unfinished, dto)
	}
	out.Unfinished = &unfinished
	return out
}
