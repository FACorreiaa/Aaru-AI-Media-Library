package sports

import (
	"aaru-go-api/internal/ratelimit"
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

var (
	// ErrSportsOff is sports being off on this server: no provider key.
	ErrSportsOff = errors.New("sports are off")
	// ErrUnknownEntity is the provider not knowing that league, team or player.
	ErrUnknownEntity = errors.New("unknown sport entity")
	// ErrTooManyFollows is the user following FollowLimit already.
	ErrTooManyFollows = errors.New("too many sport follows")
)

const (
	// FollowLimit is the most follows a user keeps.
	FollowLimit = 100
	// MaxScheduleLeagues is the leagues fetched for one day of the schedule.
	MaxScheduleLeagues = 30
	// ShareCallsPerMinute is share links' own slice of TheSportsDB's 100 calls a minute
	// (SHR-002), for cache misses only.
	ShareCallsPerMinute = 20
)

// Freshness of each kind of answer.
const (
	ttlLive       = 90 * time.Second
	ttlSchedule   = 30 * time.Minute
	ttlDay        = 15 * time.Minute
	ttlEvent      = 5 * time.Minute
	ttlEntity     = 24 * time.Hour
	ttlBroadcasts = 6 * time.Hour
)

// teamSports are sports where a player's team plays the fixtures; elsewhere (fighting, tennis,
// motorsport) a player's events are their league's or promotion's.
var teamSports = map[string]bool{
	"Soccer": true, "Basketball": true, "American Football": true, "Ice Hockey": true, "Baseball": true,
	"Rugby": true, "Australian Football": true, "Handball": true, "Volleyball": true, "Cricket": true,
	"Field Hockey": true, "Netball": true, "Water Polo": true,
}

// Suggested is the first-run picks (owner, 2026-10-24), by TheSportsDB league id.
func Suggested() []Entity {
	picks := [][3]string{
		{"4328", "English Premier League", "Soccer"},
		{"4335", "Spanish La Liga", "Soccer"},
		{"4332", "Italian Serie A", "Soccer"},
		{"4331", "German Bundesliga", "Soccer"},
		{"4334", "French Ligue 1", "Soccer"},
		{"4344", "Portuguese Primeira Liga", "Soccer"},
		{"4480", "UEFA Champions League", "Soccer"},
		{"4387", "NBA", "Basketball"},
		{"4391", "NFL", "American Football"},
		{"4443", "UFC", "Fighting"},
		{"4444", "WWE", "Fighting"},
	}
	out := make([]Entity, 0, len(picks))
	for _, p := range picks {
		id := p[0]
		out = append(out, Entity{Kind: KindLeague, ID: id, Name: p[1], Sport: p[2], LeagueID: &id})
	}
	return out
}

// Service is SPT-001…002 · the Sports tab. Off (Listing nil) every answer is unavailable.
type Service struct {
	Store   *Store
	Listing Listing
	// Now defaults to time.Now.
	Now func() time.Time
	// Patience is how long a request waits for cold answers before returning what it has, pending.
	Patience time.Duration
	// ShareLookups is share links' own slice of TheSportsDB's 100 calls a minute (SHR-002).
	ShareLookups *ratelimit.FixedWindow

	cache *Cache
}

// NewService builds the service; listing nil turns sports off.
func NewService(store *Store, listing Listing) *Service {
	return &Service{
		Store: store, Listing: listing, Now: time.Now, Patience: 3 * time.Second,
		ShareLookups: ratelimit.New(ShareCallsPerMinute, time.Minute), cache: NewCache(),
	}
}

func (s *Service) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

// IsAvailable is whether a sports provider is configured.
func (s *Service) IsAvailable() bool { return s.Listing != nil }

// MARK: Catalog

// Suggestions is the first-run picks, with their badges once known.
func (s *Service) Suggestions(ctx context.Context) []Entity {
	picks := Suggested()
	if s.Listing == nil {
		return picks
	}
	now := s.now()
	keys := make([]string, 0, len(picks))
	for _, pick := range picks {
		key := entityKey(KindLeague, pick.ID)
		keys = append(keys, key)
		id := pick.ID
		s.cache.prime(ctx, key, ttlEntity, now, func(ctx context.Context) (any, error) {
			return s.Listing.Lookup(ctx, KindLeague, id)
		})
	}
	s.cache.Settle(ctx, keys, s.Patience)
	for i := range picks {
		if found, ok := Cached[*Entity](s.cache, entityKey(KindLeague, picks[i].ID)); ok && found != nil {
			picks[i].BadgeURL = found.BadgeURL
		}
	}
	return picks
}

// Search is leagues, teams and players by name; kind empty searches all three.
func (s *Service) Search(ctx context.Context, query string, kind EntityKind) ([]Entity, error) {
	if s.Listing == nil {
		return nil, ErrSportsOff
	}
	slug := strings.Join(strings.Fields(strings.ToLower(query)), " ")
	kinds := []EntityKind{KindLeague, KindTeam, KindPlayer}
	if kind != "" {
		kinds = []EntityKind{kind}
	}
	now := s.now()
	byKind := make([][]Entity, len(kinds))
	var wg sync.WaitGroup
	for i, k := range kinds {
		wg.Go(func() {
			found, _ := Value(ctx, s.cache, "search:"+string(k)+":"+slug, ttlEntity, now, func(ctx context.Context) ([]Entity, error) {
				return s.Listing.Search(ctx, k, slug)
			})
			byKind[i] = found
		})
	}
	wg.Wait()
	out := []Entity{}
	for _, found := range byKind {
		out = append(out, found...)
	}
	return out, nil
}

// MARK: Follows

// Follows is the user's followed entities, oldest first.
func (s *Service) Follows(ctx context.Context, userID uuid.UUID) ([]Entity, error) {
	follows, err := s.Store.Follows(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]Entity, 0, len(follows))
	for _, f := range follows {
		out = append(out, f.Entity)
	}
	return out, nil
}

// Follow follows by the provider's id, after looking it up: the name, sport, badge and (for a
// team or player) league are kept so the list renders while the provider is down.
func (s *Service) Follow(ctx context.Context, kind EntityKind, id string, userID uuid.UUID) (Entity, error) {
	if s.Listing == nil {
		return Entity{}, ErrSportsOff
	}
	now := s.now()
	found := s.lookup(ctx, kind, id, now)
	if found == nil {
		return Entity{}, ErrUnknownEntity
	}
	entity := *found
	if kind == KindPlayer && entity.TeamID != nil {
		// A player's fixtures come from their team, or (a fighter) the team's league.
		team := s.lookup(ctx, KindTeam, *entity.TeamID, now)
		entity.LeagueID = nil
		if team != nil {
			entity.LeagueID = team.LeagueID
			if entity.TeamName == nil {
				name := team.Name
				entity.TeamName = &name
			}
		}
	}
	ok, err := s.Store.Follow(ctx, entity, userID, FollowLimit, now)
	if err != nil {
		return Entity{}, err
	}
	if !ok {
		return Entity{}, ErrTooManyFollows
	}
	return entity, nil
}

// Unfollow forgets a follow.
func (s *Service) Unfollow(ctx context.Context, kind EntityKind, id string, userID uuid.UUID) error {
	return s.Store.Unfollow(ctx, kind, id, userID)
}

// WatchCountry is the user's "Where to watch" country, nil when never chosen.
func (s *Service) WatchCountry(ctx context.Context, userID uuid.UUID) (*string, error) {
	return s.Store.WatchCountry(ctx, userID)
}

// SaveWatchCountry saves or clears the "Where to watch" country.
func (s *Service) SaveWatchCountry(ctx context.Context, code *string, userID uuid.UUID) error {
	return s.Store.SaveWatchCountry(ctx, code, userID, s.now())
}
