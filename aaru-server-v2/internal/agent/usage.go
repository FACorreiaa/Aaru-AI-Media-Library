package agent

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/model"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Usage is one user's model spend on one UTC day (`agent_usage`).
type Usage struct {
	Requests     int
	InputTokens  int
	OutputTokens int
	// CostMicros is millionths of a dollar.
	CostMicros int
}

// RecordUsage adds one model call to the user's `agent_usage` row for the UTC day of at.
// Every model call is metered: group replies (GRP-011) and capture (AG-006) alike.
func RecordUsage(ctx context.Context, q *sqlc.Queries, user uuid.UUID, at time.Time, inputTokens, outputTokens, costMicros int) error {
	if err := q.RecordAgentUsage(ctx, sqlc.RecordAgentUsageParams{
		UserID: user, At: at, InputTokens: int64(inputTokens),
		OutputTokens: int64(outputTokens), CostMicros: int64(costMicros),
	}); err != nil {
		return fmt.Errorf("record agent usage: %w", err)
	}
	return nil
}

// RecordResponse meters one model response at the provider's pricing.
func RecordResponse(ctx context.Context, q *sqlc.Queries, user uuid.UUID, at time.Time, provider model.Provider, response model.Response) error {
	return RecordUsage(ctx, q, user, at, response.InputTokens, response.OutputTokens, provider.Pricing().Micros(response))
}

// UsageOn is the user's spend on the UTC day of at; zero when nothing was recorded.
func UsageOn(ctx context.Context, q *sqlc.Queries, user uuid.UUID, at time.Time) (Usage, error) {
	row, err := q.AgentUsageOn(ctx, sqlc.AgentUsageOnParams{UserID: user, At: at})
	if db.IsNoRows(err) {
		return Usage{}, nil
	}
	if err != nil {
		return Usage{}, fmt.Errorf("agent usage: %w", err)
	}
	return Usage{
		Requests: int(row.Requests), InputTokens: int(row.InputTokens),
		OutputTokens: int(row.OutputTokens), CostMicros: int(row.CostMicros),
	}, nil
}

// UsageStore meters model calls made outside this package (capture's extractor).
type UsageStore struct{ Q *sqlc.Queries }

// RecordUsage is RecordUsage over the store's queries.
func (s UsageStore) RecordUsage(ctx context.Context, user uuid.UUID, at time.Time, inputTokens, outputTokens, costMicros int) error {
	return RecordUsage(ctx, s.Q, user, at, inputTokens, outputTokens, costMicros)
}
