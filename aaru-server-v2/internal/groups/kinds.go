package groups

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Title channels and the spoiler guard (GRP-007), shelf channels (GRP-008) and watch parties
// (GRP-009), from GroupService+Kinds.swift. Nothing here writes to anyone's library but the
// viewer's own, through library.Service, journaled like any tap.

// Limits for the kinds.
const (
	MaxShelfItems    = 200
	MinCountdown     = 3
	MaxCountdown     = 60
	DefaultCountdown = 10
)

// Reactions a watch party carries. A fixed set keeps the socket from carrying free text.
var Reactions = map[string]bool{"😂": true, "😱": true, "😭": true, "❤️": true, "👏": true, "🔥": true}

// MemberProgress is one member's progress in a title channel's title.
type MemberProgress struct {
	User     User
	Progress *TitleProgress
}

// ChannelProgress is a title channel's header: its title, the viewer's progress, and members who
// share theirs.
type ChannelProgress struct {
	Title   core.Title
	Mine    *TitleProgress
	Members []MemberProgress
}

// UpdateMembership changes the viewer's own settings in a group: showing their progress in its
// title channels, and muting its mention alerts (GRP-012). A nil leaves that setting as it is.
func (s *Service) UpdateMembership(ctx context.Context, group uuid.UUID, share, muted *bool, viewer uuid.UUID) (Summary, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return Summary{}, err
	}
	if share != nil {
		if err := s.Store.SetShareProgress(ctx, group, viewer, *share); err != nil {
			return Summary{}, err
		}
		s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	}
	if muted != nil {
		// Nobody else sees a mute; only the viewer's other devices refresh.
		if err := s.Store.SetMuted(ctx, group, viewer, *muted); err != nil {
			return Summary{}, err
		}
		s.publish(ctx, Event{Type: EventGroupUpdated, Group: group}, []uuid.UUID{viewer})
	}
	summary, err := s.Store.Summary(ctx, group, viewer)
	if err != nil {
		return Summary{}, err
	}
	if summary == nil {
		return Summary{}, ErrNoSuchGroup
	}
	return *summary, nil
}

// TitleProgress is a title channel's title, the viewer's own progress, and the progress of
// members who share theirs in this group. Nobody else appears.
func (s *Service) TitleProgress(ctx context.Context, group, channel, viewer uuid.UUID) (ChannelProgress, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return ChannelProgress{}, err
	}
	found, err := s.requireChannel(ctx, group, channel)
	if err != nil {
		return ChannelProgress{}, err
	}
	notAbout := Invalid("channelId", "That channel is not about a title.")
	if found.TitleID == nil {
		return ChannelProgress{}, notAbout
	}
	title, err := s.Title(ctx, *found.TitleID)
	if err != nil {
		return ChannelProgress{}, err
	}
	if title == nil {
		return ChannelProgress{}, notAbout
	}
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return ChannelProgress{}, err
	}
	var sharing []Member
	for _, m := range members {
		if m.ShareProgress && m.User.ID != viewer {
			sharing = append(sharing, m)
		}
	}
	progress, err := Progress(ctx, s.q(), title.ID, append(memberIDs(sharing), viewer))
	if err != nil {
		return ChannelProgress{}, err
	}
	out := ChannelProgress{Title: *title, Mine: progressOf(progress, viewer), Members: make([]MemberProgress, len(sharing))}
	for i, m := range sharing {
		out.Members[i] = MemberProgress{User: m.User, Progress: progressOf(progress, m.User.ID)}
	}
	return out, nil
}

// MARK: Shelf

// ShelfEntry is a shelf item and its title.
type ShelfEntry struct {
	Item  ShelfItem
	Title core.Title
}

// Shelf is a shelf channel's titles; an item whose title is gone is left out.
func (s *Service) Shelf(ctx context.Context, group, channel, viewer uuid.UUID) ([]ShelfEntry, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return nil, err
	}
	if err := s.requireKind(ctx, KindShelf, group, channel); err != nil {
		return nil, err
	}
	items, err := s.Store.ShelfItems(ctx, channel, viewer)
	if err != nil {
		return nil, err
	}
	ids := make([]uuid.UUID, len(items))
	for i, it := range items {
		ids[i] = it.TitleID
	}
	titles, err := s.titles(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := []ShelfEntry{}
	for _, it := range items {
		if t, ok := titles[it.TitleID]; ok {
			out = append(out, ShelfEntry{Item: it, Title: t})
		}
	}
	return out, nil
}

// AddToShelf: any member adds a title. Adding one already there changes nothing.
func (s *Service) AddToShelf(ctx context.Context, group, channel uuid.UUID, ref core.MediaRef, viewer uuid.UUID) (core.Title, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return core.Title{}, err
	}
	if err := s.requireKind(ctx, KindShelf, group, channel); err != nil {
		return core.Title{}, err
	}
	items, err := s.Store.ShelfItems(ctx, channel, viewer)
	if err != nil {
		return core.Title{}, err
	}
	if len(items) >= MaxShelfItems {
		return core.Title{}, Invalid("title", fmt.Sprintf("A shelf holds %d titles.", MaxShelfItems))
	}
	title, err := s.Catalog.Resolver().Resolve(ctx, ref, nil)
	if err != nil {
		return core.Title{}, err
	}
	added, err := s.Store.AddShelfItem(ctx, channel, title.ID, viewer, s.now())
	if err != nil {
		return core.Title{}, err
	}
	if added {
		s.announce(ctx, Event{Type: EventShelfUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	}
	return title, nil
}

// RemoveFromShelf: any member removes a title.
func (s *Service) RemoveFromShelf(ctx context.Context, group, channel, title, viewer uuid.UUID) error {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return err
	}
	if err := s.requireKind(ctx, KindShelf, group, channel); err != nil {
		return err
	}
	removed, err := s.Store.RemoveShelfItem(ctx, channel, title)
	if err != nil {
		return err
	}
	if !removed {
		return apperr.NotFound("That title is not on this shelf.")
	}
	s.announce(ctx, Event{Type: EventShelfUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return nil
}

// MARK: Watch parties

// Party is a watch party and its title.
type Party struct {
	Party WatchParty
	Title core.Title
}

var errNoParty = apperr.NotFound("No watch party is open here.")

// Party is the channel's newest party with its title, or nil before the first one.
func (s *Service) Party(ctx context.Context, group, channel, viewer uuid.UUID) (*Party, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return nil, err
	}
	if err := s.requireKind(ctx, KindWatch, group, channel); err != nil {
		return nil, err
	}
	party, err := s.Store.LatestParty(ctx, channel)
	if err != nil || party == nil {
		return nil, err
	}
	title, err := s.Title(ctx, party.TitleID)
	if err != nil || title == nil {
		return nil, err
	}
	return &Party{Party: *party, Title: *title}, nil
}

// OpenParty opens a party in the lobby. A show needs the episode; a channel holds one open party.
func (s *Service) OpenParty(ctx context.Context, group, channel uuid.UUID, ref core.MediaRef, episode *EpisodePoint, viewer uuid.UUID) (Party, error) {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return Party{}, err
	}
	if err := s.requireKind(ctx, KindWatch, group, channel); err != nil {
		return Party{}, err
	}
	host, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return Party{}, err
	}
	title, err := s.Catalog.Resolver().Resolve(ctx, ref, nil)
	if err != nil {
		return Party{}, err
	}
	party := WatchParty{ID: uuid.New(), ChannelID: channel, TitleID: title.ID, CreatedBy: &host, CreatedAt: s.now()}
	if title.Type == core.MediaShow {
		if episode == nil || episode.Season < 0 || episode.Episode < 1 {
			return Party{}, Invalid("episode", "Pick the episode you are watching.")
		}
		party.Episode = episode
	}
	if err := s.Store.CreateParty(ctx, party); err != nil {
		return Party{}, err
	}
	s.announce(ctx, Event{Type: EventWatchUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return s.requireParty(ctx, group, channel, viewer, false)
}

// SetReady marks the viewer ready, or not, in the open party.
func (s *Service) SetReady(ctx context.Context, group, channel uuid.UUID, ready bool, viewer uuid.UUID) (Party, error) {
	found, err := s.requireParty(ctx, group, channel, viewer, true)
	if err != nil {
		return Party{}, err
	}
	if err := s.Store.SetReady(ctx, found.Party.ID, viewer, ready); err != nil {
		return Party{}, err
	}
	s.announce(ctx, Event{Type: EventWatchUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return s.requireParty(ctx, group, channel, viewer, false)
}

// StartCountdown starts the countdown. The host or an admin does; every client counts down to the
// same server time.
func (s *Service) StartCountdown(ctx context.Context, group, channel uuid.UUID, seconds *int, viewer uuid.UUID) (Party, error) {
	found, err := s.requireParty(ctx, group, channel, viewer, true)
	if err != nil {
		return Party{}, err
	}
	if err := s.requireHost(ctx, found.Party, group, viewer); err != nil {
		return Party{}, err
	}
	n := DefaultCountdown
	if seconds != nil {
		n = *seconds
	}
	if n < MinCountdown || n > MaxCountdown {
		return Party{}, Invalid("countdownSeconds", "Count down from 3 to 60 seconds.")
	}
	if err := s.Store.StartParty(ctx, found.Party.ID, s.now().Add(time.Duration(n)*time.Second)); err != nil {
		return Party{}, err
	}
	// Everyone ready when it starts was at the party (GAM-001), once per party.
	if s.Gamification != nil {
		for _, member := range found.Party.Ready {
			s.Gamification.RoomAttended(ctx, member.ID, found.Party.ID)
		}
	}
	s.announce(ctx, Event{Type: EventWatchUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return s.requireParty(ctx, group, channel, viewer, false)
}

// EndParty ends the open party (the host or an admin).
func (s *Service) EndParty(ctx context.Context, group, channel, viewer uuid.UUID) (Party, error) {
	found, err := s.requireParty(ctx, group, channel, viewer, true)
	if err != nil {
		return Party{}, err
	}
	if err := s.requireHost(ctx, found.Party, group, viewer); err != nil {
		return Party{}, err
	}
	if err := s.Store.EndParty(ctx, found.Party.ID, s.now()); err != nil {
		return Party{}, err
	}
	s.announce(ctx, Event{Type: EventWatchUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return s.requireParty(ctx, group, channel, viewer, false)
}

// MarkWatched marks the party's episode, or the film or book, watched in the viewer's own library
// only: the same journaled writes as ticking it on the title page.
func (s *Service) MarkWatched(ctx context.Context, group, channel, viewer uuid.UUID) error {
	found, err := s.requireParty(ctx, group, channel, viewer, false)
	if err != nil {
		return err
	}
	if found.Party.StartsAt == nil {
		return Invalid("party", "The party has not started yet.")
	}
	if s.Gamification != nil {
		s.Gamification.RoomAttended(ctx, viewer, found.Party.ID)
	}
	id := found.Title.ID
	ref := core.MediaRef{TitleID: &id, Type: found.Title.Type}
	if ep := found.Party.Episode; ep != nil {
		status := core.StatusInProgress
		entry, err := s.Library.Add(ctx, ref, &status, viewer, library.UserCaller)
		if err != nil {
			return err
		}
		key, err := core.NewEpisodeKey(ep.Season, ep.Episode)
		if err != nil {
			return err
		}
		_, err = s.Library.SetEpisode(ctx, entry.Item.ID, viewer, key, true, library.UserCaller)
		return err
	}
	status := core.StatusFinished
	entry, err := s.Library.Add(ctx, ref, &status, viewer, library.UserCaller)
	if err != nil {
		return err
	}
	if entry.Item.Status != core.StatusFinished {
		_, err = s.Library.Patch(ctx, entry.Item.ID, viewer, library.ItemPatch{Status: &status}, library.UserCaller)
	}
	return err
}

// React passes a watch-party reaction from the socket to the other members. Anything outside the
// set is dropped.
func (s *Service) React(ctx context.Context, group, channel uuid.UUID, emoji string, viewer uuid.UUID) error {
	if !Reactions[emoji] {
		return nil
	}
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return err
	}
	if err := s.requireKind(ctx, KindWatch, group, channel); err != nil {
		return err
	}
	user, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return err
	}
	s.announce(ctx, Event{Type: EventWatchReaction, Group: group, Channel: channel, User: &user, Emoji: emoji}, group, viewer)
	return nil
}

// MARK: Rules

func (s *Service) requireKind(ctx context.Context, kind ChannelKind, group, channel uuid.UUID) error {
	found, err := s.requireChannel(ctx, group, channel)
	if err != nil {
		return err
	}
	if found.Kind != kind {
		return Invalid("channelId", fmt.Sprintf("That is not a %s channel.", kind))
	}
	return nil
}

func (s *Service) requireParty(ctx context.Context, group, channel, viewer uuid.UUID, open bool) (Party, error) {
	found, err := s.Party(ctx, group, channel, viewer)
	if err != nil {
		return Party{}, err
	}
	if found == nil || (open && found.Party.EndedAt != nil) {
		return Party{}, errNoParty
	}
	return *found, nil
}

func (s *Service) requireHost(ctx context.Context, party WatchParty, group, viewer uuid.UUID) error {
	role, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	if (party.CreatedBy == nil || party.CreatedBy.ID != viewer) && !role.Manages() {
		return Forbidden("Only whoever opened the party, or an admin, can do that.")
	}
	return nil
}
