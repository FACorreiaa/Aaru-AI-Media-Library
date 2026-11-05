package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"context"
	"net/http"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// LeaveOutRow is BOOK-001: untick one row of a plan before approving it, or tick it again. The row
// stays in the plan and the counts follow. In one transaction under the job's lock, so a tick
// cannot land on a plan being approved, and quick ticks each see the last.
func (s *Service) LeaveOutRow(ctx context.Context, id uuid.UUID, index int, leftOut bool, user uuid.UUID) (core.ImportJob, PlannedRow, error) {
	var job core.ImportJob
	var row PlannedRow
	err := pgx.BeginFunc(ctx, s.Store.Pool, func(tx pgx.Tx) error {
		if err := s.lockPlanned(ctx, tx, id, user); err != nil {
			return err
		}
		store := &Store{Q: s.Store.Q.WithTx(tx)}
		stored, err := store.Job(ctx, id, user)
		if err != nil {
			return err
		}
		if stored == nil {
			return apperr.NotFound()
		}
		job = *stored
		rows, err := store.Rows(ctx, id)
		if err != nil {
			return err
		}
		position := -1
		for i, r := range rows {
			if r.Index == index {
				position = i
				break
			}
		}
		if position < 0 {
			return apperr.NotFound()
		}
		if o := rows[position].Outcome; o != OutcomeCreate && o != OutcomeUpdate {
			return apperr.New(http.StatusConflict, "import_row_not_written", "The plan does not write this row.")
		}
		rows[position].Row.LeftOut = nil
		if leftOut {
			rows[position].Row.LeftOut = ptr(true)
		}
		row = rows[position]
		job.Stats = Stats(rows)
		job.UpdatedAt = s.now()
		return s.Store.SavePlanTx(ctx, tx, job, []PlannedRow{row})
	})
	if err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	return job, row, nil
}
