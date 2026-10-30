package plans

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/library"
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// The plan store (PostgresPlanStore).

type planRow sqlc.PlanByIDRow

// plan reads a row; nil for a status this server does not know (Swift's compactMap).
func (r planRow) plan() (*Plan, error) {
	status := Status(r.Status)
	if !status.valid() {
		return nil, nil //nolint:nilnil // skipped, as Swift dropped it
	}
	changes, err := decodeChanges(r.Changes)
	if err != nil {
		return nil, err
	}
	var counts Counts
	if err := json.Unmarshal(r.Counts, &counts); err != nil {
		return nil, fmt.Errorf("plan counts: %w", err)
	}
	var op library.Op
	if err := json.Unmarshal(r.Op, &op); err != nil {
		return nil, fmt.Errorf("plan op: %w", err)
	}
	basis, err := decodeBasis(r.Basis)
	if err != nil {
		return nil, err
	}
	return &Plan{
		ID: r.ID, AgentTokenID: r.AgentTokenID, AgentName: r.AgentName, Status: status, Summary: r.Summary,
		Changes: changes, Counts: counts, Op: op, Basis: basis, CreatedAt: r.CreatedAt.UTC(), ExpiresAt: r.ExpiresAt.UTC(),
		DecidedAt: utc(r.DecidedAt), ActionID: r.ActionID,
	}, nil
}

func utc(t *time.Time) *time.Time {
	if t == nil {
		return nil
	}
	u := t.UTC()
	return &u
}

func (s *Service) create(ctx context.Context, p Plan, user uuid.UUID) error {
	changes, err := encodeChanges(p.Changes)
	if err != nil {
		return err
	}
	counts, err := json.Marshal(p.Counts)
	if err != nil {
		return fmt.Errorf("plan counts: %w", err)
	}
	op, err := json.Marshal(p.Op)
	if err != nil {
		return fmt.Errorf("plan op: %w", err)
	}
	basis, err := encodeBasis(p.Basis)
	if err != nil {
		return err
	}
	err = s.q.PlanCreate(ctx, sqlc.PlanCreateParams{
		ID: p.ID, UserID: user, AgentTokenID: p.AgentTokenID, AgentName: p.AgentName, Status: string(p.Status),
		Summary: p.Summary, Changes: changes, Counts: counts, Op: op, Basis: basis, CreatedAt: p.CreatedAt,
		ExpiresAt: p.ExpiresAt,
	})
	if err != nil {
		return fmt.Errorf("create plan: %w", err)
	}
	return nil
}

func plansFrom(rows []planRow) ([]Plan, error) {
	out := make([]Plan, 0, len(rows))
	for _, r := range rows {
		p, err := r.plan()
		if err != nil {
			return nil, err
		}
		if p != nil {
			out = append(out, *p)
		}
	}
	return out, nil
}

func (s *Service) list(ctx context.Context, user uuid.UUID, pendingOnly bool, now time.Time, limit int32) ([]Plan, error) {
	var rows []planRow
	if pendingOnly {
		pending, err := s.q.PlansPending(ctx, sqlc.PlansPendingParams{UserID: user, Now: now, RowLimit: limit})
		if err != nil {
			return nil, fmt.Errorf("pending plans: %w", err)
		}
		for _, r := range pending {
			rows = append(rows, planRow(r))
		}
	} else {
		all, err := s.q.PlansAll(ctx, sqlc.PlansAllParams{UserID: user, RowLimit: limit})
		if err != nil {
			return nil, fmt.Errorf("plans: %w", err)
		}
		for _, r := range all {
			rows = append(rows, planRow(r))
		}
	}
	return plansFrom(rows)
}

func (s *Service) find(ctx context.Context, id, user uuid.UUID) (*Plan, error) {
	row, err := s.q.PlanByID(ctx, sqlc.PlanByIDParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // no such plan
	}
	if err != nil {
		return nil, fmt.Errorf("plan: %w", err)
	}
	return planRow(row).plan()
}

// itemVersions is each item's `updated_at` in microseconds, by lowercase id.
func itemVersions(ctx context.Context, q *sqlc.Queries, ids []uuid.UUID, user uuid.UUID, lock bool) (map[string]int64, error) {
	out := map[string]int64{}
	if len(ids) == 0 {
		return out, nil
	}
	if lock {
		rows, err := q.PlanItemVersionsLocked(ctx, sqlc.PlanItemVersionsLockedParams{UserID: user, Ids: ids})
		if err != nil {
			return nil, fmt.Errorf("item versions: %w", err)
		}
		for _, r := range rows {
			out[strings.ToLower(r.ID.String())] = r.Micros
		}
		return out, nil
	}
	rows, err := q.PlanItemVersions(ctx, sqlc.PlanItemVersionsParams{UserID: user, Ids: ids})
	if err != nil {
		return nil, fmt.Errorf("item versions: %w", err)
	}
	for _, r := range rows {
		out[strings.ToLower(r.ID.String())] = r.Micros
	}
	return out, nil
}

// decisionKind is how an approval or denial ended (PlanDecision). Only applied wrote anything.
type decisionKind int

const (
	decidedApplied decisionKind = iota + 1
	decidedDenied
	decidedStale
	decidedExpired
	alreadyDecided
)

type decision struct {
	kind   decisionKind
	plan   Plan
	action library.ActionRecord
}

func lockPlan(ctx context.Context, q *sqlc.Queries, id, user uuid.UUID) (*Plan, error) {
	row, err := q.PlanLock(ctx, sqlc.PlanLockParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // no such plan
	}
	if err != nil {
		return nil, fmt.Errorf("lock plan: %w", err)
	}
	return planRow(row).plan()
}

func decide(ctx context.Context, q *sqlc.Queries, p Plan, status Status, now time.Time, actionID *uuid.UUID) (Plan, error) {
	err := q.PlanDecide(ctx, sqlc.PlanDecideParams{ID: p.ID, Status: string(status), DecidedAt: now, ActionID: actionID})
	if err != nil {
		return Plan{}, fmt.Errorf("decide plan: %w", err)
	}
	p.Status = status
	p.DecidedAt = &now
	p.ActionID = actionID
	return p, nil
}

// approveTx re-checks status, expiry and basis, then runs the op and journals it as the plan's
// token, all in one transaction. Nil when the user has no such plan.
func (s *Service) approveTx(ctx context.Context, id, user uuid.UUID, now time.Time) (*decision, error) {
	var out *decision
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		p, err := lockPlan(ctx, q, id, user)
		if err != nil || p == nil {
			return err
		}
		if p.Status != StatusPending {
			out = &decision{kind: alreadyDecided, plan: *p}
			return nil
		}
		if p.IsExpired(now) {
			decided, err := decide(ctx, q, *p, StatusExpired, now, nil)
			out = &decision{kind: decidedExpired, plan: decided}
			return err
		}
		holds, err := basisHolds(ctx, q, p.Basis, user)
		if err != nil {
			return err
		}
		if !holds {
			decided, err := decide(ctx, q, *p, StatusStale, now, nil)
			out = &decision{kind: decidedStale, plan: decided}
			return err
		}
		caller := library.Caller{Actor: library.ActorExternalAgent, AgentTokenID: p.AgentTokenID, AgentName: &p.AgentName}
		action, err := s.Library.Store.RunInTx(ctx, tx, p.Op, user, caller, "plan", caller.Summary(p.Summary))
		if err != nil {
			return err
		}
		actionID := action.ID
		decided, err := decide(ctx, q, *p, StatusApplied, now, &actionID)
		out = &decision{kind: decidedApplied, plan: decided, action: action}
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// denyTx denies a pending plan. Nil when the user has no such plan.
func (s *Service) denyTx(ctx context.Context, id, user uuid.UUID, now time.Time) (*decision, error) {
	var out *decision
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		p, err := lockPlan(ctx, q, id, user)
		if err != nil || p == nil {
			return err
		}
		if p.Status != StatusPending {
			out = &decision{kind: alreadyDecided, plan: *p}
			return nil
		}
		decided, err := decide(ctx, q, *p, StatusDenied, now, nil)
		out = &decision{kind: decidedDenied, plan: decided}
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// basisHolds: every item still exists unchanged, and no title the plan adds is in the library yet.
func basisHolds(ctx context.Context, q *sqlc.Queries, b Basis, user uuid.UUID) (bool, error) {
	ids := make([]uuid.UUID, 0, len(b.Items))
	for raw := range b.Items {
		if id, err := uuid.Parse(raw); err == nil {
			ids = append(ids, id)
		}
	}
	if len(ids) > 0 {
		current, err := itemVersions(ctx, q, ids, user, true)
		if err != nil {
			return false, err
		}
		if !maps.Equal(current, b.Items) {
			return false, nil
		}
	}
	if len(b.AbsentTitles) == 0 {
		return true, nil
	}
	present, err := q.PlanAnyTitlePresent(ctx, sqlc.PlanAnyTitlePresentParams{UserID: user, TitleIds: b.AbsentTitles})
	if err != nil {
		return false, fmt.Errorf("absent titles: %w", err)
	}
	return !present, nil
}
