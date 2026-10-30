package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

// GamificationHandlers.swift: GAM-001…005: progress, badges, the ledger and the weekly friends board.

func (s *Server) GetProgress(ctx context.Context, _ api.GetProgressRequestObject) (api.GetProgressResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	progress, err := s.Gamification.Progress(ctx, userID)
	if err != nil {
		return nil, err
	}
	// One summary for anything an import, a plan or the first run awarded.
	origin := gamification.OriginLive
	for _, b := range progress.Unseen {
		if b.Origin != gamification.OriginLive {
			origin = b.Origin
			break
		}
	}
	out := api.Progress{
		Total: progress.Total, Level: progress.Level, LevelStart: progress.LevelStart,
		NextLevelAt: progress.NextLevelAt, WeekPoints: progress.WeekPoints,
		Streak: api.StreakState{
			Current: progress.Streak.Current, Longest: progress.Streak.Longest, Today: progress.Streak.Today,
			Days: make([]api.StreakDayState, 0, len(progress.Days)),
		},
	}
	for _, d := range progress.Days {
		out.Streak.Days = append(out.Streak.Days, api.StreakDayState{Date: apiDate(d.Date), Active: d.Active})
	}
	out.Unseen.Count = len(progress.Unseen)
	out.Unseen.Origin = api.BadgeOrigin(origin)
	out.Unseen.Items = []api.BadgeAward{}
	for _, b := range progress.Unseen[:min(5, len(progress.Unseen))] {
		if award, ok := badgeAwardDTO(b); ok {
			out.Unseen.Items = append(out.Unseen.Items, award)
		}
	}
	return api.GetProgress200JSONResponse(out), nil
}

func (s *Server) ListBadges(ctx context.Context, _ api.ListBadgesRequestObject) (api.ListBadgesResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	badges, err := s.Gamification.Badges(ctx, userID)
	if err != nil {
		return nil, err
	}
	items := make([]api.Badge, len(badges))
	for i, b := range badges {
		items[i] = badgeDTO(b)
	}
	return api.ListBadges200JSONResponse(api.BadgeList{Items: items}), nil
}

func (s *Server) MarkBadgesSeen(ctx context.Context, req api.MarkBadgesSeenRequestObject) (api.MarkBadgesSeenResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	if len(req.Body.Ids) > 200 {
		return nil, apperr.New(422, "validation_failed", "Send at most 200 ids.")
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	// Malformed ids read as nil and are dropped, as Swift's compactMap did.
	var ids []uuid.UUID
	for _, id := range apiid.IDs(req.Body.Ids) {
		if id != uuid.Nil {
			ids = append(ids, id)
		}
	}
	if err := s.Gamification.MarkSeen(ctx, ids, userID); err != nil {
		return nil, err
	}
	return api.MarkBadgesSeen204Response{}, nil
}

func (s *Server) ListPoints(ctx context.Context, req api.ListPointsRequestObject) (api.ListPointsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	limit := 50
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	limit = min(max(limit, 1), 100)
	var before *time.Time
	if req.Params.Before != nil {
		t := req.Params.Before.Time
		before = &t
	}
	events, err := s.Gamification.Events(ctx, userID, before, limit)
	if err != nil {
		return nil, err
	}
	var titleIDs []uuid.UUID
	seen := map[uuid.UUID]bool{}
	for _, e := range events {
		if e.TitleID != nil && !seen[*e.TitleID] {
			seen[*e.TitleID] = true
			titleIDs = append(titleIDs, *e.TitleID)
		}
	}
	titles := map[uuid.UUID]api.TitleSummary{}
	if len(titleIDs) > 0 {
		rows, err := s.q.GamificationTitles(ctx, titleIDs)
		if err != nil {
			return nil, fmt.Errorf("points titles: %w", err)
		}
		for _, row := range rows {
			titles[row.ID] = gamificationTitleSummary(row)
		}
	}
	page := api.PointsPage{Items: make([]api.PointsEventItem, len(events))}
	for i, e := range events {
		item := api.PointsEventItem{
			Id: apiid.From(e.ID), Kind: e.Kind, Points: e.Points, Day: apiDate(e.LocalDate),
			At: apitime.From(e.CreatedAt), Revocation: e.IsRevocation,
		}
		if e.TitleID != nil {
			if t, ok := titles[*e.TitleID]; ok {
				item.Title = &t
			}
		}
		page.Items[i] = item
	}
	if len(events) == limit && len(events) > 0 {
		page.NextBefore = apitime.Ptr(events[len(events)-1].CreatedAt)
	}
	return api.ListPoints200JSONResponse(page), nil
}

func (s *Server) GetLeaderboard(ctx context.Context, req api.GetLeaderboardRequestObject) (api.GetLeaderboardResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	board, err := s.Gamification.Leaderboard(ctx, viewer, req.Params.Week)
	if err != nil {
		return nil, err
	}
	out := api.Leaderboard{
		Week: board.Week, From: apiDate(board.From), Until: apiDate(board.Until), OptedIn: board.OptedIn,
		Entries: make([]api.LeaderboardEntry, len(board.Entries)),
	}
	for i, e := range board.Entries {
		out.Entries[i] = api.LeaderboardEntry{
			User: gamificationSocialUser(e.User), Points: e.Points, Rank: e.Rank, You: e.User.ID == viewer,
		}
	}
	return api.GetLeaderboard200JSONResponse(out), nil
}

// badgeAwardDTO is false for a badge no longer in the catalog. Reveal is the rule: a live award
// of a tiered badge's top tier, or of a hidden badge. The friend profile uses it too.
func badgeAwardDTO(award gamification.EarnedBadge) (api.BadgeAward, bool) {
	definition, ok := gamification.ByID[award.Badge]
	if !ok {
		return api.BadgeAward{}, false
	}
	top := award.Tier == definition.MaxTier() && (definition.MaxTier() > 1 || definition.Hidden)
	return api.BadgeAward{
		Id: apiid.From(award.ID), Badge: award.Badge, Name: definition.Name, Family: api.BadgeFamily(definition.Family),
		Tier: award.Tier, MaxTier: definition.MaxTier(), AwardedAt: apitime.From(award.AwardedAt),
		Origin: api.BadgeOrigin(award.Origin), Reveal: award.Origin == gamification.OriginLive && top,
	}, true
}

func badgeDTO(status gamification.BadgeStatus) api.Badge {
	definition := status.Definition
	earned := len(status.Earned) > 0
	secret := definition.Hidden && !earned
	byTier := map[int]time.Time{}
	for _, e := range status.Earned {
		if _, ok := byTier[e.Tier]; !ok {
			byTier[e.Tier] = e.AwardedAt
		}
	}
	target, hasTarget := status.Target()
	shown := 1
	switch {
	case hasTarget:
		shown = target
	case len(definition.Thresholds) > 0:
		shown = definition.Thresholds[len(definition.Thresholds)-1]
	}
	out := api.Badge{
		Id: definition.ID, Family: api.BadgeFamily(definition.Family), Hidden: definition.Hidden, Earned: earned,
		Tier: status.Tier(), MaxTier: definition.MaxTier(),
	}
	if definition.Private {
		t := true
		out.Private = &t
	}
	tiers := []api.BadgeTier{}
	if !secret {
		name, description := definition.Name, definition.Describe(shown)
		out.Name, out.Description = &name, &description
		if hasTarget {
			out.Progress = &struct {
				Current int `json:"current"`
				Target  int `json:"target"`
			}{Current: min(status.Value, target), Target: target}
		}
		for i, threshold := range definition.Thresholds {
			tier := api.BadgeTier{Tier: i + 1, Threshold: threshold, Description: definition.Describe(threshold)}
			if at, ok := byTier[i+1]; ok {
				tier.AwardedAt = apitime.Ptr(at)
			}
			tiers = append(tiers, tier)
		}
	}
	out.Tiers = &tiers
	return out
}

// apiDate is a `yyyy-MM-dd` local date on the wire.
func apiDate(date string) openapi_types.Date {
	t, err := time.Parse(time.DateOnly, date)
	if err != nil {
		return openapi_types.Date{}
	}
	return openapi_types.Date{Time: t}
}

// gamificationSocialUser is Components.Schemas.SocialUser(SocialUser).
func gamificationSocialUser(user gamification.SocialUser) api.SocialUser {
	out := api.SocialUser{UserId: apiid.From(user.ID), Handle: user.Handle, DisplayName: user.DisplayName}
	if user.AvatarVersion != nil {
		path := fmt.Sprintf("/v1/users/%s/avatar?v=%d", apiid.From(user.ID).String(), *user.AvatarVersion)
		out.AvatarUrl = &path
	}
	return out
}

// gamificationTitleSummary is Components.Schemas.TitleSummary(Title) for a ledger row's title.
func gamificationTitleSummary(row sqlc.GamificationTitlesRow) api.TitleSummary {
	return api.TitleSummary{
		Id: apiid.From(row.ID), Type: api.MediaType(row.Type), Title: row.Title, OriginalTitle: row.OriginalTitle,
		Year: intPtr(row.Year), PosterUrl: row.PosterUrl, BackdropUrl: row.BackdropUrl, Network: row.Network,
		Byline: row.Byline, PageCount: intPtr(row.PageCount), ChapterCount: intPtr(row.ChapterCount),
		VolumeCount: intPtr(row.VolumeCount), IsAnime: row.IsAnime,
		Ids: api.ExternalIds{
			Tmdb: row.Tmdb, Imdb: row.Imdb, Trakt: row.Trakt, Tvdb: row.Tvdb, Isbn: row.Isbn,
			OpenLibrary: row.OpenLibrary, Anilist: row.Anilist, Mal: row.Mal, Anidb: row.Anidb,
			Musicbrainz: row.Musicbrainz,
		},
	}
}

func intPtr(v *int32) *int {
	if v == nil {
		return nil
	}
	n := int(*v)
	return &n
}
