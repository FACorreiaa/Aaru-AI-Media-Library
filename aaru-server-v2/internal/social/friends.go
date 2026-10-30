package social

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"context"
	"time"

	"github.com/google/uuid"
)

// What friends see of each other (FriendService.swift; SOC-001 settings, SOC-003 minimal).
// Friends only: anyone else, and a block either way, is the same 404 as a handle nobody holds.
// A friend who hides their library shows only their name.

const (
	// ShelfLimit is how many titles each shelf row shows.
	ShelfLimit = 12
	// ActivityWindow is how far back the activity feed reaches.
	ActivityWindow = 14 * 24 * time.Hour
	// ActivityPage is one page of the feed.
	ActivityPage = 40
)

// Achievements are a friend's level and badges.
type Achievements struct {
	Level  int
	Badges []gamification.EarnedBadge
}

// FriendProfile is a friend's profile as the viewer may see it.
type FriendProfile struct {
	User         User
	FriendsSince time.Time
	// Sharing is false when the friend hides their library: then only the header is shown.
	Sharing bool
	Shelf   *FriendShelf
	// Titles are every title the shelf names, by id.
	Titles map[uuid.UUID]core.Title
	// Achievements are nil when the friend hides them (independent of Sharing).
	Achievements *Achievements
	// Favorites are their top 10s (FAV-001); nil when they hide their library.
	Favorites *Favorites
	// Email is theirs, only while they share it (SOC-001b). Independent of Sharing.
	Email *string
}

// ActivityFeed is activity rows with the people, titles and reactions they name.
type ActivityFeed struct {
	Items     []FriendActivity
	Reactions map[ActivityKey]ReactionSummary
	People    map[uuid.UUID]User
	Titles    map[uuid.UUID]core.Title
}

// Settings are the viewer's social switches.
func (s *Service) Settings(ctx context.Context, viewer uuid.UUID) (Settings, error) {
	return s.Store.Settings(ctx, viewer)
}

// SaveSettings replaces the viewer's switches.
func (s *Service) SaveSettings(ctx context.Context, settings Settings, viewer uuid.UUID) (Settings, error) {
	if err := s.Store.SaveSettings(ctx, viewer, settings); err != nil {
		return Settings{}, err
	}
	return settings, nil
}

// FriendProfile is a friend's profile, or ErrNoSuchUser for anyone who is not a friend.
func (s *Service) FriendProfile(ctx context.Context, friend, viewer uuid.UUID) (FriendProfile, error) {
	if friend == viewer {
		return FriendProfile{}, ErrNoSuchUser
	}
	blocked, err := s.Store.IsBlocked(ctx, viewer, friend)
	if err != nil {
		return FriendProfile{}, err
	}
	if blocked {
		return FriendProfile{}, ErrNoSuchUser
	}
	since, err := s.Store.FriendsSince(ctx, viewer, friend)
	if err != nil {
		return FriendProfile{}, err
	}
	if since == nil {
		return FriendProfile{}, ErrNoSuchUser
	}
	user, err := s.Store.User(ctx, friend)
	if err != nil {
		return FriendProfile{}, err
	}
	if user == nil {
		return FriendProfile{}, ErrNoSuchUser
	}
	profile := FriendProfile{User: *user, FriendsSince: *since, Titles: map[uuid.UUID]core.Title{}}
	if s.Gamification != nil {
		level, badges, ok, err := s.Gamification.FriendAchievements(ctx, friend)
		if err != nil {
			return FriendProfile{}, err
		}
		if ok {
			profile.Achievements = &Achievements{Level: level, Badges: badges}
		}
	}
	settings, err := s.Store.Settings(ctx, friend)
	if err != nil {
		return FriendProfile{}, err
	}
	if profile.Email, err = s.sharedEmail(ctx, friend, settings); err != nil {
		return FriendProfile{}, err
	}
	if !settings.ShareLibraryWithFriends {
		return profile, nil
	}
	shelf, err := s.Store.Shelf(ctx, friend, viewer, ShelfLimit)
	if err != nil {
		return FriendProfile{}, err
	}
	favorites, err := s.Favorites(ctx, friend)
	if err != nil {
		return FriendProfile{}, err
	}
	var ids []uuid.UUID
	for _, item := range shelf.Watching {
		ids = append(ids, item.TitleID)
	}
	for _, item := range shelf.Finished {
		ids = append(ids, item.TitleID)
	}
	ids = append(append(ids, shelf.BothWant...), shelf.TheyLoved...)
	if profile.Titles, err = s.titles(ctx, ids); err != nil {
		return FriendProfile{}, err
	}
	profile.Sharing = true
	profile.Shelf = &shelf
	profile.Favorites = &favorites
	return profile, nil
}

// sharedEmail is a friend's email while they share it; never an Apple relay address, which
// friends cannot write to.
func (s *Service) sharedEmail(ctx context.Context, friend uuid.UUID, settings Settings) (*string, error) {
	if !settings.ShareEmailWithFriends {
		return nil, nil
	}
	p, found, err := s.Profiles.Profile(ctx, friend)
	if err != nil {
		return nil, err
	}
	if !found || !p.EmailShareable() {
		return nil, nil
	}
	return p.Email, nil
}

// Activity is your and your friends' last two weeks, newest first, one page at a time.
func (s *Service) Activity(ctx context.Context, viewer uuid.UUID, before *time.Time) (ActivityFeed, error) {
	now := s.now()
	until := now
	if before != nil {
		until = *before
	}
	items, err := s.Store.Activity(ctx, viewer, now.Add(-ActivityWindow), until, ActivityPage)
	if err != nil {
		return ActivityFeed{}, err
	}
	everyone, err := s.Store.Friends(ctx, viewer)
	if err != nil {
		return ActivityFeed{}, err
	}
	own, err := s.Store.User(ctx, viewer)
	if err != nil {
		return ActivityFeed{}, err
	}
	if own != nil {
		everyone = append(everyone, *own)
	}
	people := map[uuid.UUID]User{}
	for _, u := range everyone {
		if _, seen := people[u.ID]; !seen {
			people[u.ID] = u
		}
	}
	// A friend without a handle has no social identity yet; their rows wait until they claim one.
	shown := make([]FriendActivity, 0, len(items))
	keys := make([]ActivityKey, 0, len(items))
	ids := make([]uuid.UUID, 0, len(items))
	for _, item := range items {
		if _, ok := people[item.Friend]; ok {
			shown = append(shown, item)
			keys = append(keys, ActivityKey{Owner: item.Friend, TitleID: item.TitleID, Day: item.Day})
			ids = append(ids, item.TitleID)
		}
	}
	reactions, err := s.Store.ReactionsOn(ctx, keys, viewer)
	if err != nil {
		return ActivityFeed{}, err
	}
	titles, err := s.titles(ctx, ids)
	if err != nil {
		return ActivityFeed{}, err
	}
	return ActivityFeed{Items: shown, Reactions: reactions, People: people, Titles: titles}, nil
}
