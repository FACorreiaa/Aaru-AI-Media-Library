package sports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/provider"
	"context"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/text/collate"
	"golang.org/x/text/language"
)

// SPT-002 · what the Sports tab shows: each favorite's live, next and last, one local day of
// fixtures, and one event with where to watch it.

// Favorite is one follow with what is live, next and last.
type Favorite struct {
	Entity Entity
	Live   []Event
	Next   *Event
	Last   *Event
	// Pending is still being fetched; ask again in a few seconds.
	Pending bool
}

// Favorites is every follow's line.
type Favorites struct {
	Items       []Favorite
	Unavailable bool
}

// ScheduledEvent is one event of a day.
type ScheduledEvent struct {
	Event Event
	// IsFavorite: a followed team (or player's team) plays in it.
	IsFavorite bool
}

// ScheduleGroup is one league's events of a day.
type ScheduleGroup struct {
	LeagueID *string
	League   string
	Sport    string
	BadgeURL *string
	Events   []ScheduledEvent
}

// Schedule is one local day.
type Schedule struct {
	Date        string
	Groups      []ScheduleGroup
	Pending     bool
	Unavailable bool
}

// EventDetail is one event with where to watch it.
type EventDetail struct {
	Event            Event
	IsFavorite       bool
	InYourCountry    []Broadcast
	Elsewhere        []Broadcast
	WatchCountryCode *string
}

// MARK: Favorites

// Favorites is each followed league, team and player with what is live, next and last. Cold
// answers get Patience; the rest come back pending and are ready on the next ask.
func (s *Service) Favorites(ctx context.Context, userID uuid.UUID) (Favorites, error) {
	follows, err := s.Follows(ctx, userID)
	if err != nil {
		return Favorites{}, err
	}
	if s.Listing == nil {
		items := make([]Favorite, 0, len(follows))
		for _, f := range follows {
			items = append(items, Favorite{Entity: f, Live: []Event{}})
		}
		return Favorites{Items: items, Unavailable: true}, nil
	}
	now := s.now()
	sources := make([]*source, len(follows))
	keys := []string{liveKey}
	s.primeLive(ctx, now)
	for i, f := range follows {
		sources[i] = sourceOf(f)
		if sources[i] != nil {
			keys = append(keys, s.primeSchedules(ctx, sources[i].kind, sources[i].id, now)...)
		}
	}
	s.cache.Settle(ctx, keys, s.Patience)
	live := s.liveByID()
	items := make([]Favorite, 0, len(follows))
	for i, f := range follows {
		items = append(items, s.favorite(f, sources[i], live, now))
	}
	return Favorites{Items: items}, nil
}

func (s *Service) favorite(entity Entity, src *source, live map[string]Event, now time.Time) Favorite {
	if src == nil {
		return Favorite{Entity: entity, Live: []Event{}}
	}
	nextKey, previousKey := scheduleKey(Next, src.kind, src.id), scheduleKey(Previous, src.kind, src.id)
	upcoming, _ := Cached[[]Event](s.cache, nextKey)
	past, _ := Cached[[]Event](s.cache, previousKey)
	hasNext, hasPrevious := s.cache.Has(nextKey), s.cache.Has(previousKey)
	var listed []Event
	for _, e := range append(slices.Clone(upcoming), past...) {
		listed = append(listed, Normalized(e, live, now))
	}
	concerns := func(e Event) bool {
		if src.kind == KindTeam {
			return e.Involves(src.id)
		}
		return e.LeagueID != nil && *e.LeagueID == src.id
	}
	// The listed copy carries badges and the round; the feed adds games the list missed.
	playing := []Event{}
	listedIDs := map[string]bool{}
	for _, e := range listed {
		listedIDs[e.ID] = true
		if e.Status == StatusLive && concerns(e) {
			playing = append(playing, e)
		}
	}
	for _, e := range live {
		if concerns(e) && !listedIDs[e.ID] {
			playing = append(playing, e)
		}
	}
	var next, last *Event
	for i := range listed {
		e := listed[i]
		if e.Status == StatusScheduled && (e.StartsAt == nil || e.StartsAt.After(now)) &&
			(next == nil || sortKey(e) < sortKey(*next)) {
			next = &e
		}
		if e.Status == StatusFinished && (last == nil || sortKey(*last) < sortKey(e)) {
			last = &e
		}
	}
	sort.SliceStable(playing, func(a, b int) bool { return sortKey(playing[a]) < sortKey(playing[b]) })
	return Favorite{Entity: entity, Live: playing, Next: next, Last: last, Pending: !hasNext || !hasPrevious}
}

// MARK: Schedule

// Schedule is one local day (date in loc): the events of followed leagues and of the leagues of
// followed teams and players, plus any followed team's game that day in another competition.
// Grouped by league, favorites first.
func (s *Service) Schedule(ctx context.Context, userID uuid.UUID, date string, loc *time.Location) (Schedule, error) {
	start, ok := StartOfDay(date, loc)
	if !ok {
		return Schedule{}, apperr.BadRequest()
	}
	end := start.Add(24 * time.Hour)
	follows, err := s.Follows(ctx, userID)
	if err != nil {
		return Schedule{}, err
	}
	if s.Listing == nil {
		return Schedule{Date: date, Groups: []ScheduleGroup{}, Unavailable: true}, nil
	}
	now := s.now()
	days := []string{start.UTC().Format(time.DateOnly)}
	if last := end.Add(-time.Second).UTC().Format(time.DateOnly); last != days[0] {
		days = append(days, last)
	}
	sort.Strings(days)
	events, pending := s.fixtures(ctx, follows, days, now)
	live := s.liveByID()
	seen := map[string]bool{}
	var today []Event
	for _, raw := range events {
		e := Normalized(raw, live, now)
		if seen[e.ID] {
			continue
		}
		seen[e.ID] = true
		if e.StartsAt != nil {
			if !e.StartsAt.Before(start) && e.StartsAt.Before(end) {
				today = append(today, e)
			}
		} else if e.Day == date {
			today = append(today, e)
		}
	}
	favoriteTeams := map[string]bool{}
	for _, f := range follows {
		if f.Kind == KindTeam {
			favoriteTeams[f.ID] = true
		} else if f.TeamID != nil {
			favoriteTeams[*f.TeamID] = true
		}
	}
	return Schedule{Date: date, Groups: Grouped(today, favoriteTeams), Pending: pending}, nil
}

// fixtures is the followed leagues' events on these UTC days and the followed teams' own
// fixtures, and whether some are still being fetched.
func (s *Service) fixtures(ctx context.Context, follows []Entity, days []string, now time.Time) ([]Event, bool) {
	var leagues []string
	for _, f := range follows {
		if f.LeagueID != nil && !slices.Contains(leagues, *f.LeagueID) {
			leagues = append(leagues, *f.LeagueID)
		}
	}
	var keys []string
	s.primeLive(ctx, now)
	for _, league := range leagues[:min(len(leagues), MaxScheduleLeagues)] {
		for _, day := range days {
			key := "day:" + league + ":" + day
			keys = append(keys, key)
			s.cache.prime(ctx, key, ttlDay, now, func(ctx context.Context) (any, error) {
				return s.Listing.Events(ctx, day, league)
			})
		}
	}
	for _, f := range follows {
		if src := sourceOf(f); src != nil && src.kind == KindTeam {
			keys = append(keys, s.primeSchedules(ctx, KindTeam, src.id, now)...)
		}
	}
	s.cache.Settle(ctx, append(slices.Clone(keys), liveKey), s.Patience)
	pending := false
	var events []Event
	for _, key := range keys {
		found, ok := Cached[[]Event](s.cache, key)
		if !ok {
			pending = true
			continue
		}
		events = append(events, found...)
	}
	return events, pending
}

// Grouped is events by league, each sorted by start; leagues with a favorite first, then by name.
func Grouped(events []Event, favoriteTeams map[string]bool) []ScheduleGroup {
	index := map[string]int{}
	var groups []ScheduleGroup
	for _, e := range events {
		key := e.Sport
		switch {
		case e.LeagueID != nil:
			key = *e.LeagueID
		case e.League != nil:
			key = *e.League
		}
		i, ok := index[key]
		if !ok {
			league := e.Sport
			if e.League != nil {
				league = *e.League
			}
			groups = append(groups, ScheduleGroup{LeagueID: e.LeagueID, League: league, Sport: e.Sport, BadgeURL: e.LeagueBadgeURL})
			i = len(groups) - 1
			index[key] = i
		}
		if groups[i].BadgeURL == nil {
			groups[i].BadgeURL = e.LeagueBadgeURL
		}
		favorite := false
		for team := range favoriteTeams {
			if e.Involves(team) {
				favorite = true
				break
			}
		}
		groups[i].Events = append(groups[i].Events, ScheduledEvent{Event: e, IsFavorite: favorite})
	}
	hasFavorite := func(g ScheduleGroup) bool {
		return slices.ContainsFunc(g.Events, func(e ScheduledEvent) bool { return e.IsFavorite })
	}
	for i := range groups {
		evs := groups[i].Events
		sort.SliceStable(evs, func(a, b int) bool { return sortKey(evs[a].Event) < sortKey(evs[b].Event) })
	}
	names := collate.New(language.English, collate.IgnoreCase)
	sort.SliceStable(groups, func(a, b int) bool {
		fa, fb := hasFavorite(groups[a]), hasFavorite(groups[b])
		if fa != fb {
			return fa
		}
		return names.CompareString(groups[a].League, groups[b].League) < 0
	})
	if groups == nil {
		groups = []ScheduleGroup{}
	}
	return groups
}

// MARK: Event

// Event is one event with its live line and where to watch it, split by the user's country.
// Nil when the provider has no such event.
func (s *Service) Event(ctx context.Context, id string, userID uuid.UUID) (*EventDetail, error) {
	if s.Listing == nil {
		return nil, ErrSportsOff
	}
	now := s.now()
	s.primeLive(ctx, now)
	channelsDone := make(chan []Broadcast, 1)
	go func() {
		channels, _ := Value(ctx, s.cache, "tv:"+id, ttlBroadcasts, now, func(ctx context.Context) ([]Broadcast, error) {
			return s.Listing.Broadcasts(ctx, id)
		})
		channelsDone <- channels
	}()
	found, _ := Value(ctx, s.cache, "event:"+id, ttlEvent, now, func(ctx context.Context) (*Event, error) {
		return s.Listing.Event(ctx, id)
	})
	if found == nil {
		return nil, nil
	}
	code, err := s.Store.WatchCountry(ctx, userID)
	if err != nil {
		return nil, err
	}
	follows, err := s.Follows(ctx, userID)
	if err != nil {
		return nil, err
	}
	s.cache.Settle(ctx, []string{liveKey}, s.Patience)
	live := s.liveByID()
	favorite := false
	for _, f := range follows {
		team := f.TeamID
		if f.Kind == KindTeam {
			team = &f.ID
		}
		if team != nil && found.Involves(*team) {
			favorite = true
			break
		}
	}
	names := map[string]bool{}
	if code != nil {
		names = countryNames(*code)
	}
	all := <-channelsDone
	mine, elsewhere := []Broadcast{}, []Broadcast{}
	for _, b := range all {
		if b.Country != nil && names[strings.ToLower(*b.Country)] {
			mine = append(mine, b)
		}
	}
	for _, b := range all {
		if !slices.ContainsFunc(mine, b.equal) {
			elsewhere = append(elsewhere, b)
		}
	}
	countryOf := func(b Broadcast) string {
		if b.Country == nil {
			return "~"
		}
		return *b.Country
	}
	sort.SliceStable(elsewhere, func(a, b int) bool {
		ca, cb := countryOf(elsewhere[a]), countryOf(elsewhere[b])
		if ca != cb {
			return ca < cb
		}
		return elsewhere[a].Channel < elsewhere[b].Channel
	})
	return &EventDetail{
		Event: Normalized(*found, live, now), IsFavorite: favorite, InYourCountry: mine, Elsewhere: elsewhere,
		WatchCountryCode: code,
	}, nil
}

// PublicEvent is one event with its live line, for anyone (SHR-002): no watch country, no
// follows, no user. It shares Event's cache entry, so a busy share link costs one provider call;
// a cache miss takes one of ShareCallsPerMinute. Nil when the provider has no such event or did
// not answer; ErrSportsOff when sports are off.
func (s *Service) PublicEvent(ctx context.Context, id string) (*Event, error) {
	if s.Listing == nil {
		return nil, ErrSportsOff
	}
	now := s.now()
	s.primeLive(ctx, now)
	found, _ := Value(ctx, s.cache, "event:"+id, ttlEvent, now, func(ctx context.Context) (*Event, error) {
		if !s.ShareLookups.Allow("share", now) {
			return nil, provider.NewError("thesportsdb", provider.KindUnavailable)
		}
		return s.Listing.Event(ctx, id)
	})
	if found == nil {
		return nil, nil
	}
	s.cache.Settle(ctx, []string{liveKey}, s.Patience)
	event := Normalized(*found, s.liveByID(), now)
	return &event, nil
}
