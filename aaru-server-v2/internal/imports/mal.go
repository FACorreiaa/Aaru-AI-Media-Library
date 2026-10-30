package imports

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"

	"github.com/google/uuid"
)

// ApplyFromMAL is SCR-010: entries read back from MyAnimeList, matched, merged and written at once
// as one journaled action, so Undo takes it back. There is no plan to approve: the user connected
// MAL to keep the two lists in step, and the merge only fills gaps and moves forward. It returns
// every row with its outcome: created and updated were written.
func (s *Service) ApplyFromMAL(ctx context.Context, rows []Row, user uuid.UUID) ([]PlannedRow, error) {
	if len(rows) == 0 {
		return []PlannedRow{}, nil
	}
	pending := make([]PlannedRow, len(rows))
	for i, r := range rows {
		pending[i] = PlannedRow{Index: i, Row: r, Outcome: OutcomePending}
	}
	planned, err := s.Plan(ctx, pending, user, false, nil)
	if err != nil {
		return nil, err
	}
	ops, err := s.writes(ctx, planned, user)
	if err != nil {
		return nil, err
	}
	if len(ops) == 0 {
		return planned, nil
	}
	if _, err := s.Library.Apply(ctx, library.Batch(ops...), user, library.UserCaller, "import",
		summary(core.SourceMALXML, Stats(planned))); err != nil {
		return nil, err
	}
	return planned, nil
}
