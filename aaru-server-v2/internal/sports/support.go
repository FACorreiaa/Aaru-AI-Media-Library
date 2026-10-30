package sports

import (
	"aaru-go-api/internal/core"
	"context"
	"strconv"
	"strings"
	"time"

	"golang.org/x/text/language"
	"golang.org/x/text/language/display"
)

// SPT-001 · the sources, cache keys and time and status rules the Sports answers share.

// source is where a followed entity's fixtures come from: a team's own, or a league's.
type source struct {
	kind EntityKind
	id   string
}

func sourceOf(entity Entity) *source {
	switch entity.Kind {
	case KindLeague:
		return &source{KindLeague, entity.ID}
	case KindTeam:
		return &source{KindTeam, entity.ID}
	case KindPlayer:
		if teamSports[entity.Sport] && entity.TeamID != nil {
			return &source{KindTeam, *entity.TeamID}
		}
		if entity.LeagueID != nil {
			return &source{KindLeague, *entity.LeagueID}
		}
	}
	return nil
}

const liveKey = "live:all"

func entityKey(kind EntityKind, id string) string { return "entity:" + string(kind) + ":" + id }

func scheduleKey(direction ScheduleDirection, kind EntityKind, id string) string {
	return "schedule:" + string(direction) + ":" + string(kind) + ":" + id
}

func (s *Service) lookup(ctx context.Context, kind EntityKind, id string, now time.Time) *Entity {
	found, _ := Value(ctx, s.cache, entityKey(kind, id), ttlEntity, now, func(ctx context.Context) (*Entity, error) {
		return s.Listing.Lookup(ctx, kind, id)
	})
	return found
}

// primeSchedules starts the next and previous schedules of a team or league; returns their keys.
func (s *Service) primeSchedules(ctx context.Context, kind EntityKind, id string, now time.Time) []string {
	keys := make([]string, 0, 2)
	for _, direction := range []ScheduleDirection{Next, Previous} {
		key := scheduleKey(direction, kind, id)
		keys = append(keys, key)
		s.cache.prime(ctx, key, ttlSchedule, now, func(ctx context.Context) (any, error) {
			return s.Listing.Schedule(ctx, direction, kind, id)
		})
	}
	return keys
}

func (s *Service) primeLive(ctx context.Context, now time.Time) {
	s.cache.prime(ctx, liveKey, ttlLive, now, func(ctx context.Context) (any, error) { return s.Listing.Live(ctx) })
}

func (s *Service) liveByID() map[string]Event {
	live, _ := Cached[[]Event](s.cache, liveKey)
	out := map[string]Event{}
	for _, e := range live {
		if _, seen := out[e.ID]; e.Status == StatusLive && !seen {
			out[e.ID] = e
		}
	}
	return out
}

func copySide(side *Side) *Side {
	if side == nil {
		return nil
	}
	c := *side
	return &c
}

// Normalized lays the live line over a listed event, and settles statuses the provider left
// behind: a past event with a score is finished; a "live" one from half a day ago is too.
func Normalized(event Event, live map[string]Event, now time.Time) Event {
	event.Home, event.Away = copySide(event.Home), copySide(event.Away)
	if line, ok := live[event.ID]; ok {
		event.Status = line.Status
		event.Progress = line.Progress
		if line.Home != nil && line.Home.Score != nil && event.Home != nil {
			event.Home.Score = line.Home.Score
		}
		if line.Away != nil && line.Away.Score != nil && event.Away != nil {
			event.Away.Score = line.Away.Score
		}
		return event
	}
	hasScore := (event.Home != nil && event.Home.Score != nil) || (event.Away != nil && event.Away.Score != nil)
	started := event.StartsAt != nil && event.StartsAt.Before(now)
	if event.Status == StatusScheduled && hasScore && started {
		event.Status = StatusFinished
	} else if event.Status == StatusLive && event.StartsAt != nil && now.Sub(*event.StartsAt) > 12*time.Hour {
		event.Status = StatusFinished
	}
	if event.Status != StatusLive {
		event.Progress = nil
	}
	return event
}

// sortKey orders events by start; an event without a time goes after that day's timed ones.
func sortKey(event Event) string {
	if event.StartsAt != nil {
		t := event.StartsAt.UTC()
		return t.Format(time.DateOnly) + t.Format("15:04:05") + "Z"
	}
	return event.Day + "~"
}

// StartOfDay is `YYYY-MM-DD` at 00:00 in loc; false for anything else.
func StartOfDay(date string, loc *time.Location) (time.Time, bool) {
	var parts []int
	for _, piece := range strings.Split(date, "-") {
		if piece == "" {
			continue
		}
		if n, err := strconv.Atoi(piece); err == nil {
			parts = append(parts, n)
		}
	}
	if core.Length(date) != 10 || len(parts) != 3 {
		return time.Time{}, false
	}
	day := time.Date(parts[0], time.Month(parts[1]), parts[2], 0, 0, 0, 0, loc)
	if day.Day() != parts[2] {
		return time.Time{}, false
	}
	return day, true
}

// countryNames is the names TheSportsDB may give a country, lowercased: the English name plus
// aliases.
func countryNames(code string) map[string]bool {
	names := map[string]bool{}
	if region, err := language.ParseRegion(code); err == nil {
		if name := display.English.Regions().Name(region); name != "" {
			names[strings.ToLower(name)] = true
		}
	}
	var aliases []string
	switch code {
	case "US":
		aliases = []string{"usa", "united states", "united states of america"}
	case "GB":
		aliases = []string{"united kingdom", "uk", "england", "scotland", "wales", "northern ireland"}
	case "IE":
		aliases = []string{"ireland"}
	case "KR":
		aliases = []string{"south korea", "korea"}
	case "AE":
		aliases = []string{"uae"}
	}
	for _, a := range aliases {
		names[a] = true
	}
	return names
}
