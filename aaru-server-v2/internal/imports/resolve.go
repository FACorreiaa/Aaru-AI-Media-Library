package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"net/http"

	"github.com/google/uuid"
)

// Unmatched-row triage (IMP-011, ImportService+Resolve): the person searches the catalog and picks
// the title a row meant. Before approval the pick joins the plan; after it, the row is written at
// once, like a tap, as its own undoable action. Either way the source's status, rating and ticks
// come with it, merged like any import row: fill empty, move forward, never past a status set by
// hand.

// ResolveRow matches row index of the job to the title ref names.
func (s *Service) ResolveRow(ctx context.Context, id uuid.UUID, index int, ref core.MediaRef, user uuid.UUID) (core.ImportJob, PlannedRow, error) {
	stored, err := s.Store.Job(ctx, id, user)
	if err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	if stored == nil {
		return core.ImportJob{}, PlannedRow{}, apperr.NotFound()
	}
	job := *stored
	if job.State != core.JobPlanned && job.State != core.JobPartial && job.State != core.JobSucceeded {
		return core.ImportJob{}, PlannedRow{}, apperr.New(http.StatusConflict, "import_not_planned",
			"This import has no plan yet. Try again when its rows are matched.")
	}
	rows, err := s.Store.Rows(ctx, id)
	if err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	position := -1
	for i, r := range rows {
		if r.Index == index {
			position = i
			break
		}
	}
	if position < 0 {
		return core.ImportJob{}, PlannedRow{}, apperr.NotFound()
	}
	if rows[position].Outcome != OutcomeUnmatched {
		return core.ImportJob{}, PlannedRow{}, apperr.New(http.StatusConflict, "import_row_matched", "This row is already matched.")
	}
	resolver := s.Resolver()
	title, err := resolver.Resolve(ctx, ref, nil)
	if err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	row := rows[position]
	titleID := title.ID
	row.TitleID = &titleID
	row.Row.Type = title.Type
	row.Row.Unsupported = nil
	if err := numberNamedEpisodes(ctx, &row.Row, title, resolver); err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	row.Outcome = OutcomePending
	rows[position] = row

	if job.State == core.JobPlanned {
		if rows, err = s.Decided(ctx, rows, user); err != nil {
			return core.ImportJob{}, PlannedRow{}, err
		}
		job.Stats = Stats(rows)
		job.UpdatedAt = s.now()
		if err := s.Store.SavePlan(ctx, job, rows); err != nil {
			return core.ImportJob{}, PlannedRow{}, err
		}
		return job, rows[position], nil
	}

	if err := s.writeRow(ctx, &row, job, user); err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	rows[position] = row
	job.Stats = Stats(rows)
	job.State = core.JobSucceeded
	if job.Stats.Unmatched > 0 {
		job.State = core.JobPartial
	}
	job.UpdatedAt = s.now()
	if err := s.Store.SavePlan(ctx, job, []PlannedRow{row}); err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	return job, row, nil
}

// writeRow writes one row of an approved import, decided against the library as it is now, as one
// journaled action.
func (s *Service) writeRow(ctx context.Context, row *PlannedRow, job core.ImportJob, user uuid.UUID) error {
	if row.TitleID == nil {
		return nil
	}
	titleID := *row.TitleID
	mc, err := s.mergeContext(ctx, []PlannedRow{*row}, user)
	if err != nil {
		return err
	}
	merged := Merged(seasonRows([]PlannedRow{*row}, mc))
	var ops []library.Op
	if isTrue(merged.ListOnly) {
		row.Outcome = OutcomeSkip
		row.Reason = ptr("On a list only; added to the list, not your library.")
	} else {
		ops = append(ops, s.rowWrites(row, merged, titleID, stateFor(mc, titleID))...)
	}
	members := map[string][]uuid.UUID{}
	for _, list := range row.Row.Lists {
		members[list] = []uuid.UUID{titleID}
	}
	lists, err := s.listOps(ctx, members, user)
	if err != nil {
		return err
	}
	ops = append(ops, lists...)
	if len(ops) == 0 {
		return nil
	}
	action, err := s.Library.Apply(ctx, library.Batch(ops...), user, library.UserCaller, "import",
		"Matched “"+row.Row.Title+"” from "+SourceName(job.Source)+" by hand")
	if err != nil {
		return err
	}
	if s.Game != nil {
		s.Game.BatchApplied(ctx, user, &action.ID, false)
	}
	return nil
}
