package oauth

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Client registered itself (RFC 7591): public, PKCE only, no secret.
type Client struct {
	ID           string
	Name         string
	RedirectURIs []string
	CreatedAt    time.Time
}

// Request is one authorization in progress: the client asked, the user has not
// answered yet. Only the browser that started it holds the binding.
type Request struct {
	ID            uuid.UUID
	ClientID      string
	RedirectURI   string
	State         *string
	CodeChallenge string
	Resource      *string
	BindingHash   string
	ExpiresAt     time.Time
}

// Code is what the user approved, waiting to be exchanged for tokens (60 seconds, once).
type Code struct {
	ClientID      string
	UserID        uuid.UUID
	RedirectURI   string
	CodeChallenge string
	Resource      *string
	Name          string
	Kind          auth.TokenKind
	AllowWrites   bool
	ExpiresAt     time.Time
}

type redemption int

const (
	redemptionNone redemption = iota
	redemptionFresh
	// redemptionReused: already exchanged; the tokens it gave are revoked (RFC 6749 §4.1.2).
	redemptionReused
)

type refreshOutcome int

const (
	refreshInvalid refreshOutcome = iota
	refreshRotated
	// refreshReused: a spent refresh token came back, so the connection is revoked.
	refreshReused
)

// Store is PostgresOAuthStore.
type Store struct {
	pool *pgxpool.Pool
	q    *sqlc.Queries
}

// NewStore wraps the pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool, q: sqlc.New(pool)}
}

func (s *Store) register(ctx context.Context, c Client) error {
	if err := s.q.CreateOAuthClient(ctx, sqlc.CreateOAuthClientParams{ID: c.ID, Name: c.Name, RedirectUris: c.RedirectURIs, CreatedAt: c.CreatedAt}); err != nil {
		return fmt.Errorf("register oauth client: %w", err)
	}
	return nil
}

func (s *Store) client(ctx context.Context, id string) (Client, bool, error) {
	row, err := s.q.OAuthClient(ctx, id)
	if err != nil {
		if db.IsNoRows(err) {
			return Client{}, false, nil
		}
		return Client{}, false, fmt.Errorf("oauth client: %w", err)
	}
	return Client{ID: row.ID, Name: row.Name, RedirectURIs: row.RedirectUris, CreatedAt: row.CreatedAt}, true, nil
}

func (s *Store) createRequest(ctx context.Context, r Request) error {
	err := s.q.CreateOAuthRequest(ctx, sqlc.CreateOAuthRequestParams{
		ID: r.ID, ClientID: r.ClientID, RedirectUri: r.RedirectURI, State: r.State, CodeChallenge: r.CodeChallenge,
		Resource: r.Resource, BindingHash: r.BindingHash, ExpiresAt: r.ExpiresAt,
	})
	if err != nil {
		return fmt.Errorf("create oauth request: %w", err)
	}
	return nil
}

// request is a request not yet answered and not expired.
func (s *Store) request(ctx context.Context, id uuid.UUID, now time.Time) (Request, bool, error) {
	row, err := s.q.OAuthRequest(ctx, sqlc.OAuthRequestParams{ID: id, Now: now})
	if err != nil {
		if db.IsNoRows(err) {
			return Request{}, false, nil
		}
		return Request{}, false, fmt.Errorf("oauth request: %w", err)
	}
	return Request{
		ID: row.ID, ClientID: row.ClientID, RedirectURI: row.RedirectUri, State: row.State, CodeChallenge: row.CodeChallenge,
		Resource: row.Resource, BindingHash: row.BindingHash, ExpiresAt: row.ExpiresAt,
	}, true, nil
}

// consumeRequest marks a live request answered; false when answered already or expired.
func (s *Store) consumeRequest(ctx context.Context, id uuid.UUID, now time.Time) (bool, error) {
	if _, err := s.q.ConsumeOAuthRequest(ctx, sqlc.ConsumeOAuthRequestParams{Now: now, ID: id}); err != nil {
		if db.IsNoRows(err) {
			return false, nil
		}
		return false, fmt.Errorf("consume oauth request: %w", err)
	}
	return true, nil
}

func (s *Store) createCode(ctx context.Context, c Code, hash string) error {
	err := s.q.CreateOAuthCode(ctx, sqlc.CreateOAuthCodeParams{
		CodeHash: hash, ClientID: c.ClientID, UserID: c.UserID, RedirectUri: c.RedirectURI, CodeChallenge: c.CodeChallenge,
		Resource: c.Resource, Name: c.Name, Kind: string(c.Kind), AllowWrites: c.AllowWrites, ExpiresAt: c.ExpiresAt,
	})
	if err != nil {
		return fmt.Errorf("create oauth code: %w", err)
	}
	return nil
}

// redeemCode marks the code used. None when unknown or expired.
func (s *Store) redeemCode(ctx context.Context, hash string, now time.Time) (Code, redemption, error) {
	var code Code
	outcome := redemptionNone
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		row, err := q.OAuthCodeForUpdate(ctx, hash)
		if err != nil {
			if db.IsNoRows(err) {
				return nil
			}
			return err
		}
		if row.ConsumedAt != nil {
			if row.AgentTokenID != nil {
				if err := revokeToken(ctx, q, *row.AgentTokenID, now); err != nil {
					return err
				}
			}
			outcome = redemptionReused
			return nil
		}
		kind, ok := auth.ParseTokenKind(row.Kind)
		if !row.ExpiresAt.After(now) || !ok {
			return nil
		}
		if err := q.ConsumeOAuthCode(ctx, sqlc.ConsumeOAuthCodeParams{Now: now, CodeHash: hash}); err != nil {
			return err
		}
		code = Code{
			ClientID: row.ClientID, UserID: row.UserID, RedirectURI: row.RedirectUri, CodeChallenge: row.CodeChallenge,
			Resource: row.Resource, Name: row.Name, Kind: kind, AllowWrites: row.AllowWrites, ExpiresAt: row.ExpiresAt,
		}
		outcome = redemptionFresh
		return nil
	})
	if err != nil {
		return Code{}, redemptionNone, fmt.Errorf("redeem oauth code: %w", err)
	}
	return code, outcome, nil
}

type issue struct {
	token            auth.AgentToken
	userID           uuid.UUID
	clientID         string
	codeHash         string
	accessHash       string
	accessExpiresAt  time.Time
	refreshHash      string
	refreshExpiresAt time.Time
}

// issue writes, in one transaction, the connection's agent_tokens row, its first
// refresh token, and the code pointing at the row (so a reused code can revoke it).
func (s *Store) issue(ctx context.Context, in issue) error {
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		if err := q.CreateOAuthAgentToken(ctx, sqlc.CreateOAuthAgentTokenParams{
			ID: in.token.ID, UserID: in.userID, Name: in.token.Name, Kind: string(in.token.Kind), TokenHash: in.accessHash,
			Scopes: auth.SortedScopes(in.token.Scopes), CreatedAt: in.token.CreatedAt, ExpiresAt: in.accessExpiresAt, ClientID: in.clientID,
		}); err != nil {
			return err
		}
		if err := q.CreateOAuthRefreshToken(ctx, sqlc.CreateOAuthRefreshTokenParams{
			TokenHash: in.refreshHash, AgentTokenID: in.token.ID, ClientID: in.clientID, ExpiresAt: in.refreshExpiresAt,
		}); err != nil {
			return err
		}
		return q.LinkOAuthCodeToken(ctx, sqlc.LinkOAuthCodeTokenParams{AgentTokenID: in.token.ID, CodeHash: in.codeHash})
	})
	if err != nil {
		return fmt.Errorf("issue oauth tokens: %w", err)
	}
	return nil
}

type rotation struct {
	refreshHash      string
	clientID         string
	now              time.Time
	accessHash       string
	accessExpiresAt  time.Time
	newRefreshHash   string
	refreshExpiresAt time.Time
}

func (s *Store) rotate(ctx context.Context, in rotation) ([]auth.Scope, refreshOutcome, error) {
	var scopes []auth.Scope
	outcome := refreshInvalid
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		row, err := q.OAuthRefreshForUpdate(ctx, in.refreshHash)
		if err != nil {
			if db.IsNoRows(err) {
				return nil
			}
			return err
		}
		if row.ConsumedAt != nil {
			if err := revokeToken(ctx, q, row.AgentTokenID, in.now); err != nil {
				return err
			}
			outcome = refreshReused
			return nil
		}
		if row.ClientID != in.clientID || !row.ExpiresAt.After(in.now) || row.RevokedAt != nil {
			return nil
		}
		if err := q.ConsumeOAuthRefresh(ctx, sqlc.ConsumeOAuthRefreshParams{Now: in.now, TokenHash: in.refreshHash}); err != nil {
			return err
		}
		if err := q.CreateOAuthRefreshToken(ctx, sqlc.CreateOAuthRefreshTokenParams{
			TokenHash: in.newRefreshHash, AgentTokenID: row.AgentTokenID, ClientID: in.clientID, ExpiresAt: in.refreshExpiresAt,
		}); err != nil {
			return err
		}
		if err := q.RotateOAuthAccess(ctx, sqlc.RotateOAuthAccessParams{TokenHash: in.accessHash, ExpiresAt: in.accessExpiresAt, ID: row.AgentTokenID}); err != nil {
			return err
		}
		for _, raw := range row.Scopes {
			switch sc := auth.Scope(raw); sc {
			case auth.ScopeLibraryRead, auth.ScopeLibraryWrite, auth.ScopeScrobbleWrite, auth.ScopeImportsWrite:
				scopes = append(scopes, sc)
			}
		}
		outcome = refreshRotated
		return nil
	})
	if err != nil {
		return nil, refreshInvalid, fmt.Errorf("rotate oauth refresh: %w", err)
	}
	return scopes, outcome, nil
}

// revoke revokes the connection an access or refresh token belongs to. Unknown tokens are ignored.
func (s *Store) revoke(ctx context.Context, tokenHash string, now time.Time) error {
	id, err := s.q.OAuthConnectionForToken(ctx, tokenHash)
	if err != nil {
		if db.IsNoRows(err) {
			return nil
		}
		return fmt.Errorf("oauth connection: %w", err)
	}
	return revokeToken(ctx, s.q, id, now)
}

// revokeToken is what Settings' revoke does: the token stops at once and its waiting plans expire with it.
func revokeToken(ctx context.Context, q *sqlc.Queries, id uuid.UUID, now time.Time) error {
	if err := q.RevokeAgentTokenByID(ctx, sqlc.RevokeAgentTokenByIDParams{Now: now, ID: id}); err != nil {
		return fmt.Errorf("revoke agent token: %w", err)
	}
	if err := q.ExpireAgentTokenPlans(ctx, sqlc.ExpireAgentTokenPlansParams{Now: now, AgentTokenID: id}); err != nil {
		return fmt.Errorf("expire plans: %w", err)
	}
	return nil
}
