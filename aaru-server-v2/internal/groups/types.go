// Package groups is friends-only groups (GRP-001…GRP-013): members, invites, channels
// (text, title, watch, shelf), server-visible messages with spoiler stamps, watch parties,
// mention and invite alerts, and `@aaru` replies (GRP-010/011). It ports
// Social/GroupService*.swift, Data/Stores+Groups*.swift, PostgresGroupStore*.swift and
// Agent/AgentReplyService.swift, AgentReplyWorker.swift and GroupAgentTools.swift.
//
// Everything about a group answers 404 to a non-member, the same as a group that does not
// exist. Group messages are server-visible; DMs are another thing entirely.
package groups

import (
	"aaru-go-api/internal/core"
	"time"

	"github.com/google/uuid"
)

// User is someone with a handle, as groups and the Board show them (SocialUser).
type User struct {
	ID            uuid.UUID
	Handle        string
	DisplayName   *string
	AvatarVersion *int64
}

// Role is a member's place in a group.
type Role string

// The roles.
const (
	RoleOwner  Role = "owner"
	RoleAdmin  Role = "admin"
	RoleMember Role = "member"
)

func parseRole(s string) Role {
	switch Role(s) {
	case RoleOwner, RoleAdmin:
		return Role(s)
	default:
		return RoleMember
	}
}

// Manages: owner and admins manage channels and members.
func (r Role) Manages() bool { return r != RoleMember }

func (r Role) rank() int {
	switch r {
	case RoleOwner:
		return 2
	case RoleAdmin:
		return 1
	default:
		return 0
	}
}

// Below reports whether r ranks under other.
func (r Role) Below(other Role) bool { return r.rank() < other.rank() }

// Summary is one group as the viewer's rail shows it.
type Summary struct {
	ID               uuid.UUID
	Name             string
	Role             Role
	DefaultChannelID uuid.UUID
	// Unread is messages from others since the viewer last read, across every channel.
	Unread   int
	Mentions int
	// ShareProgress: the viewer shows their progress in this group's title channels (GRP-007).
	ShareProgress bool
	// Muted: the viewer silenced this group's mention alerts (GRP-012).
	Muted bool
}

// ChannelKind is plain chat, one title's thread, a watch party, or a shared shelf.
type ChannelKind string

// The kinds.
const (
	KindText  ChannelKind = "text"
	KindTitle ChannelKind = "title"
	KindWatch ChannelKind = "watch"
	KindShelf ChannelKind = "shelf"
)

func parseKind(s string) ChannelKind {
	switch ChannelKind(s) {
	case KindTitle, KindWatch, KindShelf:
		return ChannelKind(s)
	default:
		return KindText
	}
}

// Channel is one place to talk inside a group.
type Channel struct {
	ID      uuid.UUID
	GroupID uuid.UUID
	Kind    ChannelKind
	// TitleID is what a `title` channel is about; nil for every other kind.
	TitleID   *uuid.UUID
	Name      string
	Topic     *string
	Position  int
	IsDefault bool
	CreatedAt time.Time
	Unread    int
	Mentions  int
}

// Member is a user's place in a group.
type Member struct {
	User          User
	Role          Role
	JoinedAt      time.Time
	ShareProgress bool
}

// Invite is a pending invite into a group. It stops existing once accepted or declined.
type Invite struct {
	ID        uuid.UUID
	GroupID   uuid.UUID
	GroupName string
	Inviter   User
	Invitee   User
	CreatedAt time.Time
}

// EpisodePoint is a point in a show, ordered as watched.
type EpisodePoint struct {
	Season  int
	Episode int
}

// Before reports whether p comes before other.
func (p EpisodePoint) Before(other EpisodePoint) bool {
	if p.Season != other.Season {
		return p.Season < other.Season
	}
	return p.Episode < other.Episode
}

// SpoilerStamp is what a message may give away: up to an episode, or the ending of anything.
// Exactly one of Episode and Ending is set.
type SpoilerStamp struct {
	Episode *EpisodePoint
	Ending  bool
}

// EndingStamp is the ending of anything.
func EndingStamp() *SpoilerStamp { return &SpoilerStamp{Ending: true} }

// EpisodeStamp is up to one episode.
func EpisodeStamp(p EpisodePoint) *SpoilerStamp { return &SpoilerStamp{Episode: &p} }

// TitleProgress is one user's library status in one title and the furthest episode they ticked.
type TitleProgress struct {
	Status   core.LibraryStatus
	Furthest *EpisodePoint
}

// Component is a card on an agent reply: one title. Title is filled in when the message is read.
type Component struct {
	TitleID uuid.UUID
	Title   *core.Title
}

// Message is one message in a channel. Author is nil once the author deleted their account,
// and for `@aaru`. A deleted message keeps its row with an empty body so the history around it
// still reads in order.
type Message struct {
	ID            uuid.UUID
	ChannelID     uuid.UUID
	Author        *User
	Body          string
	Mentions      []uuid.UUID
	MentionsAgent bool
	CreatedAt     time.Time
	EditedAt      *time.Time
	DeletedAt     *time.Time
	// ClientNonce is the author's retry key. Only the author is ever shown it.
	ClientNonce *string
	// Spoiler is how far into the title a reader must be to read it unveiled (title channels).
	Spoiler *SpoilerStamp
	// FromAgent: written by `@aaru`; such a message has no author.
	FromAgent bool
	// ReplyTo is the mention an agent reply answers.
	ReplyTo *uuid.UUID
	// Components are the catalog cards an agent reply carries. Nothing else is allowed.
	Components []Component
}

// AuthorID is the author's id, or uuid.Nil without one.
func (m Message) AuthorID() uuid.UUID {
	if m.Author == nil {
		return uuid.Nil
	}
	return m.Author.ID
}

// CursorKind is where a page of messages starts.
type CursorKind int

// The cursors: the latest, older than one message, newer than one.
const (
	CursorLatest CursorKind = iota
	CursorBefore
	CursorAfter
)

// Cursor is a page start.
type Cursor struct {
	Kind CursorKind
	ID   uuid.UUID
}

// ShelfItem is one title on a shelf channel. AddedBy is nil once that account is gone.
type ShelfItem struct {
	TitleID  uuid.UUID
	AddedBy  *User
	AddedAt  time.Time
	Position int
	// MyStatus is the viewer's own library status for the title, when they have it.
	MyStatus *core.LibraryStatus
}

// WatchParty is a party in a watch channel: lobby until StartsAt is set, then a countdown until
// it passes, then live until EndedAt.
type WatchParty struct {
	ID        uuid.UUID
	ChannelID uuid.UUID
	TitleID   uuid.UUID
	Episode   *EpisodePoint
	CreatedBy *User
	StartsAt  *time.Time
	EndedAt   *time.Time
	CreatedAt time.Time
	Ready     []User
}

// PartyState is a party's state at a moment.
func (p WatchParty) State(now time.Time) string {
	switch {
	case p.EndedAt != nil:
		return "ended"
	case p.StartsAt == nil:
		return "lobby"
	case p.StartsAt.After(now):
		return "countdown"
	default:
		return "live"
	}
}
