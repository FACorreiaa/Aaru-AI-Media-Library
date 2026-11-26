package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"net/http"
	"slices"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
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
	// A guess waiting in the plan can be changed; anything else already matched cannot.
	changingGuess := job.State == core.JobPlanned && rows[position].Row.Guess != nil
	if rows[position].Outcome != OutcomeUnmatched && !changingGuess {
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
	row.Row.Guess, row.Row.LeftOut = nil, nil
	if err := numberNamedEpisodes(ctx, &row.Row, title, resolver); err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	row.Outcome = OutcomePending
	rows[position] = row

	if job.State == core.JobPlanned {
		decided, err := s.Decided(ctx, rows, user)
		if err != nil {
			return core.ImportJob{}, PlannedRow{}, err
		}
		job.Stats = Stats(decided)
		job.UpdatedAt = s.now()
		// One pick changes its row and the rows it now merges with: the rest are not rewritten.
		if err := s.Store.SavePlan(ctx, job, changedRows(rows, decided, position)); err != nil {
			return core.ImportJob{}, PlannedRow{}, err
		}
		return job, decided[position], nil
	}

	before := slices.Clone(row.Row.Lists)
	if err := s.writeRow(ctx, &row, job, user); err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	rows[position] = row
	changed := []PlannedRow{row}
	// A capture that made no list made one now, perhaps under a new name: every row names it.
	if len(before) > 0 && len(row.Row.Lists) > 0 && before[0] != row.Row.Lists[0] {
		for i, r := range rows {
			if i != position && slices.Contains(r.Row.Lists, before[0]) {
				lists := slices.Clone(r.Row.Lists)
				lists[slices.Index(lists, before[0])] = row.Row.Lists[0]
				rows[i].Row.Lists = lists
				changed = append(changed, rows[i])
			}
		}
	}
	job.Stats = Stats(rows)
	job.State = core.JobSucceeded
	if job.Stats.Unmatched > 0 {
		job.State = core.JobPartial
	}
	job.UpdatedAt = s.now()
	if err := s.Store.SavePlan(ctx, job, changed); err != nil {
		return core.ImportJob{}, PlannedRow{}, err
	}
	return job, row, nil
}

// rowLists are the list writes of a row matched by hand after approval. A capture's titles all join
// one list (ASK-012): the row joins the list the approval made, by its id, whatever the user's other
// lists are now called. A capture that made no list (nothing matched) makes it now, a roadmap under a
// name of its own, and made is that list for the job to keep. Other imports' shelves join by name.
func (s *Service) rowLists(ctx context.Context, row *PlannedRow, job core.ImportJob, titleID, user uuid.UUID) (
	ops []library.Op, made *uuid.UUID, err error,
) {
	if len(row.Row.Lists) == 0 {
		return nil, nil, nil
	}
	if job.Source == core.SourceCapture {
		listID, err := s.Store.List(ctx, job.ID, user)
		if err != nil {
			return nil, nil, err
		}
		if listID != nil {
			existing, err := s.Library.Lists(ctx, user)
			if err != nil {
				return nil, nil, err
			}
			for _, l := range existing {
				if l.ID != *listID {
					continue
				}
				if containsID(l.TitleIDs, titleID) {
					return nil, nil, nil
				}
				return []library.Op{library.SetListMembers(l.ID, append(slices.Clone(l.TitleIDs), titleID))}, nil, nil
			}
		}
		one := []PlannedRow{*row}
		if err := s.ownRoadmapLists(ctx, one, user); err != nil {
			return nil, nil, err
		}
		row.Row.Lists = one[0].Row.Lists
	}
	members := map[string][]uuid.UUID{}
	for _, list := range row.Row.Lists {
		members[list] = []uuid.UUID{titleID}
	}
	ops, ids, err := s.listOps(ctx, members, user)
	if err != nil {
		return nil, nil, err
	}
	if listID, ok := ids[row.Row.Lists[0]]; ok && job.Source == core.SourceCapture {
		made = &listID
	}
	return ops, made, nil
}

// changedRows is the picked row and every row deciding moved (PERF-006). Deciding sets only a
// row's outcome and reason.
func changedRows(before, after []PlannedRow, picked int) []PlannedRow {
	var changed []PlannedRow
	for i := range after {
		if i == picked || before[i].Outcome != after[i].Outcome || !equalReason(before[i].Reason, after[i].Reason) {
			changed = append(changed, after[i])
		}
	}
	return changed
}

func equalReason(a, b *string) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

// writeRow writes one row of an approved import, decided against the library as it is now, as one
// journaled action. Its lists are decided under the user's import-lists lock, as an approval's are.
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
	var batch library.Op
	var action *library.ActionRecord
	err = pgx.BeginFunc(ctx, s.Store.Pool, func(tx pgx.Tx) error {
		if err := s.Store.LockUserLists(ctx, tx, user); err != nil {
			return err
		}
		lists, made, err := s.rowLists(ctx, row, job, titleID, user)
		if err != nil {
			return err
		}
		all := append(slices.Clone(ops), lists...)
		if len(all) == 0 {
			return nil
		}
		batch = library.Batch(all...)
		applied, err := s.Library.ApplyTx(ctx, tx, batch, user, library.UserCaller, "import",
			"Matched “"+row.Row.Title+"” from "+SourceName(job.Source)+" by hand")
		if err != nil {
			return err
		}
		action = &applied
		if made != nil {
			return s.Store.SetListTx(ctx, tx, job.ID, *made)
		}
		return nil
	})
	if err != nil || action == nil {
		return err
	}
	s.Library.Committed(ctx, batch, "import", library.UserCaller.Actor, user)
	if s.Game != nil {
		s.Game.BatchApplied(ctx, user, &action.ID, false)
	}
	return nil
}
