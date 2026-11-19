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
	// WebSearches is how many web searches the assistant ran (ASK-004).
	WebSearches int
}

// RecordUsage adds one model call to the user's `agent_usage` row for the UTC day of at.
// Every model call is metered: group replies (GRP-011) and capture (AG-006) alike.
func RecordUsage(ctx context.Context, q *sqlc.Queries, user uuid.UUID, at time.Time, inputTokens, outputTokens, costMicros int) error {
	return recordUsage(ctx, q, user, at, Usage{InputTokens: inputTokens, OutputTokens: outputTokens, CostMicros: costMicros})
}

// recordUsage adds one model call's tokens, cost and web searches; Requests is ignored (always one).
func recordUsage(ctx context.Context, q *sqlc.Queries, user uuid.UUID, at time.Time, u Usage) error {
	if err := q.RecordAgentUsage(ctx, sqlc.RecordAgentUsageParams{
		UserID: user, At: at, InputTokens: int64(u.InputTokens),
		OutputTokens: int64(u.OutputTokens), CostMicros: int64(u.CostMicros), WebSearches: int32(u.WebSearches), //nolint:gosec // a call runs a handful of searches
	}); err != nil {
		return fmt.Errorf("record agent usage: %w", err)
	}
	return nil
}

// RecordResponse meters one model response at the provider's pricing.
func RecordResponse(ctx context.Context, q *sqlc.Queries, user uuid.UUID, at time.Time, provider model.Provider, response model.Response) error {
	return recordUsage(ctx, q, user, at, Usage{
		InputTokens: response.InputTokens, OutputTokens: response.OutputTokens,
		CostMicros: provider.Pricing().Micros(response), WebSearches: response.WebSearches,
	})
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
		OutputTokens: int(row.OutputTokens), CostMicros: int(row.CostMicros), WebSearches: int(row.WebSearches),
	}, nil
}

// UsageStore meters model calls made outside this package (capture's extractor).
type UsageStore struct{ Q *sqlc.Queries }

// RecordUsage is RecordUsage over the store's queries.
func (s UsageStore) RecordUsage(ctx context.Context, user uuid.UUID, at time.Time, inputTokens, outputTokens, costMicros int) error {
	return RecordUsage(ctx, s.Q, user, at, inputTokens, outputTokens, costMicros)
}
