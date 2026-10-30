package billing

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/telemetry"
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
)

// FreeCapturesPerMonth is how many captures a free account may start in one UTC calendar month
// (ImportService.freeCapturesPerMonth).
const FreeCapturesPerMonth = 3

// Entitlement is one App Store subscription, as Aaru keeps it (BIL-001).
type Entitlement struct {
	OriginalTransactionID string
	UserID                uuid.UUID
	ProductID             string
	// Environment is Apple's `Production` or `Sandbox` (TestFlight buys in the sandbox).
	Environment string
	ExpiresAt   *time.Time
	RevokedAt   *time.Time
	// SignedAt is when Apple signed this state.
	SignedAt time.Time
}

// IsActive: not revoked and not expired at now.
func (e Entitlement) IsActive(now time.Time) bool {
	return e.RevokedAt == nil && (e.ExpiresAt == nil || e.ExpiresAt.After(now))
}

// Write is what recording an entitlement did.
type Write int

const (
	// Inserted is the first time this subscription was seen.
	Inserted Write = iota + 1
	// Updated replaced an older state.
	Updated
	// Stale: the stored state was signed later; nothing changed.
	Stale
)

// State is what `/v1/me/entitlement` reports.
type State struct {
	Plus         *Entitlement
	CapturesUsed int
	// CaptureLimit is nil on Plus: the monthly limit is lifted (a fair-use cap per day still applies).
	CaptureLimit     *int
	CapturesResetAt time.Time
}

// Service is BIL-001…003: Aaru Plus, bought in the App Store and kept by the server. The app
// sends each signed transaction after a purchase or a restore; Apple's notifications carry
// renewals, expiries and refunds. The web reads the same state and sells nothing.
type Service struct {
	Q *sqlc.Queries
	// Apple is nil when billing is not configured; purchases then answer 503.
	Apple AppleVerifier
	Now   func() time.Time
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// MonthStart is the UTC calendar month holding t, and the next one's start.
func MonthStart(t time.Time) (start, next time.Time) {
	u := t.UTC()
	start = time.Date(u.Year(), u.Month(), 1, 0, 0, 0, 0, time.UTC)
	return start, start.AddDate(0, 1, 0)
}

// Active is the subscription keeping the user on Plus at now, the one lasting longest; nil on the free tier.
func (s *Service) Active(ctx context.Context, userID uuid.UUID, now time.Time) (*Entitlement, error) {
	rows, err := s.Q.ActiveEntitlement(ctx, sqlc.ActiveEntitlementParams{UserID: userID, Now: &now})
	if err != nil {
		return nil, fmt.Errorf("active entitlement: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil //nolint:nilnil // nil is the free tier
	}
	r := rows[0]
	return &Entitlement{
		OriginalTransactionID: r.OriginalTransactionID, UserID: userID, ProductID: r.ProductID,
		Environment: r.Environment, ExpiresAt: r.ExpiresAt, SignedAt: r.SignedAt,
	}, nil
}

// Record writes an entitlement unless a state Apple signed later is already stored.
func (s *Service) Record(ctx context.Context, e Entitlement, now time.Time) (Write, error) {
	rows, err := s.Q.RecordEntitlement(ctx, sqlc.RecordEntitlementParams{
		OriginalTransactionID: e.OriginalTransactionID, UserID: e.UserID, ProductID: e.ProductID,
		Environment: e.Environment, ExpiresAt: e.ExpiresAt, RevokedAt: e.RevokedAt, SignedAt: e.SignedAt, UpdatedAt: now,
	})
	if err != nil {
		return 0, fmt.Errorf("record entitlement: %w", err)
	}
	switch {
	case len(rows) == 0:
		return Stale, nil
	case rows[0]:
		return Inserted, nil
	default:
		return Updated, nil
	}
}

// State is the user's Plus status and this month's captures.
func (s *Service) State(ctx context.Context, userID uuid.UUID) (State, error) {
	now := s.now()
	plus, err := s.Active(ctx, userID, now)
	if err != nil {
		return State{}, err
	}
	start, next := MonthStart(now)
	used, err := s.Q.BillingCapturesSince(ctx, sqlc.BillingCapturesSinceParams{UserID: userID, CreatedAt: start})
	if err != nil {
		return State{}, fmt.Errorf("captures: %w", err)
	}
	state := State{Plus: plus, CapturesUsed: int(used), CapturesResetAt: next}
	if plus == nil {
		limit := FreeCapturesPerMonth
		state.CaptureLimit = &limit
	}
	return state, nil
}

// RecordPurchase is a purchase or a restore, from the app that made it. The transaction must name this account.
func (s *Service) RecordPurchase(ctx context.Context, jws string, userID uuid.UUID) (State, error) {
	if s.Apple == nil {
		return State{}, apperr.Unavailable("billing_unavailable",
			"Aaru cannot confirm purchases right now. Try again later; nothing was lost.")
	}
	t, err := s.Apple.Transaction(jws)
	if err != nil {
		return State{}, apperr.New(http.StatusUnprocessableEntity, "invalid_transaction",
			"Aaru could not confirm that purchase with the App Store.")
	}
	if t.AppAccountToken == nil || *t.AppAccountToken != userID {
		return State{}, apperr.New(http.StatusConflict, "plus_other_account",
			"This App Store purchase belongs to another Aaru account. Sign in with that account to use it.")
	}
	if err := s.apply(ctx, t, userID); err != nil {
		return State{}, err
	}
	return s.State(ctx, userID)
}

// Notify handles one App Store Server Notification. A subscription Aaru cannot place (no
// account token, an account since deleted) is acknowledged and dropped, so Apple stops retrying it.
func (s *Service) Notify(ctx context.Context, jws string) error {
	if s.Apple == nil {
		return apperr.Unavailable("billing_unavailable", "Billing is off.")
	}
	n, err := s.Apple.Notification(jws)
	if err != nil {
		return apperr.New(http.StatusUnprocessableEntity, "invalid_notification", "The signature did not verify.")
	}
	if n.Transaction == nil {
		return nil
	}
	t := *n.Transaction
	owners, err := s.Q.EntitlementOwner(ctx, t.OriginalTransactionID)
	if err != nil {
		return fmt.Errorf("entitlement owner: %w", err)
	}
	var userID uuid.UUID
	switch {
	case len(owners) > 0:
		userID = owners[0]
	case t.AppAccountToken != nil:
		userID = *t.AppAccountToken
	default:
		return nil
	}
	exists, err := s.Q.BillingUserExists(ctx, userID)
	if err != nil {
		return fmt.Errorf("user exists: %w", err)
	}
	if !exists {
		return nil
	}
	return s.apply(ctx, t, userID)
}

func (s *Service) apply(ctx context.Context, t Transaction, userID uuid.UUID) error {
	e := Entitlement{
		OriginalTransactionID: t.OriginalTransactionID, UserID: userID, ProductID: t.ProductID,
		Environment: t.Environment, ExpiresAt: t.ExpiresAt, RevokedAt: t.RevokedAt, SignedAt: t.SignedAt,
	}
	now := s.now()
	write, err := s.Record(ctx, e, now)
	if err != nil {
		return err
	}
	if write == Inserted && e.IsActive(now) {
		telemetry.Capture(telemetry.PlusPurchased, userID, map[string]string{"product": t.ProductID})
	}
	return nil
}
