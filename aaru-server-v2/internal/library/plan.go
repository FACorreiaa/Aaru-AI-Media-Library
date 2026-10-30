package library

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// RunInTx applies op and journals its inverse inside the caller's transaction, as one action
// (PostgresLibraryStore.run + journal). Unlike Apply it records no points and marks no ticks
// undated: an approved plan (AG-003) is a batch, and its badges arrive through
// gamification.BatchApplied once the transaction commits. An op naming an item the user does not
// own is a 404.
func (s *Store) RunInTx(ctx context.Context, tx pgx.Tx, op Op, user uuid.UUID, caller Caller, kind, summary string) (ActionRecord, error) {
	q := s.q.WithTx(tx)
	inverse, err := run(ctx, q, op, user)
	if err != nil {
		return ActionRecord{}, err
	}
	return journal(ctx, q, journalEntry{
		inverse: inverse, itemIDs: op.ItemIDs(), actor: caller.Actor, kind: kind, summary: summary,
		agentTokenID: caller.AgentTokenID,
	}, user)
}
