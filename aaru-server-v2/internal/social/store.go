package social

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is the social graph (PostgresSocialStore.swift, +Invites, PostgresFriendViewStore.swift).
// Callers check blocks before revealing anything; the store only answers what is asked.
type Store struct {
	Pool *pgxpool.Pool
	Q    *sqlc.Queries
}

// NewStore builds the store over a pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool, Q: sqlc.New(pool)}
}

// errConflict is a constraint failure (Swift's StoreConflict): a taken handle or code.
type errConflict struct{ message string }

func (e errConflict) Error() string { return e.message }

// AppError is the 409 `conflict` Swift's StoreConflict answered.
func (e errConflict) AppError() *apperr.Error { return apperr.Conflict(e.message) }

// isConstraintFailure is any integrity-constraint violation (class 23), as Fluent's
// isConstraintFailure was.
func isConstraintFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && strings.HasPrefix(pgErr.Code, "23")
}

func userOf(id uuid.UUID, handle string, name *string, avatar *int64) User {
	return User{ID: id, Handle: handle, DisplayName: name, AvatarVersion: avatar}
}

// User is the user's social identity; nil until they claim a handle.
func (s *Store) User(ctx context.Context, id uuid.UUID) (*User, error) {
	row, err := s.Q.SocialUserByID(ctx, id)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // no handle
	}
	if err != nil {
		return nil, fmt.Errorf("social user: %w", err)
	}
	u := userOf(row.UserID, row.Handle, row.DisplayName, row.AvatarVersion)
	return &u, nil
}

// UserByHandle is whoever holds the (already lowercased) handle, or nil.
func (s *Store) UserByHandle(ctx context.Context, handle string) (*User, error) {
	row, err := s.Q.SocialUserByHandle(ctx, handle)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nobody
	}
	if err != nil {
		return nil, fmt.Errorf("social user by handle: %w", err)
	}
	u := userOf(row.UserID, row.Handle, row.DisplayName, row.AvatarVersion)
	return &u, nil
}

// Name is a first and a last name, both optional (SOC-001b).
type Name struct {
	First *string
	Last  *string
}

// SaveProfile claims or changes the handle when one is given, and replaces both names when
// they are. A handle another user holds is a 409.
func (s *Store) SaveProfile(ctx context.Context, id uuid.UUID, handle *string, name *Name) error {
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if handle != nil {
			if err := q.SocialSaveHandle(ctx, sqlc.SocialSaveHandleParams{UserID: id, Handle: *handle}); err != nil {
				return err
			}
		}
		if name != nil {
			return q.SocialSaveNames(ctx, sqlc.SocialSaveNamesParams{
				ID: id, FirstName: name.First, LastName: name.Last, DisplayName: joinName(name.First, name.Last),
			})
		}
		return nil
	})
	if isConstraintFailure(err) {
		return errConflict{"That handle is taken."}
	}
	if err != nil {
		return fmt.Errorf("save profile: %w", err)
	}
	return nil
}

// SaveAvatar replaces the avatar and gives it a new version (SOC-001b).
func (s *Store) SaveAvatar(ctx context.Context, id uuid.UUID, image []byte) error {
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.SocialSaveAvatar(ctx, sqlc.SocialSaveAvatarParams{UserID: id, Image: image}); err != nil {
			return err
		}
		return q.SocialBumpAvatarVersion(ctx, id)
	})
	if err != nil {
		return fmt.Errorf("save avatar: %w", err)
	}
	return nil
}

// DeleteAvatar removes the avatar and its version.
func (s *Store) DeleteAvatar(ctx context.Context, id uuid.UUID) error {
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.SocialDeleteAvatar(ctx, id); err != nil {
			return err
		}
		return q.SocialClearAvatarVersion(ctx, id)
	})
	if err != nil {
		return fmt.Errorf("delete avatar: %w", err)
	}
	return nil
}

// Avatar is the avatar's JPEG bytes, or nil without one.
func (s *Store) Avatar(ctx context.Context, id uuid.UUID) ([]byte, error) {
	image, err := s.Q.SocialAvatar(ctx, id)
	if db.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("avatar: %w", err)
	}
	return image, nil
}

// IsBlocked is true when either user blocked the other.
func (s *Store) IsBlocked(ctx context.Context, first, second uuid.UUID) (bool, error) {
	found, err := s.Q.SocialIsBlocked(ctx, sqlc.SocialIsBlockedParams{First: first, Second: second})
	if err != nil {
		return false, fmt.Errorf("is blocked: %w", err)
	}
	return found, nil
}

// AreFriends is true for a mutual, accepted friendship.
func (s *Store) AreFriends(ctx context.Context, first, second uuid.UUID) (bool, error) {
	found, err := s.Q.SocialAreFriends(ctx, sqlc.SocialAreFriendsParams{First: first, Second: second})
	if err != nil {
		return false, fmt.Errorf("are friends: %w", err)
	}
	return found, nil
}

// FriendsSince is when the two became friends; nil when they are not.
func (s *Store) FriendsSince(ctx context.Context, first, second uuid.UUID) (*time.Time, error) {
	since, err := s.Q.SocialFriendsSince(ctx, sqlc.SocialFriendsSinceParams{First: first, Second: second})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // not friends
	}
	if err != nil {
		return nil, fmt.Errorf("friends since: %w", err)
	}
	return &since, nil
}

// PendingRequest is the pending request from one user to another, if any.
func (s *Store) PendingRequest(ctx context.Context, sender, recipient uuid.UUID) (*uuid.UUID, error) {
	id, err := s.Q.SocialPendingRequest(ctx, sqlc.SocialPendingRequestParams{FromUserID: sender, ToUserID: recipient})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none pending
	}
	if err != nil {
		return nil, fmt.Errorf("pending request: %w", err)
	}
	return &id, nil
}

// CreateRequest inserts a request; a duplicate is ignored.
func (s *Store) CreateRequest(ctx context.Context, id, sender, recipient uuid.UUID, now time.Time) error {
	if err := s.Q.SocialCreateRequest(ctx, sqlc.SocialCreateRequestParams{
		ID: id, FromUserID: sender, ToUserID: recipient, CreatedAt: now,
	}); err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	return nil
}

// requestRow is either request listing's row: both select the same columns.
type requestRow sqlc.SocialIncomingRequestsRow

func (r requestRow) request() FriendRequest {
	return FriendRequest{
		ID:        r.ID,
		Sender:    userOf(r.FromUserID, r.FromHandle, r.FromDisplayName, r.FromAvatarVersion),
		Recipient: userOf(r.ToUserID, r.ToHandle, r.ToDisplayName, r.ToAvatarVersion),
		CreatedAt: r.CreatedAt,
	}
}

// IncomingRequests are the requests to the user, newest first.
func (s *Store) IncomingRequests(ctx context.Context, id uuid.UUID) ([]FriendRequest, error) {
	rows, err := s.Q.SocialIncomingRequests(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("incoming requests: %w", err)
	}
	out := make([]FriendRequest, 0, len(rows))
	for _, r := range rows {
		out = append(out, requestRow(r).request())
	}
	return out, nil
}

// OutgoingRequests are the requests the user sent, newest first.
func (s *Store) OutgoingRequests(ctx context.Context, id uuid.UUID) ([]FriendRequest, error) {
	rows, err := s.Q.SocialOutgoingRequests(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("outgoing requests: %w", err)
	}
	out := make([]FriendRequest, 0, len(rows))
	for _, r := range rows {
		out = append(out, requestRow(r).request())
	}
	return out, nil
}

// AcceptRequest turns a request addressed to recipient into a friendship. It returns the
// sender, or nil when no such request is pending.
func (s *Store) AcceptRequest(ctx context.Context, id, recipient uuid.UUID, now time.Time) (*uuid.UUID, error) {
	var sender *uuid.UUID
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		from, err := q.SocialTakeRequest(ctx, sqlc.SocialTakeRequestParams{ID: id, ToUserID: recipient})
		if db.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return err
		}
		// The reverse request, if both asked, is answered by the same acceptance.
		if err := q.SocialDeleteRequestFrom(ctx, sqlc.SocialDeleteRequestFromParams{FromUserID: recipient, ToUserID: from}); err != nil {
			return err
		}
		if err := q.SocialInsertFriendship(ctx, sqlc.SocialInsertFriendshipParams{First: from, Second: recipient, CreatedAt: now}); err != nil {
			return err
		}
		sender = &from
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("accept request: %w", err)
	}
	return sender, nil
}

// DeleteRequest deletes a request either side of it is withdrawing. True when one was pending.
func (s *Store) DeleteRequest(ctx context.Context, id, party uuid.UUID) (bool, error) {
	n, err := s.Q.SocialWithdrawRequest(ctx, sqlc.SocialWithdrawRequestParams{ID: id, Party: party})
	if err != nil {
		return false, fmt.Errorf("withdraw request: %w", err)
	}
	return n > 0, nil
}

// Friends are the user's friends with a handle, by handle.
func (s *Store) Friends(ctx context.Context, id uuid.UUID) ([]User, error) {
	rows, err := s.Q.SocialFriends(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("friends: %w", err)
	}
	out := make([]User, 0, len(rows))
	for _, r := range rows {
		out = append(out, userOf(r.UserID, r.Handle, r.DisplayName, r.AvatarVersion))
	}
	return out, nil
}

// Unfriend ends a friendship and the pair's own group invites. True when they were friends.
func (s *Store) Unfriend(ctx context.Context, first, second uuid.UUID) (bool, error) {
	var ended bool
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		n, err := q.SocialDeleteFriendship(ctx, sqlc.SocialDeleteFriendshipParams{First: first, Second: second})
		if err != nil {
			return err
		}
		ended = n > 0
		return q.SocialDropGroupInvites(ctx, sqlc.SocialDropGroupInvitesParams{First: first, Second: second})
	})
	if err != nil {
		return false, fmt.Errorf("unfriend: %w", err)
	}
	return ended, nil
}

// Block blocks, and in the same transaction ends any friendship, pending requests both ways and
// the pair's group invites.
func (s *Store) Block(ctx context.Context, blocker, blocked uuid.UUID, now time.Time) error {
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.SocialInsertBlock(ctx, sqlc.SocialInsertBlockParams{BlockerID: blocker, BlockedID: blocked, CreatedAt: now}); err != nil {
			return err
		}
		if _, err := q.SocialDeleteFriendship(ctx, sqlc.SocialDeleteFriendshipParams{First: blocker, Second: blocked}); err != nil {
			return err
		}
		if err := q.SocialDeleteRequestsBetween(ctx, sqlc.SocialDeleteRequestsBetweenParams{First: blocker, Second: blocked}); err != nil {
			return err
		}
		return q.SocialDropGroupInvites(ctx, sqlc.SocialDropGroupInvitesParams{First: blocker, Second: blocked})
	})
	if err != nil {
		return fmt.Errorf("block: %w", err)
	}
	return nil
}

// Unblock removes the blocker's block. True when there was one.
func (s *Store) Unblock(ctx context.Context, blocker, blocked uuid.UUID) (bool, error) {
	n, err := s.Q.SocialUnblock(ctx, sqlc.SocialUnblockParams{BlockerID: blocker, BlockedID: blocked})
	if err != nil {
		return false, fmt.Errorf("unblock: %w", err)
	}
	return n > 0, nil
}

// Blocked are the users this user blocked, by handle.
func (s *Store) Blocked(ctx context.Context, id uuid.UUID) ([]User, error) {
	rows, err := s.Q.SocialBlocked(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("blocked: %w", err)
	}
	out := make([]User, 0, len(rows))
	for _, r := range rows {
		out = append(out, userOf(r.UserID, r.Handle, r.DisplayName, r.AvatarVersion))
	}
	return out, nil
}

// Blockers is everyone who blocked this user.
func (s *Store) Blockers(ctx context.Context, id uuid.UUID) (map[uuid.UUID]bool, error) {
	ids, err := s.Q.SocialBlockers(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("blockers: %w", err)
	}
	out := make(map[uuid.UUID]bool, len(ids))
	for _, b := range ids {
		out[b] = true
	}
	return out, nil
}

// Report is one report of a user to Aaru. The reported user is never told.
type Report struct {
	ID        uuid.UUID
	Reporter  uuid.UUID
	Target    uuid.UUID
	Reason    ReportReason
	Note      *string
	CreatedAt time.Time
}

// SaveReport stores a report.
func (s *Store) SaveReport(ctx context.Context, r Report) error {
	target := r.Target
	if err := s.Q.SocialReport(ctx, sqlc.SocialReportParams{
		ID: r.ID, ReporterID: r.Reporter, TargetUserID: &target, Reason: string(r.Reason), Note: r.Note, CreatedAt: r.CreatedAt,
	}); err != nil {
		return fmt.Errorf("report: %w", err)
	}
	return nil
}

// MARK: Invites (SOC-002)

func inviteOf(r sqlc.SocialInvite) Invite {
	return Invite{
		ID: r.ID, Code: r.Code, Inviter: r.InviterID, TitleID: r.TitleID, CreatedAt: r.CreatedAt, ExpiresAt: r.ExpiresAt,
		RedeemedBy: r.RedeemedBy, RedeemedAt: r.RedeemedAt, RevokedAt: r.RevokedAt,
	}
}

// CreateInvite inserts an invite; a taken code is a conflict.
func (s *Store) CreateInvite(ctx context.Context, i Invite) error {
	err := s.Q.SocialCreateInvite(ctx, sqlc.SocialCreateInviteParams{
		ID: i.ID, Code: i.Code, InviterID: i.Inviter, TitleID: i.TitleID, CreatedAt: i.CreatedAt, ExpiresAt: i.ExpiresAt,
	})
	if isConstraintFailure(err) {
		return errConflict{"That invite code is taken."}
	}
	if err != nil {
		return fmt.Errorf("create invite: %w", err)
	}
	return nil
}

// Invite is the invite with this code, or nil.
func (s *Store) Invite(ctx context.Context, code string) (*Invite, error) {
	row, err := s.Q.SocialInvite(ctx, code)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none
	}
	if err != nil {
		return nil, fmt.Errorf("invite: %w", err)
	}
	i := inviteOf(row)
	return &i, nil
}

// OpenInvites are the inviter's invites still open at now, newest first.
func (s *Store) OpenInvites(ctx context.Context, inviter uuid.UUID, now time.Time) ([]Invite, error) {
	rows, err := s.Q.SocialOpenInvites(ctx, sqlc.SocialOpenInvitesParams{InviterID: inviter, Now: now})
	if err != nil {
		return nil, fmt.Errorf("open invites: %w", err)
	}
	out := make([]Invite, 0, len(rows))
	for _, r := range rows {
		out = append(out, inviteOf(r))
	}
	return out, nil
}

// RevokeInvite revokes an open invite the inviter made. True when one was open.
func (s *Store) RevokeInvite(ctx context.Context, code string, inviter uuid.UUID, now time.Time) (bool, error) {
	n, err := s.Q.SocialRevokeInvite(ctx, sqlc.SocialRevokeInviteParams{Code: code, InviterID: inviter, Now: &now})
	if err != nil {
		return false, fmt.Errorf("revoke invite: %w", err)
	}
	return n > 0, nil
}

// RedeemInvite spends an open invite on redeemer and, in the same transaction, makes the two
// friends and drops any pending requests between them. It returns the inviter, or nil when the
// invite was not open (a concurrent redeem lost).
func (s *Store) RedeemInvite(ctx context.Context, code string, redeemer uuid.UUID, now time.Time) (*uuid.UUID, error) {
	var inviter *uuid.UUID
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		id, err := q.SocialRedeemInvite(ctx, sqlc.SocialRedeemInviteParams{Redeemer: redeemer, Now: &now, Code: code})
		if db.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := q.SocialDeleteRequestsBetween(ctx, sqlc.SocialDeleteRequestsBetweenParams{First: id, Second: redeemer}); err != nil {
			return err
		}
		if err := q.SocialInsertFriendship(ctx, sqlc.SocialInsertFriendshipParams{First: id, Second: redeemer, CreatedAt: now}); err != nil {
			return err
		}
		inviter = &id
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("redeem invite: %w", err)
	}
	return inviter, nil
}

// MARK: Settings (SOC-001)

// Settings are the user's social switches; DefaultSettings without a row.
func (s *Store) Settings(ctx context.Context, id uuid.UUID) (Settings, error) {
	row, err := s.Q.SocialSettings(ctx, id)
	if db.IsNoRows(err) {
		return DefaultSettings, nil
	}
	if err != nil {
		return Settings{}, fmt.Errorf("social settings: %w", err)
	}
	return Settings{
		ShareLibraryWithFriends: row.ShareLibraryWithFriends, ShowAchievementsToFriends: row.ShowAchievementsToFriends,
		LeaderboardOptIn: row.LeaderboardOptIn, ShareEmailWithFriends: row.ShareEmailWithFriends,
	}, nil
}

// SaveSettings replaces the user's switches.
func (s *Store) SaveSettings(ctx context.Context, id uuid.UUID, settings Settings) error {
	if err := s.Q.SocialSaveSettings(ctx, sqlc.SocialSaveSettingsParams{
		UserID: id, ShareLibraryWithFriends: settings.ShareLibraryWithFriends,
		ShowAchievementsToFriends: settings.ShowAchievementsToFriends, LeaderboardOptIn: settings.LeaderboardOptIn,
		ShareEmailWithFriends: settings.ShareEmailWithFriends,
	}); err != nil {
		return fmt.Errorf("save social settings: %w", err)
	}
	return nil
}

// HasTitle is true when the owner has the title in their library at all.
func (s *Store) HasTitle(ctx context.Context, owner, titleID uuid.UUID) (bool, error) {
	found, err := s.Q.SocialHasTitle(ctx, sqlc.SocialHasTitleParams{UserID: owner, TitleID: titleID})
	if err != nil {
		return false, fmt.Errorf("has title: %w", err)
	}
	return found, nil
}

func joinName(first, last *string) *string {
	var parts []string
	for _, p := range []*string{first, last} {
		if p != nil {
			parts = append(parts, *p)
		}
	}
	if len(parts) == 0 {
		return nil
	}
	joined := strings.Join(parts, " ")
	if joined == "" {
		return nil
	}
	return &joined
}
