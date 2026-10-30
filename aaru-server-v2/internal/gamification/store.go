package gamification

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Origin is where an award was evaluated (BadgeOrigin): a live write (toast), an import or
// approved plan (one summary), or the first run over a user's existing library (one summary).
type Origin string

// The origins.
const (
	OriginLive     Origin = "live"
	OriginBatch    Origin = "batch"
	OriginBackfill Origin = "backfill"
)

func (o Origin) valid() bool {
	return o == OriginLive || o == OriginBatch || o == OriginBackfill
}

// PointsEvent is one ledger row as "How you earned it" lists it.
type PointsEvent struct {
	ID        uuid.UUID
	Kind      string
	Points    int
	TitleID   *uuid.UUID
	LocalDate string
	CreatedAt time.Time
	// IsRevocation is a revocation (an undo, a short friendship).
	IsRevocation bool
}

// EarnedBadge is one earned badge tier.
type EarnedBadge struct {
	ID        uuid.UUID
	Badge     string
	Tier      int
	AwardedAt time.Time
	Origin    Origin
	ActionID  *uuid.UUID
	SeenAt    *time.Time
}

// TierDue is a badge tier to insert.
type TierDue struct {
	Badge string
	Tier  int
}

// Dirty is a user the gamification worker should evaluate, and why (DirtyProgress).
type Dirty struct {
	UserID uuid.UUID
	Origin Origin
	// Fresh is never evaluated: the first run backfills streak days from live ticks.
	Fresh bool
}

// store is PostgresGamificationStore over any connection or transaction.
type store struct {
	db sqlc.DBTX
	q  *sqlc.Queries
}

func newStore(db sqlc.DBTX) store {
	return store{db: db, q: sqlc.New(db)}
}

// zone is the request's zone (stored for later requests that send none), else the stored
// zone, else UTC.
func (s store) zone(ctx context.Context, userID uuid.UUID, requested *time.Location) (*time.Location, error) {
	if requested != nil {
		if err := s.q.GamificationStoreZone(ctx, sqlc.GamificationStoreZoneParams{UserID: userID, TimeZone: requested.String()}); err != nil {
			return nil, fmt.Errorf("store time zone: %w", err)
		}
		return requested, nil
	}
	rows, err := s.q.GamificationStoredZone(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("stored time zone: %w", err)
	}
	if len(rows) > 0 && rows[0] != nil && *rows[0] != "" && *rows[0] != "Local" {
		if loc, err := time.LoadLocation(*rows[0]); err == nil {
			return loc, nil
		}
	}
	return time.UTC, nil
}

func (s store) markStreakDay(ctx context.Context, userID uuid.UUID, loc *time.Location, now time.Time) error {
	err := s.q.GamificationMarkStreakDay(ctx, sqlc.GamificationMarkStreakDayParams{
		UserID: userID, LocalDate: core.LocalDate(now, loc), TimeZone: loc.String(), FirstAt: now,
	})
	if err != nil {
		return fmt.Errorf("mark streak day: %w", err)
	}
	return nil
}

func (s store) lastEvents(ctx context.Context, userID uuid.UUID, roots []string) (map[string]sqlc.GamificationLastEventsRow, error) {
	rows, err := s.q.GamificationLastEvents(ctx, sqlc.GamificationLastEventsParams{UserID: userID, Roots: roots})
	if err != nil {
		return nil, fmt.Errorf("last points events: %w", err)
	}
	out := make(map[string]sqlc.GamificationLastEventsRow, len(rows))
	for _, row := range rows {
		if _, ok := out[row.DedupeRoot]; !ok {
			out[row.DedupeRoot] = row
		}
	}
	return out, nil
}

func (s store) addToTotal(ctx context.Context, userID uuid.UUID, delta int) error {
	if delta == 0 {
		return nil
	}
	if err := s.q.GamificationAddToTotal(ctx, sqlc.GamificationAddToTotalParams{UserID: userID, TotalPoints: int32(delta)}); err != nil { //nolint:gosec // a batch of awards
		return fmt.Errorf("add to total: %w", err)
	}
	return nil
}

// insertAwardsSQL is GamificationInsertAwards; written with pgx because sqlc rejects a
// multi-array unnest.
const insertAwardsSQL = `
INSERT INTO points_events (id, user_id, kind, points, dedupe_root, seq, dedupe_key, title_id, action_id,
    local_date, time_zone, created_at)
SELECT k.id, $1, k.kind, k.points, k.root, k.seq, k.root || '#' || k.seq,
    NULLIF(k.title, '')::uuid, NULLIF(k.action, '')::uuid, $2::date, $3, $4
FROM unnest($5::uuid[], $6::text[], $7::int[], $8::text[], $9::int[], $10::text[], $11::text[])
    AS k(id, kind, points, root, seq, title, action)
ON CONFLICT (user_id, dedupe_key) DO NOTHING
RETURNING points`

// award writes the awards whose root has no active award (or no event at all, for once-only
// kinds), trimmed to each kind's daily cap. A capped award is still written at 0 points, so the
// root stays spent. It returns the points actually added.
func (s store) award(ctx context.Context, awards []Award, userID uuid.UUID, loc *time.Location, now time.Time) (int, error) {
	seen := map[string]bool{}
	var unique []Award
	for _, a := range awards {
		if !seen[a.Root] {
			seen[a.Root] = true
			unique = append(unique, a)
		}
	}
	if len(unique) == 0 {
		return 0, nil
	}
	roots := make([]string, len(unique))
	for i, a := range unique {
		roots[i] = a.Root
	}
	last, err := s.lastEvents(ctx, userID, roots)
	if err != nil {
		return 0, err
	}
	var due []Award
	for _, a := range unique {
		event, ok := last[a.Root]
		if !ok || (event.Revoked && !a.Kind.OncePerRoot()) {
			due = append(due, a)
		}
	}
	if len(due) == 0 {
		return 0, nil
	}
	date := core.LocalDate(now, loc)
	var capped []string
	cappedSeen := map[Kind]bool{}
	for _, a := range due {
		if _, ok := a.Kind.DailyCap(); ok && !cappedSeen[a.Kind] {
			cappedSeen[a.Kind] = true
			capped = append(capped, string(a.Kind))
		}
	}
	remaining := map[Kind]int{}
	if len(capped) > 0 {
		rows, err := s.q.GamificationEarnedToday(ctx, sqlc.GamificationEarnedTodayParams{UserID: userID, LocalDate: date, Kinds: capped})
		if err != nil {
			return 0, fmt.Errorf("points earned today: %w", err)
		}
		for _, row := range rows {
			if _, ok := remaining[Kind(row.Kind)]; !ok {
				remaining[Kind(row.Kind)] = int(row.Total)
			}
		}
	}
	for i := range due {
		limit, ok := due[i].Kind.DailyCap()
		if !ok {
			continue
		}
		left := max(0, limit-remaining[due[i].Kind])
		due[i].Points = min(due[i].Points, left)
		remaining[due[i].Kind] += due[i].Points
	}
	n := len(due)
	ids, kinds, points, dueRoots, seqs, titles, actions :=
		make([]uuid.UUID, n), make([]string, n), make([]int32, n), make([]string, n), make([]int32, n), make([]string, n), make([]string, n)
	for i, a := range due {
		ids[i], kinds[i], points[i], dueRoots[i] = uuid.New(), string(a.Kind), int32(a.Points), a.Root //nolint:gosec // at most 1,000
		seq := int32(1)
		if event, ok := last[a.Root]; ok {
			seq = event.Seq + 1
		}
		seqs[i] = seq
		if a.TitleID != nil {
			titles[i] = upper(*a.TitleID)
		}
		if a.ActionID != nil {
			actions[i] = upper(*a.ActionID)
		}
	}
	rows, err := s.db.Query(ctx, insertAwardsSQL, userID, date, loc.String(), now, ids, kinds, points, dueRoots, seqs, titles, actions)
	if err != nil {
		return 0, fmt.Errorf("insert points events: %w", err)
	}
	written, err := pgx.CollectRows(rows, pgx.RowTo[int32])
	if err != nil {
		return 0, fmt.Errorf("insert points events: %w", err)
	}
	total := 0
	for _, p := range written {
		total += int(p)
	}
	return total, s.addToTotal(ctx, userID, total)
}

// revoke writes the negative of each root's active award. It returns the points taken back.
func (s store) revoke(ctx context.Context, roots []string, userID uuid.UUID) (int, error) {
	seen := map[string]bool{}
	var unique []string
	for _, r := range roots {
		if !seen[r] {
			seen[r] = true
			unique = append(unique, r)
		}
	}
	last, err := s.lastEvents(ctx, userID, unique)
	if err != nil {
		return 0, err
	}
	var active []uuid.UUID
	for _, event := range last {
		if !event.Revoked {
			active = append(active, event.ID)
		}
	}
	if len(active) == 0 {
		return 0, nil
	}
	written, err := s.q.GamificationRevoke(ctx, active)
	if err != nil {
		return 0, fmt.Errorf("revoke points: %w", err)
	}
	total := 0
	for _, p := range written {
		total += int(p)
	}
	return total, s.addToTotal(ctx, userID, total)
}

func (s store) totalPoints(ctx context.Context, userID uuid.UUID) (int, error) {
	rows, err := s.q.GamificationTotalPoints(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("total points: %w", err)
	}
	if len(rows) == 0 {
		return 0, nil
	}
	return int(rows[0]), nil
}

// rebuildTotal sums the ledger and stores it as the cached total.
func (s store) rebuildTotal(ctx context.Context, userID uuid.UUID) (int, error) {
	total, err := s.q.GamificationLedgerSum(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("ledger sum: %w", err)
	}
	if err := s.q.GamificationSetTotal(ctx, sqlc.GamificationSetTotalParams{UserID: userID, TotalPoints: total}); err != nil {
		return 0, fmt.Errorf("set total: %w", err)
	}
	return int(total), nil
}

func (s store) boardPoints(ctx context.Context, userID uuid.UUID, from, until string) (int, error) {
	total, err := s.q.GamificationBoardPoints(ctx, sqlc.GamificationBoardPointsParams{
		UserID: userID, FromDate: from, UntilDate: until, OffBoard: OffBoardKinds(),
	})
	if err != nil {
		return 0, fmt.Errorf("board points: %w", err)
	}
	return int(total), nil
}

func (s store) streakDays(ctx context.Context, userID uuid.UUID) ([]core.StreakDay, error) {
	rows, err := s.q.GamificationStreakDays(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("streak days: %w", err)
	}
	days := make([]core.StreakDay, len(rows))
	for i, row := range rows {
		days[i] = core.StreakDay{Date: row.LocalDate, TimeZone: row.TimeZone, FirstAt: row.FirstAt}
	}
	return days, nil
}

func badgeFromRow(row sqlc.GamificationBadgesRow) (EarnedBadge, bool) {
	origin := Origin(row.Origin)
	if !origin.valid() {
		return EarnedBadge{}, false
	}
	return EarnedBadge{
		ID: row.ID, Badge: row.Badge, Tier: int(row.Tier), AwardedAt: row.AwardedAt, Origin: origin,
		ActionID: row.ActionID, SeenAt: row.SeenAt,
	}, true
}

func (s store) badges(ctx context.Context, userID uuid.UUID) ([]EarnedBadge, error) {
	rows, err := s.q.GamificationBadges(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("badges: %w", err)
	}
	var out []EarnedBadge
	for _, row := range rows {
		if b, ok := badgeFromRow(row); ok {
			out = append(out, b)
		}
	}
	return out, nil
}

// insertBadgesSQL is GamificationInsertBadges; written with pgx because sqlc rejects a
// multi-array unnest.
const insertBadgesSQL = `
INSERT INTO user_badges (id, user_id, badge, tier, awarded_at, origin, action_id)
SELECT k.id, $1, k.badge, k.tier, $2, $3, $4
FROM unnest($5::uuid[], $6::text[], $7::int[]) AS k(id, badge, tier)
ON CONFLICT (user_id, badge, tier) DO NOTHING
RETURNING id, badge, tier, awarded_at, origin, action_id, seen_at`

// insertBadges inserts tiers not yet earned and returns the rows it wrote.
func (s store) insertBadges(ctx context.Context, due []TierDue, userID uuid.UUID, origin Origin, actionID *uuid.UUID, now time.Time) ([]EarnedBadge, error) {
	if len(due) == 0 {
		return nil, nil
	}
	ids, names, tiers := make([]uuid.UUID, len(due)), make([]string, len(due)), make([]int32, len(due))
	for i, d := range due {
		ids[i], names[i], tiers[i] = uuid.New(), d.Badge, int32(d.Tier) //nolint:gosec // 1…4
	}
	rows, err := s.db.Query(ctx, insertBadgesSQL, userID, now, string(origin), actionID, ids, names, tiers)
	if err != nil {
		return nil, fmt.Errorf("insert badges: %w", err)
	}
	written, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (sqlc.GamificationBadgesRow, error) {
		var b sqlc.GamificationBadgesRow
		err := row.Scan(&b.ID, &b.Badge, &b.Tier, &b.AwardedAt, &b.Origin, &b.ActionID, &b.SeenAt)
		return b, err
	})
	if err != nil {
		return nil, fmt.Errorf("insert badges: %w", err)
	}
	var out []EarnedBadge
	for _, row := range written {
		if b, ok := badgeFromRow(row); ok {
			out = append(out, b)
		}
	}
	return out, nil
}

func (s store) deleteBadges(ctx context.Context, ids []uuid.UUID, userID uuid.UUID) error {
	if len(ids) == 0 {
		return nil
	}
	if err := s.q.GamificationDeleteBadges(ctx, sqlc.GamificationDeleteBadgesParams{UserID: userID, Ids: ids}); err != nil {
		return fmt.Errorf("delete badges: %w", err)
	}
	return nil
}

func (s store) isFresh(ctx context.Context, userID uuid.UUID) (bool, error) {
	rows, err := s.q.GamificationEvaluatedAt(ctx, userID)
	if err != nil {
		return false, fmt.Errorf("evaluated at: %w", err)
	}
	return len(rows) == 0 || rows[0] == nil, nil
}

func (s store) markDirty(ctx context.Context, userID uuid.UUID, origin Origin) error {
	if err := s.q.GamificationMarkDirty(ctx, sqlc.GamificationMarkDirtyParams{UserID: userID, Origin: string(origin)}); err != nil {
		return fmt.Errorf("mark dirty: %w", err)
	}
	return nil
}
