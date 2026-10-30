// Package social is P4's minimal social layer (Sources/App/Social in the Swift server): handles,
// friend requests, friends, blocks and reports (SocialService.swift), avatars
// (SocialService+Avatar.swift), friend profiles, settings and activity (FriendService.swift),
// invite links (InviteService.swift), reactions and recommendations (InteractionService.swift)
// and favorites (FavoriteService.swift).
//
// Private by default and friends only: anyone who is not a friend, and a block either way, is
// the same 404 as a handle nobody holds (X-011).
//
// # For other areas (groups, boards, export)
//
// The social graph is read through *Store:
//
//   - AreFriends(ctx, a, b): a mutual, accepted friendship.
//   - IsBlocked(ctx, a, b): either user blocked the other.
//   - Blockers(ctx, user): everyone who blocked this user.
//   - User(ctx, id) / UserByHandle(ctx, handle): a user's social identity, nil without a handle.
//   - Friends(ctx, user): friends with a handle, by handle.
//   - FriendsSince(ctx, a, b): when two became friends, nil when they are not.
//   - Settings(ctx, user): the user's social switches (defaults without a row).
//
// Service.Relationship(ctx, viewer, other) is where another user stands with the viewer, and
// answers ErrNoSuchUser across a block.
package social

import (
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
)

// User is another user as social surfaces show them: only people with a handle appear anywhere
// social.
type User struct {
	ID          uuid.UUID
	Handle      string
	DisplayName *string
	// AvatarVersion changes on every upload; nil without an avatar (SOC-001b).
	AvatarVersion *int64
}

// Relationship is where another user stands with the viewer.
type Relationship string

// The relationships.
const (
	RelationshipNone   Relationship = "none"
	RelationshipFriend Relationship = "friend"
	// RelationshipOutgoing: the viewer asked them.
	RelationshipOutgoing Relationship = "outgoing"
	// RelationshipIncoming: they asked the viewer.
	RelationshipIncoming Relationship = "incoming"
	RelationshipSelf     Relationship = "self"
)

// FriendRequest is a pending request. It stops existing once accepted, declined or cancelled.
type FriendRequest struct {
	ID        uuid.UUID
	Sender    User
	Recipient User
	CreatedAt time.Time
}

// ReportReason is why a user reported another.
type ReportReason string

// The report reasons.
const (
	ReportSpam          ReportReason = "spam"
	ReportHarassment    ReportReason = "harassment"
	ReportImpersonation ReportReason = "impersonation"
	ReportOther         ReportReason = "other"
)

// Invite is one friend invite link (SOC-002). Open while it is unredeemed, unrevoked and unexpired.
type Invite struct {
	ID         uuid.UUID
	Code       string
	Inviter    uuid.UUID
	TitleID    *uuid.UUID
	CreatedAt  time.Time
	ExpiresAt  time.Time
	RedeemedBy *uuid.UUID
	RedeemedAt *time.Time
	RevokedAt  *time.Time
}

// IsOpen reports whether the invite can still be redeemed at now.
func (i Invite) IsOpen(now time.Time) bool {
	return i.RedeemedAt == nil && i.RevokedAt == nil && i.ExpiresAt.After(now)
}

// Settings are a user's social choices. A user with no row has DefaultSettings.
type Settings struct {
	// ShareLibraryWithFriends: friends see your shelves, activity and compare. Strangers never do.
	ShareLibraryWithFriends bool
	// ShowAchievementsToFriends: friends see your level and badges (GAM-004). Private badges never.
	ShowAchievementsToFriends bool
	// LeaderboardOptIn: you appear on friends' weekly board, and see it (GAM-005). Off until you join.
	LeaderboardOptIn bool
	// ShareEmailWithFriends: friends see your email on your profile (SOC-001b). Groups never.
	ShareEmailWithFriends bool
}

// DefaultSettings are the switches of a user who never saved any.
var DefaultSettings = Settings{ShareLibraryWithFriends: true, ShowAchievementsToFriends: true}

// trimSpaces trims spaces and tabs but not newlines, as Swift's `.whitespaces` did.
func trimSpaces(s string) string {
	return strings.TrimFunc(s, func(r rune) bool {
		return unicode.IsSpace(r) && r != '\n' && r != '\r' && r != '\v' && r != '\f' && r != 0x85 &&
			r != 0x2028 && r != 0x2029
	})
}
