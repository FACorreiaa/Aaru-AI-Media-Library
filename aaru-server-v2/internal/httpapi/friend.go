package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/social"
	"context"
	"slices"
	"time"

	"github.com/google/uuid"
)

// FriendHandlers.swift: SOC-001 settings and SOC-003 friend profiles and activity.

// GetSocialSettings answers the viewer's social switches.
func (s *Server) GetSocialSettings(ctx context.Context, _ api.GetSocialSettingsRequestObject) (api.GetSocialSettingsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	settings, err := s.Social.Settings(ctx, viewer)
	if err != nil {
		return nil, err
	}
	return api.GetSocialSettings200JSONResponse(socialSettingsDTO(settings)), nil
}

// UpdateSocialSettings saves the switches. A field left out keeps its saved value: older apps
// send only the library switch.
func (s *Server) UpdateSocialSettings(ctx context.Context, req api.UpdateSocialSettingsRequestObject) (api.UpdateSocialSettingsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	settings, err := s.Social.Settings(ctx, viewer)
	if err != nil {
		return nil, err
	}
	body := req.Body
	settings.ShareLibraryWithFriends = body.ShareLibraryWithFriends
	if body.ShowAchievementsToFriends != nil {
		settings.ShowAchievementsToFriends = *body.ShowAchievementsToFriends
	}
	if body.LeaderboardOptIn != nil {
		settings.LeaderboardOptIn = *body.LeaderboardOptIn
	}
	if body.ShareEmailWithFriends != nil {
		settings.ShareEmailWithFriends = *body.ShareEmailWithFriends
	}
	saved, err := s.Social.SaveSettings(ctx, settings, viewer)
	if err != nil {
		return nil, err
	}
	return api.UpdateSocialSettings200JSONResponse(socialSettingsDTO(saved)), nil
}

// GetFriendProfile answers a friend's profile; anyone else is a 404.
func (s *Server) GetFriendProfile(ctx context.Context, req api.GetFriendProfileRequestObject) (api.GetFriendProfileResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.UserId.ID() == uuid.Nil {
		return nil, social.ErrNoSuchUser
	}
	profile, err := s.Social.FriendProfile(ctx, req.UserId.ID(), viewer)
	if err != nil {
		return nil, err
	}
	return api.GetFriendProfile200JSONResponse(friendProfileDTO(profile)), nil
}

// ListFriendActivity answers one page of your and your friends' last two weeks.
func (s *Server) ListFriendActivity(ctx context.Context, req api.ListFriendActivityRequestObject) (api.ListFriendActivityResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var before *time.Time
	if req.Params.Before != nil {
		t := req.Params.Before.Time
		before = &t
	}
	feed, err := s.Social.Activity(ctx, viewer, before)
	if err != nil {
		return nil, err
	}
	items := make([]api.ActivityItem, 0, len(feed.Items))
	for _, item := range feed.Items {
		user, okUser := feed.People[item.Friend]
		title, okTitle := feed.Titles[item.TitleID]
		if !okUser || !okTitle {
			continue
		}
		key := social.ActivityKey{Owner: item.Friend, TitleID: item.TitleID, Day: item.Day}
		summary := feed.Reactions[key]
		dto := api.ActivityItem{
			Id: key.ID(), User: SocialUserDTO(user), Title: TitleSummaryDTO(title), Day: apiDate(item.Day),
			Episodes: item.Episodes, LastSeason: item.LastSeason, LastEpisode: item.LastEpisode, Finished: item.Finished,
			Rating: item.Rating, At: apitime.From(item.LastAt), MyReaction: summary.Mine,
		}
		if counts := reactionCounts(summary.Counts); len(counts) > 0 {
			dto.Reactions = &counts
		}
		items = append(items, dto)
	}
	page := api.ActivityPage{Items: items}
	if len(feed.Items) == social.ActivityPage {
		next := apitime.From(feed.Items[len(feed.Items)-1].LastAt)
		page.NextBefore = &next
	}
	return api.ListFriendActivity200JSONResponse(page), nil
}

// reactionCounts are how many of each emoji, most first, then in the set's order.
func reactionCounts(counts map[string]int) []api.ReactionCount {
	out := make([]api.ReactionCount, 0, len(counts))
	for emoji, n := range counts {
		out = append(out, api.ReactionCount{Emoji: emoji, Count: n})
	}
	slices.SortFunc(out, func(a, b api.ReactionCount) int {
		if a.Count != b.Count {
			return b.Count - a.Count
		}
		return social.ReactionOrder(a.Emoji) - social.ReactionOrder(b.Emoji)
	})
	return out
}

func socialSettingsDTO(s social.Settings) api.SocialSettings {
	achievements, leaderboard, email := s.ShowAchievementsToFriends, s.LeaderboardOptIn, s.ShareEmailWithFriends
	return api.SocialSettings{
		ShareLibraryWithFriends: s.ShareLibraryWithFriends, ShowAchievementsToFriends: &achievements,
		LeaderboardOptIn: &leaderboard, ShareEmailWithFriends: &email,
	}
}

func friendProfileDTO(p social.FriendProfile) api.FriendProfile {
	out := api.FriendProfile{
		User: SocialUserDTO(p.User), FriendsSince: apitime.From(p.FriendsSince), Sharing: p.Sharing, Email: p.Email,
	}
	if shelf := p.Shelf; shelf != nil {
		manga := shelf.Counts["manga"]
		out.Counts = &api.KindCounts{
			Movie: shelf.Counts["movie"], Show: shelf.Counts["show"], Anime: shelf.Counts["anime"], Book: shelf.Counts["book"],
			Album: shelf.Counts["album"], Manga: &manga,
		}
		watching, finished := friendItems(shelf.Watching, p.Titles), friendItems(shelf.Finished, p.Titles)
		out.Watching, out.RecentlyFinished = &watching, &finished
		out.Compare = &api.FriendCompare{
			BothWant: titleSummaries(shelf.BothWant, p.Titles), BothFinished: shelf.BothFinished,
			TheyLoved: titleSummaries(shelf.TheyLoved, p.Titles),
		}
	}
	if a := p.Achievements; a != nil {
		badges := make([]api.BadgeAward, 0, len(a.Badges))
		for _, b := range a.Badges {
			if dto, ok := badgeAwardDTO(b); ok {
				dto.Reveal = false
				badges = append(badges, dto)
			}
		}
		out.Achievements = &api.FriendAchievements{Level: a.Level, Badges: badges}
	}
	if p.Favorites != nil {
		favorites := FavoritesDTO(*p.Favorites)
		out.Favorites = &favorites
	}
	return out
}

func friendItems(items []social.FriendItem, titles map[uuid.UUID]core.Title) []api.FriendItem {
	out := make([]api.FriendItem, 0, len(items))
	for _, item := range items {
		title, ok := titles[item.TitleID]
		if !ok {
			continue
		}
		out = append(out, api.FriendItem{
			Title: TitleSummaryDTO(title), Status: api.LibraryStatus(item.Status), Rating: item.Rating,
			LastSeason: item.LastSeason, LastEpisode: item.LastEpisode, BookPage: item.BookPage,
			MangaChapter: item.MangaChapter, FinishedAt: apitime.PtrOrNil(item.FinishedAt), UpdatedAt: apitime.From(item.UpdatedAt),
		})
	}
	return out
}

func titleSummaries(ids []uuid.UUID, titles map[uuid.UUID]core.Title) []api.TitleSummary {
	out := make([]api.TitleSummary, 0, len(ids))
	for _, id := range ids {
		if title, ok := titles[id]; ok {
			out = append(out, TitleSummaryDTO(title))
		}
	}
	return out
}
