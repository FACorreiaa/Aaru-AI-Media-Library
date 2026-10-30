package auth

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Provider is how a user signs in. One user may have several.
type Provider string

// The sign-in providers auth_identities allows.
const (
	ProviderApple  Provider = "apple"
	ProviderEmail  Provider = "email"
	ProviderGoogle Provider = "google"
)

// Identity is one sign-in of a user.
type Identity struct {
	Provider Provider
	Subject  string
	Email    *string
}

// Profile is the signed-in user as `GET /v1/me` shows them.
type Profile struct {
	ID            uuid.UUID
	FirstName     *string
	LastName      *string
	Handle        *string
	Providers     []Provider
	Email         *string
	AvatarVersion *int64
}

// DisplayName is the two names joined: what friends and groups see.
func (p Profile) DisplayName() *string {
	return JoinName(p.FirstName, p.LastName)
}

// EmailShareable is false for none and for Apple's private relay, which takes mail only from Aaru: sharing it with friends is pointless.
func (p Profile) EmailShareable() bool {
	return p.Email != nil && !strings.HasSuffix(strings.ToLower(*p.Email), "@privaterelay.appleid.com")
}

// JoinName joins a first and last name; nil with neither.
func JoinName(first, last *string) *string {
	var parts []string
	for _, p := range []*string{first, last} {
		if p != nil {
			parts = append(parts, *p)
		}
	}
	joined := strings.Join(parts, " ")
	if joined == "" {
		return nil
	}
	return &joined
}

// SplitName is one name as an older app or a sign-in sends it: the first word, then the rest.
func SplitName(raw *string) (first, last *string) {
	name := ""
	if raw != nil {
		name = strings.TrimSpace(*raw)
	}
	i := strings.IndexFunc(name, unicode.IsSpace)
	if i < 0 {
		if name == "" {
			return nil, nil
		}
		return &name, nil
	}
	f := name[:i]
	l := strings.TrimSpace(name[i:])
	if l == "" {
		return &f, nil
	}
	return &f, &l
}

// ContactEmail is the address shown and shared: the email sign-in's, else Google's, else Apple's.
func ContactEmail(identities []sqlc.UserIdentitiesRow) *string {
	for _, provider := range []Provider{ProviderEmail, ProviderGoogle, ProviderApple} {
		for _, row := range identities {
			if Provider(row.Provider) == provider && row.Email != nil && *row.Email != "" {
				email := *row.Email
				return &email
			}
		}
	}
	return nil
}

// errStoreConflict: a write broke a uniqueness rule (a concurrent sign-in, an identity already taken).
type storeConflict struct{ message string }

func (e storeConflict) Error() string { return e.message }

func isConstraintFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && strings.HasPrefix(pgErr.Code, "23")
}

const identityTaken = "That sign-in is already linked to an account."

// Store is the Postgres side of auth: users, identities, sessions, magic links.
type Store struct {
	pool *pgxpool.Pool
	q    *sqlc.Queries
}

// NewStore wraps the pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool, q: sqlc.New(pool)}
}

// createUser creates a user with its first identity, or a storeConflict if the identity exists.
func (s *Store) createUser(ctx context.Context, identity Identity, displayName *string) (uuid.UUID, error) {
	id := uuid.New()
	first, last := SplitName(displayName)
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		if err := q.CreateUser(ctx, sqlc.CreateUserParams{ID: id, FirstName: first, LastName: last, DisplayName: JoinName(first, last)}); err != nil {
			return err
		}
		if err := q.CreateAuthIdentity(ctx, sqlc.CreateAuthIdentityParams{
			ID: uuid.New(), UserID: id, Provider: string(identity.Provider), ProviderSubject: identity.Subject, Email: identity.Email,
		}); err != nil {
			return err
		}
		return q.CreateUserProgress(ctx, id)
	})
	if err != nil {
		if isConstraintFailure(err) {
			return uuid.Nil, storeConflict{identityTaken}
		}
		return uuid.Nil, fmt.Errorf("create user: %w", err)
	}
	return id, nil
}

func (s *Store) addIdentity(ctx context.Context, identity Identity, userID uuid.UUID) error {
	err := s.q.CreateAuthIdentity(ctx, sqlc.CreateAuthIdentityParams{
		ID: uuid.New(), UserID: userID, Provider: string(identity.Provider), ProviderSubject: identity.Subject, Email: identity.Email,
	})
	if err != nil {
		if isConstraintFailure(err) {
			return storeConflict{identityTaken}
		}
		return fmt.Errorf("add identity: %w", err)
	}
	return nil
}

func (s *Store) userFor(ctx context.Context, provider Provider, subject string) (uuid.UUID, bool, error) {
	id, err := s.q.UserForIdentity(ctx, sqlc.UserForIdentityParams{Provider: string(provider), ProviderSubject: subject})
	if err != nil {
		if db.IsNoRows(err) {
			return uuid.Nil, false, nil
		}
		return uuid.Nil, false, fmt.Errorf("user for identity: %w", err)
	}
	return id, true, nil
}

// Profile is the user's profile, or false when the user no longer exists.
func (s *Store) Profile(ctx context.Context, id uuid.UUID) (Profile, bool, error) {
	row, err := s.q.UserProfile(ctx, id)
	if err != nil {
		if db.IsNoRows(err) {
			return Profile{}, false, nil
		}
		return Profile{}, false, fmt.Errorf("profile: %w", err)
	}
	identities, err := s.q.UserIdentities(ctx, id)
	if err != nil {
		return Profile{}, false, fmt.Errorf("identities: %w", err)
	}
	p := Profile{ID: id, FirstName: row.FirstName, LastName: row.LastName, Handle: row.Handle, AvatarVersion: row.AvatarVersion, Providers: []Provider{}}
	known := []sqlc.UserIdentitiesRow{}
	for _, i := range identities {
		switch Provider(i.Provider) {
		case ProviderApple, ProviderEmail, ProviderGoogle:
			p.Providers = append(p.Providers, Provider(i.Provider))
			known = append(known, i)
		}
	}
	p.Email = ContactEmail(known)
	return p, true, nil
}

// deleteUser deletes the user and, by cascade, every row that belongs to them,
// plus the magic links sent to their email identities (AUTH-004).
func (s *Store) deleteUser(ctx context.Context, id uuid.UUID) error {
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		if err := q.DeleteUserMagicLinks(ctx, id); err != nil {
			return err
		}
		if err := LeaveGroups(ctx, q, id); err != nil {
			return err
		}
		if err := q.ClearUserShareNotes(ctx, id); err != nil {
			return err
		}
		return q.DeleteUser(ctx, id)
	})
	if err != nil {
		return fmt.Errorf("delete user: %w", err)
	}
	return nil
}

// LeaveGroups empties the user's group messages (server-visible, so emptied, not
// orphaned with their text), deletes the groups nobody else is in, and passes each
// group they owned to its oldest admin, else its oldest member. The membership rows
// then cascade with the user.
func LeaveGroups(ctx context.Context, q *sqlc.Queries, id uuid.UUID) error {
	if err := q.EmptyUserGroupMessages(ctx, id); err != nil {
		return fmt.Errorf("empty messages: %w", err)
	}
	if err := q.DeleteSoloGroups(ctx, id); err != nil {
		return fmt.Errorf("delete solo groups: %w", err)
	}
	owned, err := q.DemoteOwnedGroups(ctx, id)
	if err != nil {
		return fmt.Errorf("demote owner: %w", err)
	}
	for _, group := range owned {
		if err := q.PromoteNextOwner(ctx, sqlc.PromoteNextOwnerParams{GroupID: group, LeavingUserID: id}); err != nil {
			return fmt.Errorf("promote owner: %w", err)
		}
	}
	return nil
}

func (s *Store) createSession(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt time.Time) error {
	if err := s.q.CreateSession(ctx, sqlc.CreateSessionParams{ID: uuid.New(), UserID: userID, TokenHash: tokenHash, ExpiresAt: expiresAt}); err != nil {
		return fmt.Errorf("create session: %w", err)
	}
	return nil
}

func (s *Store) deleteSession(ctx context.Context, tokenHash string) error {
	if err := s.q.DeleteSession(ctx, tokenHash); err != nil {
		return fmt.Errorf("delete session: %w", err)
	}
	return nil
}

// CreateMagicLink stores a link's and its code's hashes.
func (s *Store) CreateMagicLink(ctx context.Context, email, tokenHash, codeHash string, expiresAt time.Time) error {
	err := s.q.CreateMagicLink(ctx, sqlc.CreateMagicLinkParams{ID: uuid.New(), Email: email, TokenHash: tokenHash, CodeHash: codeHash, ExpiresAt: expiresAt})
	if err != nil {
		return fmt.Errorf("create magic link: %w", err)
	}
	return nil
}

// ConsumeMagicLink atomically marks the link used and returns its email; false
// when unknown, expired, or already used — a link signs in once.
func (s *Store) ConsumeMagicLink(ctx context.Context, tokenHash string, now time.Time) (string, bool, error) {
	email, err := s.q.ConsumeMagicLinkToken(ctx, sqlc.ConsumeMagicLinkTokenParams{Now: now, TokenHash: tokenHash})
	if err != nil {
		if db.IsNoRows(err) {
			return "", false, nil
		}
		return "", false, fmt.Errorf("consume magic link: %w", err)
	}
	return email, true, nil
}

// consumeCode is the same by the emailed code. A wrong code counts against every
// live link for the email; a link with maxAttempts wrong codes no longer accepts its code.
func (s *Store) consumeCode(ctx context.Context, email, codeHash string, maxAttempts int, now time.Time) (bool, error) {
	_, err := s.q.ConsumeMagicLinkCode(ctx, sqlc.ConsumeMagicLinkCodeParams{
		Now: now, Email: email, CodeHash: codeHash, MaxAttempts: int32(maxAttempts), //nolint:gosec // a small constant
	})
	if err == nil {
		return true, nil
	}
	if !db.IsNoRows(err) {
		return false, fmt.Errorf("consume code: %w", err)
	}
	if err := s.q.FailMagicLinkCodes(ctx, sqlc.FailMagicLinkCodesParams{Email: email, Now: now}); err != nil {
		return false, fmt.Errorf("count wrong code: %w", err)
	}
	return false, nil
}
