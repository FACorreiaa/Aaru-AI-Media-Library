package groups

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/safe"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Title channels and the spoiler guard (GRP-007), shelf channels (GRP-008) and watch parties
// (GRP-009), from GroupService+Kinds.swift. Every library write here goes through library.Service
// as the member's own journaled action. All but one are the viewer's own tap; the exception is the
// end of a party, which marks the title for each member who joined it and left "Mark it for me"
// on (ROOM-005, owner 2026-11-10).

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

// AddToShelf lets any member add a title. Adding one already there changes nothing.
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

// RemoveFromShelf lets any member remove a title.
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

// OpenParty opens a party in the lobby. A show needs the episode; a manga can carry a chapter and
// volume and a book a page (ROOM-005). A target that does not fit the title's kind is left out.
// A channel holds one open party.
func (s *Service) OpenParty(ctx context.Context, group, channel uuid.UUID, ref core.MediaRef, target PartyTarget, viewer uuid.UUID) (Party, error) {
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
	switch title.Type {
	case core.MediaShow:
		episode := target.Episode
		if episode == nil || episode.Season < 0 || episode.Episode < 1 {
			return Party{}, Invalid("episode", "Pick the episode you are watching.")
		}
		party.Episode = episode
	case core.MediaManga:
		if r := target.Reading; r != nil && (r.Chapter != nil || r.Volume != nil) {
			if _, err := core.NewMangaProgress(r.Chapter, r.Volume); err != nil {
				return Party{}, err
			}
			party.Reading = &ReadingPoint{Chapter: r.Chapter, Volume: r.Volume}
		}
	case core.MediaBook:
		if r := target.Reading; r != nil && r.Page != nil {
			if _, err := core.NewBookProgress(r.Page, nil); err != nil {
				return Party{}, err
			}
			party.Reading = &ReadingPoint{Page: r.Page}
		}
	default:
	}
	if err := s.Store.CreateParty(ctx, party); err != nil {
		return Party{}, err
	}
	s.announce(ctx, Event{Type: EventWatchUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return s.requireParty(ctx, group, channel, viewer, false)
}

// SetReady marks the viewer ready, or not, in the open party. Being ready is joining: the end of
// the party marks the title for them unless autoMark says no (ROOM-005). A nil autoMark keeps
// what they chose before, on for a first join.
func (s *Service) SetReady(ctx context.Context, group, channel uuid.UUID, ready bool, autoMark *bool, viewer uuid.UUID) (Party, error) {
	found, err := s.requireParty(ctx, group, channel, viewer, true)
	if err != nil {
		return Party{}, err
	}
	if err := s.Store.SetReady(ctx, found.Party.ID, viewer, ready, autoMark); err != nil {
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

// EndParty ends the open party (the host or an admin). When its countdown had started, the end
// marks the title for every member who joined and left "Mark it for me" on (ROOM-005).
func (s *Service) EndParty(ctx context.Context, group, channel, viewer uuid.UUID) (Party, error) {
	found, err := s.requireParty(ctx, group, channel, viewer, true)
	if err != nil {
		return Party{}, err
	}
	if err := s.requireHost(ctx, found.Party, group, viewer); err != nil {
		return Party{}, err
	}
	ended, err := s.Store.EndParty(ctx, found.Party.ID, s.now())
	if err != nil {
		return Party{}, err
	}
	if ended && found.Party.StartsAt != nil {
		// The party is over whatever happens to the request: finish the check-off for everyone.
		s.markJoined(context.WithoutCancel(ctx), group, found)
	}
	s.announce(ctx, Event{Type: EventWatchUpdated, Group: group, Channel: channel}, group, uuid.Nil)
	return s.requireParty(ctx, group, channel, viewer, false)
}

// markJoined is the check-off at the end: one write per joined member who left "Mark it for me"
// on and is not marked yet. Each is that member's own action. One member's failure is logged and
// never stops the others.
func (s *Service) markJoined(ctx context.Context, group uuid.UUID, found Party) {
	for _, member := range found.Party.Ready {
		joined := found.Party.Joined[member.ID]
		if !joined.AutoMark || joined.MarkedAt != nil {
			continue
		}
		err := safe.Step(func() error {
			// Someone who left the group since joining is no longer in the party.
			if _, err := s.Role(ctx, group, member.ID); err != nil {
				return nil //nolint:nilerr // not a member any more: nothing to mark
			}
			action, skipped, err := s.markFor(ctx, member.ID, found, true)
			if err != nil || skipped {
				return err
			}
			if s.Gamification != nil {
				s.Gamification.RoomAttended(ctx, member.ID, found.Party.ID)
			}
			return s.Store.SetMarked(ctx, found.Party.ID, member.ID, s.now(), action)
		})
		if err != nil {
			s.log().WarnContext(ctx, "mark party for member", "party", found.Party.ID, "user", member.ID, "error", err)
		}
	}
}

// MarkWatched marks the party's episode, chapter, page, film or book in the viewer's own library:
// the same journaled writes as ticking it on the title page. It is the tap for a member who
// switched "Mark it for me" off or did not join; for one the end already marked, it does nothing.
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
	joined, in := found.Party.Joined[viewer]
	if in && joined.MarkedAt != nil {
		return nil
	}
	action, _, err := s.markFor(ctx, viewer, found, false)
	if err != nil || !in {
		return err
	}
	return s.Store.SetMarked(ctx, found.Party.ID, viewer, s.now(), action)
}

// partyCaller is the end of a party writing for a member who joined: their own say, so it holds
// like a tap, and the journal names where it came from ("Watch party: marked …").
func partyCaller(kind core.MediaType) library.Caller {
	name := "Watch party"
	if kind == core.MediaBook || kind == core.MediaManga {
		name = "Reading session"
	}
	return library.Caller{Actor: library.ActorUser, ByHand: true, AgentName: &name}
}

// markFor writes the party's target into one member's library and returns the action Undo takes
// back (nil when the library already said so).
//
// auto is the end of the party writing for a member who joined, and it is careful where a tap
// need not be: it skips an item the member dropped or finished, and a reading position at or past
// the party's, so it never moves anyone backward.
func (s *Service) markFor(ctx context.Context, user uuid.UUID, found Party, auto bool) (action *uuid.UUID, skipped bool, err error) {
	caller := library.UserCaller
	if auto {
		caller = partyCaller(found.Title.Type)
		existing, err := s.Library.ItemForTitle(ctx, user, found.Title.ID)
		if err != nil {
			return nil, false, err
		}
		if existing != nil && (existing.Item.Status == core.StatusDropped || existing.Item.Status == core.StatusFinished) {
			return nil, true, nil
		}
	}
	id := found.Title.ID
	ref := core.MediaRef{TitleID: &id, Type: found.Title.Type}
	inProgress, finished := core.StatusInProgress, core.StatusFinished
	p := found.Party
	if p.Episode != nil {
		entry, err := s.Library.Add(ctx, ref, &inProgress, user, caller)
		if err != nil {
			return nil, false, err
		}
		key, err := core.NewEpisodeKey(p.Episode.Season, p.Episode.Episode)
		if err != nil {
			return nil, false, err
		}
		if auto {
			watched, err := s.Library.Store.Watched(ctx, entry.Item.ID)
			if err != nil {
				return nil, false, err
			}
			if watched[key] {
				return nil, true, nil
			}
		}
		write, err := s.Library.SetEpisode(ctx, entry.Item.ID, user, key, true, caller)
		if err != nil {
			return nil, false, err
		}
		return &write.Action.ID, false, nil
	}
	// Anything else is added first, so the mark is its own action and Undo takes back the mark,
	// not the title.
	entry, err := s.Library.Add(ctx, ref, nil, user, caller)
	if err != nil {
		return nil, false, err
	}
	patch := library.ItemPatch{Status: &finished}
	if r := p.Reading; r != nil {
		if auto && readPast(entry, *r) {
			return nil, true, nil
		}
		patch = library.ItemPatch{MangaChapter: r.Chapter, MangaVolume: r.Volume, BookPage: r.Page}
		if entry.Item.Status == core.StatusWishlist {
			patch.Status = &inProgress
		}
	}
	write, err := s.Library.PatchWrite(ctx, entry.Item.ID, user, patch, caller)
	if err != nil {
		return nil, false, err
	}
	if write.Action == nil {
		return nil, false, nil
	}
	return &write.Action.ID, false, nil
}

// readPast is whether a member's reading position is already at or past the party's. A book kept
// by percent cannot be compared with a page, so it is left alone.
func readPast(entry library.Entry, to ReadingPoint) bool {
	if m := entry.MangaProgress; m != nil {
		switch {
		case to.Chapter != nil && m.Chapter != nil:
			return *m.Chapter >= *to.Chapter
		case to.Chapter == nil && to.Volume != nil && m.Volume != nil:
			return *m.Volume >= *to.Volume
		}
	}
	if b := entry.BookProgress; b != nil && to.Page != nil {
		return b.Percent != nil || (b.Page != nil && *b.Page >= *to.Page)
	}
	return false
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
