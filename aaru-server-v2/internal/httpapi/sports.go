package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/sports"
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
)

// SportsHandlers.swift: SPT-002 · the Sports tab: follows, favorites, one day's schedule, one
// event and where to watch it. Sports only: nothing here touches the library, the journal or friends.

var errSportsOff = apperr.Unavailable("sports_unavailable", "Sports are not set up yet.")

func (s *Server) GetSportSuggestions(ctx context.Context, _ api.GetSportSuggestionsRequestObject) (api.GetSportSuggestionsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	following, err := s.followedSports(ctx, userID)
	if err != nil {
		return nil, err
	}
	picks := s.Sports.Suggestions(ctx)
	return api.GetSportSuggestions200JSONResponse{Items: sportEntityDTOs(picks, following), Unavailable: !s.Sports.IsAvailable()}, nil
}

func (s *Server) SearchSports(ctx context.Context, req api.SearchSportsRequestObject) (api.SearchSportsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	query := strings.TrimSpace(req.Params.Q)
	if n := core.Length(query); n < 2 || n > 100 {
		return nil, apperr.Validation("q", "Type 2 to 100 characters.")
	}
	if !s.Sports.IsAvailable() {
		return api.SearchSports200JSONResponse{Items: []api.SportEntity{}, Unavailable: true}, nil
	}
	var kind sports.EntityKind
	if req.Params.Kind != nil {
		kind = sports.EntityKind(*req.Params.Kind)
	}
	found, err := s.Sports.Search(ctx, query, kind)
	if err != nil {
		return nil, err
	}
	following, err := s.followedSports(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.SearchSports200JSONResponse{Items: sportEntityDTOs(found, following)}, nil
}

func (s *Server) GetSportFavorites(ctx context.Context, _ api.GetSportFavoritesRequestObject) (api.GetSportFavoritesResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	favorites, err := s.Sports.Favorites(ctx, userID)
	if err != nil {
		return nil, err
	}
	items := make([]api.SportFavorite, 0, len(favorites.Items))
	for _, f := range favorites.Items {
		item := api.SportFavorite{
			Entity: sportEntityDTO(f.Entity, map[string]bool{sportFollowKey(f.Entity): true}),
			Live:   sportEventDTOs(f.Live), Pending: f.Pending,
		}
		if f.Next != nil {
			next := sportEventDTO(*f.Next, false)
			item.Next = &next
		}
		if f.Last != nil {
			last := sportEventDTO(*f.Last, false)
			item.Last = &last
		}
		items = append(items, item)
	}
	return api.GetSportFavorites200JSONResponse{Items: items, Unavailable: favorites.Unavailable}, nil
}

func (s *Server) GetSportSchedule(ctx context.Context, req api.GetSportScheduleRequestObject) (api.GetSportScheduleResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	zone := time.UTC
	if name := req.Params.Tz; name != nil {
		given, err := time.LoadLocation(*name)
		if err != nil || *name == "" || *name == "Local" {
			return nil, apperr.Validation("tz", "An IANA time zone, like Europe/Lisbon.")
		}
		zone = given
	}
	if _, ok := sports.StartOfDay(req.Params.Date, zone); !ok {
		return nil, apperr.Validation("date", "A day as YYYY-MM-DD.")
	}
	schedule, err := s.Sports.Schedule(ctx, userID, req.Params.Date, zone)
	if err != nil {
		return nil, err
	}
	groups := make([]api.SportScheduleGroup, 0, len(schedule.Groups))
	for _, g := range schedule.Groups {
		events := make([]api.SportEvent, 0, len(g.Events))
		for _, e := range g.Events {
			events = append(events, sportEventDTO(e.Event, e.IsFavorite))
		}
		groups = append(groups, api.SportScheduleGroup{LeagueId: g.LeagueID, League: g.League, Sport: g.Sport, BadgeUrl: g.BadgeURL, Events: events})
	}
	return api.GetSportSchedule200JSONResponse{
		Date: schedule.Date, Groups: groups, Pending: schedule.Pending, Unavailable: schedule.Unavailable,
	}, nil
}

func (s *Server) GetSportEvent(ctx context.Context, req api.GetSportEventRequestObject) (api.GetSportEventResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if !isSportsProviderID(req.Id) {
		return nil, apperr.NotFound()
	}
	detail, err := s.Sports.Event(ctx, req.Id, userID)
	if errors.Is(err, sports.ErrSportsOff) {
		return nil, errSportsOff
	}
	if err != nil {
		return nil, err
	}
	if detail == nil {
		return nil, apperr.NotFound("No such event.")
	}
	return api.GetSportEvent200JSONResponse{
		Event: sportEventDTO(detail.Event, detail.IsFavorite), InYourCountry: sportBroadcastDTOs(detail.InYourCountry),
		Elsewhere: sportBroadcastDTOs(detail.Elsewhere), WatchCountryCode: detail.WatchCountryCode,
	}, nil
}

func (s *Server) ListSportFollows(ctx context.Context, _ api.ListSportFollowsRequestObject) (api.ListSportFollowsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	follows, err := s.Sports.Follows(ctx, userID)
	if err != nil {
		return nil, err
	}
	items := make([]api.SportEntity, 0, len(follows))
	for _, f := range follows {
		items = append(items, sportEntityDTO(f, map[string]bool{sportFollowKey(f): true}))
	}
	return api.ListSportFollows200JSONResponse{Items: items}, nil
}

func (s *Server) FollowSport(ctx context.Context, req api.FollowSportRequestObject) (api.FollowSportResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if !isSportsProviderID(req.ProviderId) {
		return nil, apperr.NotFound()
	}
	entity, err := s.Sports.Follow(ctx, sports.EntityKind(req.Kind), req.ProviderId, userID)
	switch {
	case errors.Is(err, sports.ErrSportsOff):
		return nil, errSportsOff
	case errors.Is(err, sports.ErrUnknownEntity):
		return nil, apperr.NotFound("The sports provider does not know that one.")
	case errors.Is(err, sports.ErrTooManyFollows):
		return nil, apperr.New(http.StatusConflict, "too_many_follows",
			"You can follow up to "+strconv.Itoa(sports.FollowLimit)+" in Sports. Unfollow one first.")
	case err != nil:
		return nil, err
	}
	return api.FollowSport200JSONResponse(sportEntityDTO(entity, map[string]bool{sportFollowKey(entity): true})), nil
}

func (s *Server) UnfollowSport(ctx context.Context, req api.UnfollowSportRequestObject) (api.UnfollowSportResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Sports.Unfollow(ctx, sports.EntityKind(req.Kind), req.ProviderId, userID); err != nil {
		return nil, err
	}
	return api.UnfollowSport204Response{}, nil
}

func (s *Server) GetSportSettings(ctx context.Context, _ api.GetSportSettingsRequestObject) (api.GetSportSettingsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	code, err := s.Sports.WatchCountry(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetSportSettings200JSONResponse{WatchCountryCode: code, Available: s.Sports.IsAvailable()}, nil
}

func (s *Server) SaveSportSettings(ctx context.Context, req api.SaveSportSettingsRequestObject) (api.SaveSportSettingsResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var chosen *string
	if req.Body.WatchCountryCode != nil {
		if code := strings.ToUpper(strings.Trim(*req.Body.WatchCountryCode, " \t")); code != "" {
			chosen = &code
		}
	}
	if chosen != nil && (len(*chosen) != 2 || !isASCIILetters(*chosen)) {
		return nil, apperr.Validation("watchCountryCode", "Two letters, as ISO 3166-1.")
	}
	if err := s.Sports.SaveWatchCountry(ctx, chosen, userID); err != nil {
		return nil, err
	}
	saved, err := s.Sports.WatchCountry(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.SaveSportSettings200JSONResponse{WatchCountryCode: saved, Available: s.Sports.IsAvailable()}, nil
}

func (s *Server) followedSports(ctx context.Context, userID uuid.UUID) (map[string]bool, error) {
	follows, err := s.Sports.Follows(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make(map[string]bool, len(follows))
	for _, f := range follows {
		out[sportFollowKey(f)] = true
	}
	return out, nil
}

func sportFollowKey(entity sports.Entity) string { return string(entity.Kind) + ":" + entity.ID }

// isSportsProviderID is a TheSportsDB id: 1 to 40 digits.
func isSportsProviderID(id string) bool {
	if n := core.Length(id); n < 1 || n > 40 {
		return false
	}
	for _, r := range id {
		if !unicode.IsNumber(r) {
			return false
		}
	}
	return true
}

func isASCIILetters(s string) bool {
	for _, r := range s {
		if r > unicode.MaxASCII || !unicode.IsLetter(r) {
			return false
		}
	}
	return true
}

func sportEntityDTOs(list []sports.Entity, following map[string]bool) []api.SportEntity {
	out := make([]api.SportEntity, 0, len(list))
	for _, e := range list {
		out = append(out, sportEntityDTO(e, following))
	}
	return out
}

func sportEntityDTO(e sports.Entity, following map[string]bool) api.SportEntity {
	return api.SportEntity{
		Kind: api.SportEntityKind(e.Kind), Id: e.ID, Name: e.Name, Sport: e.Sport, BadgeUrl: e.BadgeURL,
		Country: e.Country, LeagueId: e.LeagueID, TeamId: e.TeamID, TeamName: e.TeamName,
		Following: following[sportFollowKey(e)],
	}
}

func sportSideDTO(side *sports.Side) *api.SportSide {
	if side == nil {
		return nil
	}
	return &api.SportSide{Id: side.ID, Name: side.Name, BadgeUrl: side.BadgeURL, Score: side.Score}
}

func sportEventDTOs(list []sports.Event) []api.SportEvent {
	out := make([]api.SportEvent, 0, len(list))
	for _, e := range list {
		out = append(out, sportEventDTO(e, false))
	}
	return out
}

func sportEventDTO(e sports.Event, isFavorite bool) api.SportEvent {
	dto := api.SportEvent{
		Id: e.ID, Sport: e.Sport, Name: e.Name, LeagueId: e.LeagueID, League: e.League, LeagueBadgeUrl: e.LeagueBadgeURL,
		Home: sportSideDTO(e.Home), Away: sportSideDTO(e.Away), Day: e.Day, Status: api.SportEventStatus(e.Status),
		Progress: e.Progress, Venue: e.Venue, Round: e.Round, ImageUrl: e.ImageURL, IsFavorite: isFavorite,
	}
	if e.StartsAt != nil {
		t := apitime.From(*e.StartsAt)
		dto.StartsAt = &t
	}
	return dto
}

func sportBroadcastDTOs(list []sports.Broadcast) []api.SportBroadcast {
	out := make([]api.SportBroadcast, 0, len(list))
	for _, b := range list {
		out = append(out, api.SportBroadcast{Channel: b.Channel, Country: b.Country, LogoUrl: b.LogoURL})
	}
	return out
}
