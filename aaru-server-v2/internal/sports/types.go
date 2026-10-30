// Package sports is SPT-001…002 (Sources/App/Sports): the Sports tab. What the user follows,
// their fixtures, near-live scores, results and where to watch, from TheSportsDB. Lives only in
// Sports: it never writes the library, the journal, points or activity, and no agent tool reads
// it. Off (every answer unavailable) without a provider key.
package sports

import (
	"context"
	"time"
)

// EntityKind is what a user can follow in Sports: a league (or promotion: UFC, WWE), a team, or
// a player (a fighter or wrestler too). Catalog data by the provider's id; never a Title.
type EntityKind string

// The three kinds.
const (
	KindLeague EntityKind = "league"
	KindTeam   EntityKind = "team"
	KindPlayer EntityKind = "player"
)

// Valid is one of the three kinds.
func (k EntityKind) Valid() bool { return k == KindLeague || k == KindTeam || k == KindPlayer }

// Entity is one league, team or player as the sports provider lists it.
type Entity struct {
	Kind EntityKind
	ID   string
	Name string
	// Sport is the provider's sport name: "Soccer", "Basketball", "American Football", "Fighting".
	Sport    string
	BadgeURL *string
	Country  *string
	// LeagueID is a team's main league; a player's team's league once known.
	LeagueID *string
	// TeamID is a player's team. A fighter's "team" is their division, which belongs to the promotion.
	TeamID   *string
	TeamName *string
}

// EventStatus is where a sport event stands, from the provider's free-text status.
type EventStatus string

// The five statuses.
const (
	StatusScheduled EventStatus = "scheduled"
	StatusLive      EventStatus = "live"
	StatusFinished  EventStatus = "finished"
	StatusPostponed EventStatus = "postponed"
	StatusCancelled EventStatus = "cancelled"
)

// Side is one side of a match. Cards (a UFC or WWE event) have no sides.
type Side struct {
	ID       *string
	Name     string
	BadgeURL *string
	Score    *int
}

// Event is SPT-002 · one match, game, race or card. Catalog data for the Sports tab only: never a
// Title, never a library row, and kept no longer than the cache.
type Event struct {
	ID             string
	Sport          string
	Name           string
	LeagueID       *string
	League         *string
	LeagueBadgeURL *string
	Home           *Side
	Away           *Side
	// StartsAt is the exact start in UTC, when the provider has a time.
	StartsAt *time.Time
	// Day is the UTC day, `YYYY-MM-DD`.
	Day    string
	Status EventStatus
	// Progress is the live clock or period as the provider says it: "67", "HT", "Q3".
	Progress *string
	Venue    *string
	Round    *string
	ImageURL *string
}

// Involves is whether this event involves the team (as home or away).
func (e Event) Involves(teamID string) bool {
	return (e.Home != nil && e.Home.ID != nil && *e.Home.ID == teamID) ||
		(e.Away != nil && e.Away.ID != nil && *e.Away.ID == teamID)
}

// Broadcast is one channel showing an event, in one country.
type Broadcast struct {
	Channel string
	Country *string
	LogoURL *string
}

func equalPtr(a, b *string) bool {
	return (a == nil && b == nil) || (a != nil && b != nil && *a == *b)
}

func (b Broadcast) equal(o Broadcast) bool {
	return b.Channel == o.Channel && equalPtr(b.Country, o.Country) && equalPtr(b.LogoURL, o.LogoURL)
}

// ScheduleDirection is a team's or league's next or previous events.
type ScheduleDirection string

// The two directions.
const (
	Next     ScheduleDirection = "next"
	Previous ScheduleDirection = "previous"
)

// Listing is sports data from a provider (TheSportsDB today). Named for the job, not the vendor.
type Listing interface {
	// Search is up to ten matches by name.
	Search(ctx context.Context, kind EntityKind, query string) ([]Entity, error)
	// Lookup is nil when the provider does not know the id.
	Lookup(ctx context.Context, kind EntityKind, id string) (*Entity, error)
	// Schedule is a team's or league's next or previous events (kind is team or league).
	Schedule(ctx context.Context, direction ScheduleDirection, kind EntityKind, id string) ([]Event, error)
	// Events is a league's events on one UTC day (`YYYY-MM-DD`).
	Events(ctx context.Context, day, leagueID string) ([]Event, error)
	// Event is nil when the provider has no such event.
	Event(ctx context.Context, id string) (*Event, error)
	// Live is every event the provider follows live right now, all sports, with its clock and
	// score. Laid over listed events by id.
	Live(ctx context.Context) ([]Event, error)
	Broadcasts(ctx context.Context, eventID string) ([]Broadcast, error)
}

// Follow is a followed league, team or player, with what was known of it when followed so the
// list renders while the provider is down.
type Follow struct {
	Entity    Entity
	CreatedAt time.Time
}
