package mal

import (
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Connection is a user's MyAnimeList connection, tokens still sealed (MALConnectionRecord).
type Connection struct {
	SealedAccessToken  string
	SealedRefreshToken string
	ExpiresAt          time.Time
	Username           *string
	ConnectedAt        time.Time
	// RevokedAt is set when MAL refused the tokens; pushing stops until the user connects again.
	RevokedAt *time.Time
	// PulledAt is when Aaru last read the MAL list back (SCR-010).
	PulledAt *time.Time
}

// AuthRequest is one MAL sign-in in flight. MAL takes only the `plain` PKCE method, so the
// verifier is also the challenge; it still never leaves the server before the browser comes back.
type AuthRequest struct {
	UserID       uuid.UUID
	CodeVerifier string
	ReturnTo     string
}

// ListStatus is MAL's list statuses.
type ListStatus string

// MAL's list statuses.
const (
	Watching    ListStatus = "watching"
	Completed   ListStatus = "completed"
	OnHold      ListStatus = "on_hold"
	Dropped     ListStatus = "dropped"
	PlanToWatch ListStatus = "plan_to_watch"
)

// ParseListStatus is a status MAL writes; false for one Aaru does not know.
func ParseListStatus(raw string) (ListStatus, bool) {
	switch s := ListStatus(raw); s {
	case Watching, Completed, OnHold, Dropped, PlanToWatch:
		return s, true
	}
	return "", false
}

// EntryState is what Aaru and MAL last agreed on for one MAL entry: what Aaru pushed, or (SCR-010)
// read. A push sends only when Aaru's state differs, so the same state is never sent twice.
type EntryState struct {
	MalID    string
	Status   ListStatus
	Episodes int
	Score    int
}

// PushDue is a connection with library writes newer than its push cursor.
type PushDue struct {
	UserID uuid.UUID
	Cursor time.Time
}

// PullDue is a connection due a read of its MAL list (SCR-010): a client asked, or the last read
// is old.
type PullDue struct {
	UserID uuid.UUID
	// Cursor: entries MAL changed after this are new to Aaru. It starts at the connection time, so
	// only changes made after connecting come across.
	Cursor time.Time
	// FullRead: the whole list is read this time, to find entries removed on MAL.
	FullRead bool
}

// RemovedEntry is an entry Aaru knew on MAL that MAL no longer lists. Shown in settings; Aaru
// keeps its item.
type RemovedEntry struct {
	MalID     string
	Title     *string
	RemovedAt time.Time
}

// Store is PostgresMALStore.
type Store struct {
	Pool *pgxpool.Pool
	q    *sqlc.Queries
}

// NewStore builds the store over the pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{Pool: pool, q: sqlc.New(pool)} }

// CreateAuthRequest records a sign-in by the hash of its state.
func (s *Store) CreateAuthRequest(ctx context.Context, stateHash string, r AuthRequest, expiresAt time.Time) error {
	if err := s.q.MALCreateAuthRequest(ctx, sqlc.MALCreateAuthRequestParams{
		StateHash: stateHash, UserID: r.UserID, CodeVerifier: r.CodeVerifier, ReturnTo: r.ReturnTo, ExpiresAt: expiresAt,
	}); err != nil {
		return fmt.Errorf("mal auth request: %w", err)
	}
	return nil
}

// ConsumeAuthRequest is single use: it returns the request and deletes it. nil when unknown or expired.
func (s *Store) ConsumeAuthRequest(ctx context.Context, stateHash string, now time.Time) (*AuthRequest, error) {
	rows, err := s.q.MALConsumeAuthRequest(ctx, stateHash)
	if err != nil {
		return nil, fmt.Errorf("consume mal auth request: %w", err)
	}
	if len(rows) == 0 || !rows[0].ExpiresAt.After(now) {
		return nil, nil //nolint:nilnil // unknown or expired
	}
	return &AuthRequest{UserID: rows[0].UserID, CodeVerifier: rows[0].CodeVerifier, ReturnTo: rows[0].ReturnTo}, nil
}

// SaveConnection saves the tokens and clears a revocation. A first connection starts pushing from
// cursor; connecting again keeps the cursor it had.
func (s *Store) SaveConnection(ctx context.Context, c Connection, cursor time.Time, user uuid.UUID) error {
	if err := s.q.MALSaveConnection(ctx, sqlc.MALSaveConnectionParams{
		UserID: user, AccessToken: c.SealedAccessToken, RefreshToken: c.SealedRefreshToken, ExpiresAt: c.ExpiresAt,
		Username: c.Username, ConnectedAt: c.ConnectedAt, PushCursor: cursor,
	}); err != nil {
		return fmt.Errorf("save mal connection: %w", err)
	}
	return nil
}

func connectionOf(r sqlc.MALConnectionRow) Connection {
	return Connection{
		SealedAccessToken: r.AccessToken, SealedRefreshToken: r.RefreshToken, ExpiresAt: r.ExpiresAt,
		Username: r.Username, ConnectedAt: r.ConnectedAt, RevokedAt: r.RevokedAt, PulledAt: r.PulledAt,
	}
}

// Connection is the user's connection, nil when not connected.
func (s *Store) Connection(ctx context.Context, user uuid.UUID) (*Connection, error) {
	rows, err := s.q.MALConnection(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("mal connection: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil //nolint:nilnil // not connected
	}
	c := connectionOf(rows[0])
	return &c, nil
}

// RefreshConnection runs refresh with the connection locked, and stores the tokens it returns
// when changed.
func (s *Store) RefreshConnection(ctx context.Context, user uuid.UUID,
	refresh func(current Connection) (next Connection, changed bool, err error),
) (*Connection, error) {
	var out *Connection
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		rows, err := q.MALConnectionForUpdate(ctx, user)
		if err != nil {
			return fmt.Errorf("lock mal connection: %w", err)
		}
		if len(rows) == 0 {
			return nil
		}
		current := connectionOf(sqlc.MALConnectionRow(rows[0]))
		next, changed, err := refresh(current)
		if err != nil {
			return err
		}
		if !changed {
			out = &current
			return nil
		}
		if err := q.MALUpdateTokens(ctx, sqlc.MALUpdateTokensParams{
			UserID: user, AccessToken: next.SealedAccessToken, RefreshToken: next.SealedRefreshToken, ExpiresAt: next.ExpiresAt,
		}); err != nil {
			return fmt.Errorf("update mal tokens: %w", err)
		}
		out = &next
		return nil
	})
	return out, err
}

// DeleteConnection forgets the tokens and what Aaru and MAL agreed on.
func (s *Store) DeleteConnection(ctx context.Context, user uuid.UUID) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		if err := q.MALDeleteEntryStates(ctx, user); err != nil {
			return fmt.Errorf("delete mal entry states: %w", err)
		}
		if err := q.MALDeleteConnection(ctx, user); err != nil {
			return fmt.Errorf("delete mal connection: %w", err)
		}
		return nil
	})
}

// MarkRevoked stops pushing until the user connects again.
func (s *Store) MarkRevoked(ctx context.Context, user uuid.UUID, revokedAt time.Time) error {
	if err := s.q.MALMarkRevoked(ctx, sqlc.MALMarkRevokedParams{UserID: user, RevokedAt: &revokedAt}); err != nil {
		return fmt.Errorf("mark mal revoked: %w", err)
	}
	return nil
}

// PushesDue are connections with library writes past their cursor.
func (s *Store) PushesDue(ctx context.Context) ([]PushDue, error) {
	rows, err := s.q.MALPushesDue(ctx)
	if err != nil {
		return nil, fmt.Errorf("mal pushes due: %w", err)
	}
	out := make([]PushDue, len(rows))
	for i, r := range rows {
		out[i] = PushDue{UserID: r.UserID, Cursor: r.PushCursor}
	}
	return out, nil
}

// AdvanceCursor moves the push cursor forward, never back.
func (s *Store) AdvanceCursor(ctx context.Context, user uuid.UUID, cursor time.Time) error {
	if err := s.q.MALAdvanceCursor(ctx, sqlc.MALAdvanceCursorParams{UserID: user, Cursor: cursor}); err != nil {
		return fmt.Errorf("advance mal cursor: %w", err)
	}
	return nil
}

// EntryStates are the states last agreed for these MAL ids, by id.
func (s *Store) EntryStates(ctx context.Context, user uuid.UUID, malIDs []string) (map[string]EntryState, error) {
	out := map[string]EntryState{}
	if len(malIDs) == 0 {
		return out, nil
	}
	unique := slices.Compact(slices.Sorted(slices.Values(malIDs)))
	rows, err := s.q.MALEntryStates(ctx, sqlc.MALEntryStatesParams{UserID: user, MalIds: unique})
	if err != nil {
		return nil, fmt.Errorf("mal entry states: %w", err)
	}
	for _, r := range rows {
		status, ok := ParseListStatus(r.Status)
		if _, seen := out[r.MalID]; !ok || seen {
			continue
		}
		out[r.MalID] = EntryState{MalID: r.MalID, Status: status, Episodes: int(r.Episodes), Score: int(r.Score)}
	}
	return out, nil
}

// SaveEntryState records what Aaru and MAL now agree on. A nil title keeps the one known.
func (s *Store) SaveEntryState(ctx context.Context, state EntryState, title *string, user uuid.UUID) error {
	if err := s.q.MALSaveEntryState(ctx, sqlc.MALSaveEntryStateParams{
		UserID: user, MalID: state.MalID, Status: string(state.Status),
		Episodes: int32(state.Episodes), Score: int32(state.Score), Title: title, //nolint:gosec // MAL counts
	}); err != nil {
		return fmt.Errorf("save mal entry state: %w", err)
	}
	return nil
}

// MARK: Reading back (SCR-010)

// RequestPull asks for a read on the next pass, unless the list was read after notBefore. False
// when nothing was asked.
func (s *Store) RequestPull(ctx context.Context, user uuid.UUID, now, notBefore time.Time) (bool, error) {
	rows, err := s.q.MALRequestPull(ctx, sqlc.MALRequestPullParams{UserID: user, Now: now, NotBefore: notBefore})
	if err != nil {
		return false, fmt.Errorf("request mal pull: %w", err)
	}
	return len(rows) > 0, nil
}

// ClaimPulls takes up to limit connections due a read, asked-for reads first.
func (s *Store) ClaimPulls(ctx context.Context, now, staleBefore, fullBefore time.Time, limit int) ([]PullDue, error) {
	rows, err := s.q.MALClaimPulls(ctx, sqlc.MALClaimPullsParams{
		Now: now, StaleBefore: staleBefore, FullBefore: fullBefore, MaxRows: int32(limit), //nolint:gosec // small
	})
	if err != nil {
		return nil, fmt.Errorf("claim mal pulls: %w", err)
	}
	out := make([]PullDue, len(rows))
	for i, r := range rows {
		out[i] = PullDue{UserID: r.UserID, Cursor: r.Cursor, FullRead: r.FullRead}
	}
	return out, nil
}

// FinishPull moves the read cursor forward and records a full read.
func (s *Store) FinishPull(ctx context.Context, user uuid.UUID, cursor time.Time, fullReadAt *time.Time) error {
	if err := s.q.MALFinishPull(ctx, sqlc.MALFinishPullParams{UserID: user, Cursor: cursor, FullReadAt: fullReadAt}); err != nil {
		return fmt.Errorf("finish mal pull: %w", err)
	}
	return nil
}

// MarkRemoved marks every agreed entry MAL no longer lists, and clears the mark on those it lists again.
func (s *Store) MarkRemoved(ctx context.Context, user uuid.UUID, listed []string, now time.Time) error {
	unique := slices.Compact(slices.Sorted(slices.Values(listed)))
	if unique == nil {
		unique = []string{}
	}
	if err := s.q.MALMarkRemoved(ctx, sqlc.MALMarkRemovedParams{UserID: user, Listed: unique, Now: now}); err != nil {
		return fmt.Errorf("mark mal removed: %w", err)
	}
	return nil
}

// RemovedEntries are entries removed on MAL, newest first, at most 100.
func (s *Store) RemovedEntries(ctx context.Context, user uuid.UUID) ([]RemovedEntry, error) {
	rows, err := s.q.MALRemovedEntries(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("mal removed entries: %w", err)
	}
	out := make([]RemovedEntry, len(rows))
	for i, r := range rows {
		out[i] = RemovedEntry{MalID: r.MalID, Title: r.Title, RemovedAt: r.RemovedAt}
	}
	return out, nil
}
