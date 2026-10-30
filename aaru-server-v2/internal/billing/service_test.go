package billing

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/telemetry"
	"aaru-go-api/internal/testdb"
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// FakeApple hands out signed data by name.
type FakeApple struct {
	Transactions  map[string]Transaction
	Notifications map[string]Notification
}

func (f FakeApple) Transaction(jws string) (Transaction, error) {
	t, ok := f.Transactions[jws]
	if !ok {
		return Transaction{}, ErrInvalid
	}
	return t, nil
}

func (f FakeApple) Notification(jws string) (Notification, error) {
	n, ok := f.Notifications[jws]
	if !ok {
		return Notification{}, ErrInvalid
	}
	return n, nil
}

type recordingSink struct {
	mu     sync.Mutex
	events []telemetry.Event
}

func (r *recordingSink) Capture(e telemetry.Event, _ uuid.UUID, _ map[string]string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, e)
}

func tx(original string, token *uuid.UUID, signed time.Time, revoked *time.Time) Transaction {
	expires := time.Now().Add(24 * time.Hour)
	return Transaction{
		OriginalTransactionID: original, TransactionID: original + "1", BundleID: testBundle, ProductID: "aaru_plus_yearly",
		Environment: "Sandbox", AppAccountToken: token, ExpiresAt: &expires, RevokedAt: revoked, SignedAt: signed,
	}
}

func code(err error) string {
	var e *apperr.Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func TestPurchaseLiftsTheCaptureLimit(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	user := uuid.New()
	_, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)
	sink := &recordingSink{}
	telemetry.Install(sink)
	defer telemetry.Install(nil)

	other := uuid.New()
	billing := &Service{Q: sqlc.New(pool), Apple: FakeApple{Transactions: map[string]Transaction{
		"mine":   tx("orig-1", &user, time.Now(), nil),
		"theirs": tx("other-1", &other, time.Now(), nil),
	}}}
	free, err := billing.State(ctx, user)
	require.NoError(t, err)
	assert.Nil(t, free.Plus)
	require.NotNil(t, free.CaptureLimit)
	assert.Equal(t, FreeCapturesPerMonth, *free.CaptureLimit)

	bought, err := billing.RecordPurchase(ctx, "mine", user)
	require.NoError(t, err)
	require.NotNil(t, bought.Plus)
	assert.Equal(t, "orig-1", bought.Plus.OriginalTransactionID)
	assert.Nil(t, bought.CaptureLimit)
	// A restore sends it again: nothing changes, and the purchase is counted once.
	again, err := billing.RecordPurchase(ctx, "mine", user)
	require.NoError(t, err)
	assert.NotNil(t, again.Plus)
	assert.Equal(t, []telemetry.Event{telemetry.PlusPurchased}, sink.events)

	_, err = billing.RecordPurchase(ctx, "theirs", user)
	assert.Equal(t, "plus_other_account", code(err))
	_, err = billing.RecordPurchase(ctx, "garbage", user)
	assert.Equal(t, "invalid_transaction", code(err))

	_, err = (&Service{Q: sqlc.New(pool)}).RecordPurchase(ctx, "mine", user)
	assert.Equal(t, "billing_unavailable", code(err))
}

func TestNotificationsRenewRefundAndExpire(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	user := uuid.New()
	_, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)
	now := time.Now()
	stranger := uuid.New()
	apple := FakeApple{
		Transactions: map[string]Transaction{"bought": tx("orig-2", &user, now, nil)},
		Notifications: map[string]Notification{
			"refund":   {Type: "REFUND", Transaction: ptr(tx("orig-2", &user, now.Add(time.Minute), &now))},
			"late":     {Type: "DID_RENEW", Transaction: ptr(tx("orig-2", &user, now.Add(-time.Minute), nil))},
			"stranger": {Type: "SUBSCRIBED", Transaction: ptr(tx("x-1", &stranger, now, nil))},
			"test":     {Type: "TEST"},
		},
	}
	billing := &Service{Q: sqlc.New(pool), Apple: apple}
	_, err = billing.RecordPurchase(ctx, "bought", user)
	require.NoError(t, err)
	require.NoError(t, billing.Notify(ctx, "refund"))
	state, err := billing.State(ctx, user)
	require.NoError(t, err)
	assert.Nil(t, state.Plus)
	require.NoError(t, billing.Notify(ctx, "late"), "a late one never undoes a newer state")
	state, err = billing.State(ctx, user)
	require.NoError(t, err)
	assert.Nil(t, state.Plus)
	require.NoError(t, billing.Notify(ctx, "stranger"), "an account Aaru does not have is acknowledged")
	owners, err := sqlc.New(pool).EntitlementOwner(ctx, "x-1")
	require.NoError(t, err)
	assert.Empty(t, owners)
	require.NoError(t, billing.Notify(ctx, "test"))
	assert.Equal(t, "invalid_notification", code(billing.Notify(ctx, "forged")))
	assert.Equal(t, "billing_unavailable", code((&Service{Q: sqlc.New(pool)}).Notify(ctx, "x")))
}

func TestCapturesCountThisUTCMonth(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	user := uuid.New()
	_, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)
	now := time.Date(2026, 10, 15, 12, 0, 0, 0, time.UTC)
	for _, at := range []time.Time{now, now.Add(-24 * time.Hour), time.Date(2026, 9, 30, 23, 0, 0, 0, time.UTC)} {
		_, err := pool.Exec(ctx, `INSERT INTO import_jobs (id, user_id, source, state, stats, created_at, updated_at)
			VALUES ($1, $2, 'capture', 'planned', '{}', $3, $3)`, uuid.New(), user, at)
		require.NoError(t, err)
	}
	state, err := (&Service{Q: sqlc.New(pool), Now: func() time.Time { return now }}).State(ctx, user)
	require.NoError(t, err)
	assert.Equal(t, 2, state.CapturesUsed)
	assert.Equal(t, time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC), state.CapturesResetAt)
}

func ptr[T any](v T) *T { return &v }
