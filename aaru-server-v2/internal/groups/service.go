package groups

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/telemetry"
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
)

// Pusher sends one alert to a user's devices (push.UserPush).
type Pusher interface {
	Send(ctx context.Context, m push.Message, userID uuid.UUID)
}

// Service is groups, their members, invites, channels and messages (GroupService.swift).
//
// Friends-only by the owner's decision: you can invite only a friend, and nobody finds a group
// any other way. Messages are server-visible and labelled so in the clients.
type Service struct {
	Store  *Store
	Social Social
	// Events tells members' open sockets about each change after it commits (GRP-006).
	Events Publisher
	// Catalog resolves titles for title, shelf and watch channels.
	Catalog *catalog.Kit
	// Library ticks the tapper's own library from a watch party.
	Library      *library.Service
	Gamification *gamification.Service
	// AgentAvailable: `@aaru` answers here, a model is configured (GRP-010).
	AgentAvailable bool
	// Push sends mention and invite alerts (GRP-012); nil sends none.
	Push Pusher
	Log  *slog.Logger
	Now  func() time.Time
}

// New builds the service over a pool's store; events default to none.
func New(store *Store, kit *catalog.Kit, lib *library.Service, game *gamification.Service, log *slog.Logger) *Service {
	return &Service{
		Store: store, Social: Social{Q: store.Q}, Events: NoEvents{}, Catalog: kit, Library: lib,
		Gamification: game, Log: log,
	}
}

func (s *Service) q() *sqlc.Queries { return s.Store.Q }

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s *Service) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}

func (s *Service) publish(ctx context.Context, e Event, to []uuid.UUID) {
	if s.Events != nil {
		s.Events.Publish(ctx, e, to)
	}
}

// Detail is everything a member's group screen shows.
type Detail struct {
	Summary  Summary
	Channels []Channel
	Members  []Member
	Invited  []User
	// Titles are what `title` channels are about.
	Titles map[uuid.UUID]core.Title
	// Agent: `@aaru` answers in this group.
	Agent bool
}

// MARK: Groups

// Groups are the viewer's groups.
func (s *Service) Groups(ctx context.Context, viewer uuid.UUID) ([]Summary, error) {
	return s.Store.Summaries(ctx, viewer)
}

// Create makes a group with the viewer as owner and a `#general` text channel.
func (s *Service) Create(ctx context.Context, name string, viewer uuid.UUID) (Detail, error) {
	if _, err := s.Social.RequireHandle(ctx, viewer); err != nil {
		return Detail{}, err
	}
	name, err := ValidName(name)
	if err != nil {
		return Detail{}, err
	}
	owned, err := s.Store.OwnedCount(ctx, viewer)
	if err != nil {
		return Detail{}, err
	}
	if owned >= MaxOwnedGroups {
		return Detail{}, Invalid("name", fmt.Sprintf("You own %d groups already. Delete one first.", MaxOwnedGroups))
	}
	id := uuid.New()
	now := s.now()
	general := Channel{ID: uuid.New(), GroupID: id, Kind: KindText, Name: "general", Position: 0, IsDefault: true, CreatedAt: now}
	if err := s.Store.CreateGroup(ctx, id, name, viewer, general, now); err != nil {
		return Detail{}, err
	}
	telemetry.Capture(telemetry.GroupCreated, viewer, nil)
	return s.Detail(ctx, id, viewer)
}

// Detail is one of the viewer's groups in full.
func (s *Service) Detail(ctx context.Context, group, viewer uuid.UUID) (Detail, error) {
	summary, err := s.Store.Summary(ctx, group, viewer)
	if err != nil {
		return Detail{}, err
	}
	if summary == nil {
		return Detail{}, ErrNoSuchGroup
	}
	channels, err := s.Store.Channels(ctx, group, viewer)
	if err != nil {
		return Detail{}, err
	}
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return Detail{}, err
	}
	invites, err := s.Store.InvitesPending(ctx, group)
	if err != nil {
		return Detail{}, err
	}
	var ids []uuid.UUID
	for _, c := range channels {
		if c.TitleID != nil {
			ids = append(ids, *c.TitleID)
		}
	}
	titles, err := s.titles(ctx, ids)
	if err != nil {
		return Detail{}, err
	}
	invited := make([]User, len(invites))
	for i, inv := range invites {
		invited[i] = inv.Invitee
	}
	return Detail{
		Summary: *summary, Channels: channels, Members: members, Invited: invited, Titles: titles,
		Agent: s.AgentAvailable,
	}, nil
}

// titles are stored titles by id; unknown ids are left out.
func (s *Service) titles(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]core.Title, error) {
	out := map[uuid.UUID]core.Title{}
	if len(ids) == 0 {
		return out, nil
	}
	found, err := s.Catalog.Store.Titles(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("titles: %w", err)
	}
	for _, t := range found {
		if _, ok := out[t.ID]; !ok {
			out[t.ID] = t
		}
	}
	return out, nil
}

// Title is one stored title, or nil.
func (s *Service) Title(ctx context.Context, id uuid.UUID) (*core.Title, error) {
	t, err := s.Catalog.Store.Title(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("title: %w", err)
	}
	return t, nil
}

// Rename renames a group (owner and admins).
func (s *Service) Rename(ctx context.Context, group uuid.UUID, name string, viewer uuid.UUID) (Detail, error) {
	if err := s.requireManager(ctx, group, viewer); err != nil {
		return Detail{}, err
	}
	name, err := ValidName(name)
	if err != nil {
		return Detail{}, err
	}
	if err := s.Store.RenameGroup(ctx, group, name, s.now()); err != nil {
		return Detail{}, err
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return s.Detail(ctx, group, viewer)
}

// Delete deletes a group (owner only).
func (s *Service) Delete(ctx context.Context, group, viewer uuid.UUID) error {
	role, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	if role != RoleOwner {
		return Forbidden("Only the owner can delete the group.")
	}
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return err
	}
	if err := s.Store.DeleteGroup(ctx, group); err != nil {
		return err
	}
	s.publish(ctx, Event{Type: EventGroupRemoved, Group: group}, memberIDs(members))
	return nil
}

// MARK: Members

// SetRole: the owner makes a member an admin or back. Ownership moves only through Transfer.
func (s *Service) SetRole(ctx context.Context, group, user uuid.UUID, role Role, viewer uuid.UUID) error {
	mine, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	if mine != RoleOwner {
		return Forbidden("Only the owner can change roles.")
	}
	if role == RoleOwner {
		return Invalid("role", "Transfer ownership instead.")
	}
	current, err := s.Store.Role(ctx, group, user)
	if err != nil {
		return err
	}
	if current == nil {
		return ErrNoSuchMember
	}
	if *current == RoleOwner {
		return Invalid("role", "Transfer ownership instead.")
	}
	if err := s.Store.SetRole(ctx, group, user, role); err != nil {
		return err
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return nil
}

// Remove removes a member. Removing yourself is leaving; the owner transfers or deletes first.
// Admins remove members; the owner removes anyone.
func (s *Service) Remove(ctx context.Context, group, user, viewer uuid.UUID) error {
	mine, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	if user == viewer {
		if mine == RoleOwner {
			return Invalid("userId", "Transfer ownership or delete the group before leaving.")
		}
	} else {
		theirs, err := s.Store.Role(ctx, group, user)
		if err != nil {
			return err
		}
		if theirs == nil {
			return ErrNoSuchMember
		}
		if !mine.Manages() || !theirs.Below(mine) {
			return Forbidden("You can't remove that member.")
		}
	}
	if err := s.Store.RemoveMember(ctx, group, user); err != nil {
		return err
	}
	s.publish(ctx, Event{Type: EventGroupRemoved, Group: group}, []uuid.UUID{user})
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return nil
}

// Transfer hands ownership to another member; the owner becomes an admin.
func (s *Service) Transfer(ctx context.Context, group, user, viewer uuid.UUID) error {
	mine, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	if mine != RoleOwner {
		return Forbidden("Only the owner can transfer.")
	}
	if user == viewer {
		return ErrNoSuchMember
	}
	theirs, err := s.Store.Role(ctx, group, user)
	if err != nil {
		return err
	}
	if theirs == nil {
		return ErrNoSuchMember
	}
	if err := s.Store.TransferOwnership(ctx, group, viewer, user); err != nil {
		return err
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return nil
}

// MARK: Invites

// Invite invites a friend. Asking again, or asking someone already in, changes nothing.
func (s *Service) Invite(ctx context.Context, group, user, viewer uuid.UUID) error {
	if _, err := s.Role(ctx, group, viewer); err != nil {
		return err
	}
	inviter, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return err
	}
	friends, err := s.Social.AreFriends(ctx, viewer, user)
	if err != nil {
		return err
	}
	if !friends {
		return Invalid("userId", "You can only invite friends.")
	}
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		return err
	}
	for _, m := range members {
		if m.User.ID == user {
			return nil
		}
	}
	if len(members) >= MaxMembers {
		return Invalid("userId", fmt.Sprintf("A group holds %d people.", MaxMembers))
	}
	created, err := s.Store.CreateInvite(ctx, uuid.New(), group, viewer, user, s.now())
	if err != nil {
		return err
	}
	s.publish(ctx, Event{Type: EventInvitesChanged}, []uuid.UUID{user})
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	if created {
		s.alertInvite(ctx, user, group, inviter)
	}
	return nil
}

// Invites are the invites waiting for the viewer.
func (s *Service) Invites(ctx context.Context, viewer uuid.UUID) ([]Invite, error) {
	return s.Store.InvitesTo(ctx, viewer)
}

// Accept joins the group an invite is for, and returns it.
func (s *Service) Accept(ctx context.Context, invite, viewer uuid.UUID) (Summary, error) {
	pending, err := s.Store.InvitesTo(ctx, viewer)
	if err != nil {
		return Summary{}, err
	}
	var found *Invite
	for i := range pending {
		if pending[i].ID == invite {
			found = &pending[i]
			break
		}
	}
	if found == nil {
		return Summary{}, ErrNoSuchInvite
	}
	// GRP-013: an invite is only as good as the friendship behind it. A lapsed one goes, and
	// reads like an invite that never was.
	friends, err := s.Social.AreFriends(ctx, found.Inviter.ID, viewer)
	if err != nil {
		return Summary{}, err
	}
	if !friends {
		if _, _, _, err := s.Store.DeleteInvite(ctx, invite, viewer); err != nil {
			return Summary{}, err
		}
		return Summary{}, ErrNoSuchInvite
	}
	members, err := s.Store.Members(ctx, found.GroupID)
	if err != nil {
		return Summary{}, err
	}
	if len(members) >= MaxMembers {
		return Summary{}, Invalid("id", "That group is full.")
	}
	group, err := s.Store.AcceptInvite(ctx, invite, viewer, s.now())
	if err != nil {
		return Summary{}, err
	}
	if group == nil {
		return Summary{}, ErrNoSuchInvite
	}
	summary, err := s.Store.Summary(ctx, *group, viewer)
	if err != nil {
		return Summary{}, err
	}
	if summary == nil {
		return Summary{}, ErrNoSuchInvite
	}
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: *group}, *group, uuid.Nil)
	return *summary, nil
}

// Decline declines an invite to the viewer, or cancels one the viewer sent.
func (s *Service) Decline(ctx context.Context, invite, viewer uuid.UUID) error {
	group, invitee, ok, err := s.Store.DeleteInvite(ctx, invite, viewer)
	if err != nil {
		return err
	}
	if !ok {
		return ErrNoSuchInvite
	}
	s.publish(ctx, Event{Type: EventInvitesChanged}, []uuid.UUID{invitee})
	s.announce(ctx, Event{Type: EventGroupUpdated, Group: group}, group, uuid.Nil)
	return nil
}

// MARK: Rules

// announce publishes to every member but except. The write already committed, so a failed member
// lookup only costs the live update; clients catch up over REST on their next `ready`.
func (s *Service) announce(ctx context.Context, e Event, group, except uuid.UUID) {
	members, err := s.Store.Members(ctx, group)
	if err != nil {
		s.log().DebugContext(ctx, "announce: members", "group", group, "error", err)
		return
	}
	var to []uuid.UUID
	for _, m := range members {
		if m.User.ID != except {
			to = append(to, m.User.ID)
		}
	}
	s.publish(ctx, e, to)
}

func memberIDs(members []Member) []uuid.UUID {
	ids := make([]uuid.UUID, len(members))
	for i, m := range members {
		ids[i] = m.User.ID
	}
	return ids
}

// Role is the viewer's role, or the same 404 as a group that does not exist.
func (s *Service) Role(ctx context.Context, group, viewer uuid.UUID) (Role, error) {
	role, err := s.Store.Role(ctx, group, viewer)
	if err != nil {
		return "", err
	}
	if role == nil {
		return "", ErrNoSuchGroup
	}
	return *role, nil
}

func (s *Service) requireManager(ctx context.Context, group, viewer uuid.UUID) error {
	role, err := s.Role(ctx, group, viewer)
	if err != nil {
		return err
	}
	if !role.Manages() {
		return Forbidden("Only the owner and admins can do that.")
	}
	return nil
}

func (s *Service) requireChannel(ctx context.Context, group, channel uuid.UUID) (Channel, error) {
	found, err := s.Store.Channel(ctx, channel, group)
	if err != nil {
		return Channel{}, err
	}
	if found == nil {
		return Channel{}, ErrNoSuchChannel
	}
	return *found, nil
}

func (s *Service) requireMessage(ctx context.Context, group, channel, message uuid.UUID) (Message, error) {
	if _, err := s.requireChannel(ctx, group, channel); err != nil {
		return Message{}, err
	}
	found, err := s.Store.Message(ctx, message, channel)
	if err != nil {
		return Message{}, err
	}
	if found == nil {
		return Message{}, ErrNoSuchMessage
	}
	return *found, nil
}
