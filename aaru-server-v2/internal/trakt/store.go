package trakt

import (
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Connection is a user's Trakt connection, tokens still sealed (TraktConnectionRecord).
type Connection struct {
	SealedAccessToken  string
	SealedRefreshToken string
	ExpiresAt          time.Time
	Username           *string
	ConnectedAt        time.Time
}

// AuthRequest is one sign-in in flight.
type AuthRequest struct {
	UserID       uuid.UUID
	CodeVerifier string
	ReturnTo     string
}

// Store is PostgresTraktStore.
type Store struct {
	Pool *pgxpool.Pool
	q    *sqlc.Queries
}

// NewStore builds the store over the pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{Pool: pool, q: sqlc.New(pool)} }

// CreateAuthRequest records a sign-in by the hash of its state.
func (s *Store) CreateAuthRequest(ctx context.Context, stateHash string, r AuthRequest, expiresAt time.Time) error {
	if err := s.q.TraktCreateAuthRequest(ctx, sqlc.TraktCreateAuthRequestParams{
		StateHash: stateHash, UserID: r.UserID, CodeVerifier: r.CodeVerifier, ReturnTo: r.ReturnTo, ExpiresAt: expiresAt,
	}); err != nil {
		return fmt.Errorf("trakt auth request: %w", err)
	}
	return nil
}

// ConsumeAuthRequest is single use: it returns the request and deletes it. nil when unknown or expired.
func (s *Store) ConsumeAuthRequest(ctx context.Context, stateHash string, now time.Time) (*AuthRequest, error) {
	rows, err := s.q.TraktConsumeAuthRequest(ctx, stateHash)
	if err != nil {
		return nil, fmt.Errorf("consume trakt auth request: %w", err)
	}
	if len(rows) == 0 || !rows[0].ExpiresAt.After(now) {
		return nil, nil //nolint:nilnil // unknown or expired
	}
	return &AuthRequest{UserID: rows[0].UserID, CodeVerifier: rows[0].CodeVerifier, ReturnTo: rows[0].ReturnTo}, nil
}

// SaveConnection saves the tokens; a username Trakt did not give keeps the one known.
func (s *Store) SaveConnection(ctx context.Context, c Connection, user uuid.UUID) error {
	if err := s.q.TraktSaveConnection(ctx, sqlc.TraktSaveConnectionParams{
		UserID: user, AccessToken: c.SealedAccessToken, RefreshToken: c.SealedRefreshToken, ExpiresAt: c.ExpiresAt,
		Username: c.Username, ConnectedAt: c.ConnectedAt,
	}); err != nil {
		return fmt.Errorf("save trakt connection: %w", err)
	}
	return nil
}

// Connection is the user's connection, nil when not connected.
func (s *Store) Connection(ctx context.Context, user uuid.UUID) (*Connection, error) {
	rows, err := s.q.TraktConnection(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("trakt connection: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil //nolint:nilnil // not connected
	}
	r := rows[0]
	return &Connection{
		SealedAccessToken: r.AccessToken, SealedRefreshToken: r.RefreshToken, ExpiresAt: r.ExpiresAt,
		Username: r.Username, ConnectedAt: r.ConnectedAt,
	}, nil
}

// RefreshConnection runs refresh with the connection locked, and stores what it returns when it
// changed. Trakt's refresh tokens are single use, so a second caller waits and sees the first's.
// refresh returns changed false to keep the connection as it is.
func (s *Store) RefreshConnection(ctx context.Context, user uuid.UUID,
	refresh func(current Connection) (next Connection, changed bool, err error),
) (*Connection, error) {
	var out *Connection
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		rows, err := q.TraktConnectionForUpdate(ctx, user)
		if err != nil {
			return fmt.Errorf("lock trakt connection: %w", err)
		}
		if len(rows) == 0 {
			return nil
		}
		r := rows[0]
		current := Connection{
			SealedAccessToken: r.AccessToken, SealedRefreshToken: r.RefreshToken, ExpiresAt: r.ExpiresAt,
			Username: r.Username, ConnectedAt: r.ConnectedAt,
		}
		next, changed, err := refresh(current)
		if err != nil {
			return err
		}
		if !changed {
			out = &current
			return nil
		}
		if err := q.TraktUpdateTokens(ctx, sqlc.TraktUpdateTokensParams{
			UserID: user, AccessToken: next.SealedAccessToken, RefreshToken: next.SealedRefreshToken, ExpiresAt: next.ExpiresAt,
		}); err != nil {
			return fmt.Errorf("update trakt tokens: %w", err)
		}
		out = &next
		return nil
	})
	return out, err
}

// DeleteConnection forgets the user's tokens.
func (s *Store) DeleteConnection(ctx context.Context, user uuid.UUID) error {
	if err := s.q.TraktDeleteConnection(ctx, user); err != nil {
		return fmt.Errorf("delete trakt connection: %w", err)
	}
	return nil
}
