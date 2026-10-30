package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/telemetry"
	"context"
	"errors"
	"fmt"
	"net/http"
	"sync"

	"github.com/google/uuid"
	"golang.org/x/sync/errgroup"
)

// Planning and approval (ImportService+Plan). Rows for the same title (two AniList seasons of one
// TMDB show, a film listed twice) merge into the first: it carries every tick, the furthest status,
// the first rating. The approval re-decides from the library as it is then, so a stale plan never
// overwrites.

const (
	// ChunkSize is rows per chunk: one AniList page, so a MyAnimeList export costs one request per chunk.
	ChunkSize = 50
	// chunksInFlight keeps AniList's pacer, not its latency, the limit.
	chunksInFlight = 3
	// rowsInFlight is rows matched at once inside a chunk: small enough to leave request handlers
	// their connections.
	rowsInFlight = 4
)

// Plan matches every row and decides what the approval would do with it. progress hears how many
// rows are matched as each chunk finishes (and renews the job's lease). With withoutAniListIfDown
// (a job's last try), an AniList outage leaves only the rows that need AniList unmatched, instead
// of failing the import.
func (s *Service) Plan(ctx context.Context, rows []PlannedRow, user uuid.UUID, withoutAniListIfDown bool, progress func(int) error) ([]PlannedRow, error) {
	var chunks [][]PlannedRow
	for start := 0; start < len(rows); start += ChunkSize {
		chunks = append(chunks, rows[start:min(start+ChunkSize, len(rows))])
	}
	matched := 0
	planned, err := boundedMap(ctx, chunks, chunksInFlight, func(ctx context.Context, chunk []PlannedRow) ([]PlannedRow, error) {
		return s.matchChunk(ctx, chunk, withoutAniListIfDown)
	}, func(chunk []PlannedRow) error {
		matched += len(chunk)
		if progress == nil {
			return nil
		}
		return progress(matched)
	})
	if err != nil {
		return nil, err
	}
	var flat []PlannedRow
	for _, c := range planned {
		flat = append(flat, c...)
	}
	return s.Decided(ctx, flat, user)
}

// Decided decides every matched title against the library as it is now. Rows for one title merge
// into the first; the rest are skipped.
func (s *Service) Decided(ctx context.Context, rows []PlannedRow, user uuid.UUID) ([]PlannedRow, error) {
	planned := append([]PlannedRow{}, rows...)
	mc, err := s.mergeContext(ctx, planned, user)
	if err != nil {
		return nil, err
	}
	for _, g := range groups(planned) {
		group := make([]PlannedRow, len(g.indices))
		for i, idx := range g.indices {
			group[i] = planned[idx]
		}
		merged := Merged(seasonRows(group, mc))
		for _, idx := range g.indices[1:] {
			planned[idx].Outcome = OutcomeSkip
			planned[idx].Reason = ptr("Merged into an earlier row.")
		}
		first := g.indices[0]
		if isTrue(merged.ListOnly) {
			planned[first].Outcome = OutcomeSkip
			planned[first].Reason = ptr("On a list only; added to the list, not your library.")
		} else {
			d := Decide(merged, stateFor(mc, g.titleID))
			planned[first].Outcome = d.Outcome
			planned[first].Reason = d.Reason
		}
	}
	return planned, nil
}

func stateFor(mc mergeContext, titleID uuid.UUID) *library.ImportItemState {
	if st, ok := mc.states[titleID]; ok {
		return &st
	}
	return nil
}

// matchChunk is one chunk: AniList's answers for its MyAnimeList-only rows in one request, then
// each row.
func (s *Service) matchChunk(ctx context.Context, chunk []PlannedRow, withoutAniListIfDown bool) ([]PlannedRow, error) {
	var refs []core.MediaRef
	for _, r := range chunk {
		if r.Row.Unsupported == nil {
			refs = append(refs, r.Row.MediaRef())
		}
	}
	resolver, err := s.Resolver().PrefetchingMAL(ctx, refs)
	if err != nil {
		if !withoutAniListIfDown || !provider.IsAniListOutage(err) {
			return nil, err
		}
		resolver = s.Resolver().WithoutAniList(err)
	}
	return boundedMap(ctx, chunk, rowsInFlight, func(ctx context.Context, row PlannedRow) (PlannedRow, error) {
		return match(ctx, row, resolver, withoutAniListIfDown)
	}, nil)
}

// boundedMap runs transform over items, at most limit at once, the results in the items' order.
// finished hears each result as it lands, one at a time.
func boundedMap[I, R any](ctx context.Context, items []I, limit int, transform func(context.Context, I) (R, error), finished func(R) error) ([]R, error) {
	results := make([]R, len(items))
	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(limit)
	var mu sync.Mutex
	for i, item := range items {
		g.Go(func() error {
			r, err := transform(gctx, item)
			if err != nil {
				return err
			}
			mu.Lock()
			defer mu.Unlock()
			results[i] = r
			if finished != nil {
				return finished(r)
			}
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return nil, err
	}
	return results, nil
}

// match resolves one row to a title, or says why it could not.
func match(ctx context.Context, planned PlannedRow, resolver catalog.Resolver, withoutAniListIfDown bool) (PlannedRow, error) {
	row := planned
	if row.Row.Unsupported != nil {
		row.Outcome = OutcomeUnmatched
		row.Reason = row.Row.Unsupported
		return row, nil
	}
	nameOnly := isTrue(row.Row.NameOnly) && row.Row.Year == nil && row.Row.IDs.IsEmpty()
	err := func() error {
		var title core.Title
		var err error
		if nameOnly {
			title, err = resolver.ResolveNamed(ctx, row.Row.Title, row.Row.Type, row.Row.Airing, row.Row.NotAfter)
		} else {
			title, err = resolveByIDs(ctx, row.Row, resolver)
		}
		if err != nil {
			return err
		}
		id := title.ID
		row.TitleID = &id
		return numberNamedEpisodes(ctx, &row.Row, title, resolver)
	}()
	if err == nil {
		return row, nil
	}
	if re, ok := catalog.IsResolutionError(err); ok {
		row.Outcome = OutcomeUnmatched
		if re == catalog.ErrAmbiguous {
			if nameOnly {
				kind := "shows"
				if row.Row.Type == core.MediaMovie {
					kind = "films"
				}
				row.Reason = ptr("Several " + kind + " are called “" + row.Row.Title + "”. Pick the right one by hand.")
			} else {
				row.Reason = ptr("More than one catalog entry matches. Pick the right one by hand.")
			}
		} else {
			year := ""
			if row.Row.Year != nil {
				year = fmt.Sprintf(" (%d)", *row.Row.Year)
			}
			row.Reason = ptr("No catalog entry matches “" + row.Row.Title + "”" + year + ".")
		}
		return row, nil
	}
	var verr *core.ValidationError
	if errors.As(err, &verr) {
		row.Outcome = OutcomeUnmatched
		row.Reason = ptr("Not enough to match: the row needs an id or a year.")
		return row, nil
	}
	if withoutAniListIfDown && provider.IsAniListOutage(err) {
		row.Outcome = OutcomeUnmatched
		row.Reason = ptr("AniList was not answering, so this could not be matched. " +
			"Import the file again later to add it.")
		return row, nil
	}
	return row, err
}

// numberNamedEpisodes turns Netflix's named episodes into ticks once the show is known.
func numberNamedEpisodes(ctx context.Context, row *Row, title core.Title, resolver catalog.Resolver) error {
	if row.NamedEpisodes == nil {
		return nil
	}
	keys, err := resolver.EpisodesNamed(ctx, title, row.NamedEpisodes)
	if err != nil {
		return err
	}
	if len(keys) > 0 {
		row.Watched = append(append([]core.EpisodeKey{}, row.Watched...), keys...)
	}
	row.NamedEpisodes = nil
	return nil
}

// resolveByIDs is ids first. A row that also allows its name (TV Time's old TVDB ids, which TMDB
// may not know) falls back to the exact-name match when the ids find nothing. A book whose ISBN
// Open Library does not know falls back to its title, year and author, as a row without an ISBN
// would (IMP-020).
func resolveByIDs(ctx context.Context, row Row, resolver catalog.Resolver) (core.Title, error) {
	title, err := resolver.Resolve(ctx, row.MediaRef(), row.Author)
	if re, ok := catalog.IsResolutionError(err); ok && re == catalog.ErrUnresolvable {
		if isTrue(row.NameOnly) && !row.IDs.IsEmpty() && row.Year == nil {
			return resolver.ResolveNamed(ctx, row.Title, row.Type, nil, row.NotAfter)
		}
		if row.Type == core.MediaBook && !row.IDs.IsEmpty() && row.Year != nil {
			name := row.Title
			return resolver.Resolve(ctx, core.MediaRef{Type: core.MediaBook, Title: &name, Year: row.Year}, row.Author)
		}
	}
	return title, err
}

// MARK: Approval

// Apply writes the plan as one journaled action, so a whole import undoes in one tap.
func (s *Service) Apply(ctx context.Context, id, user uuid.UUID) (core.ImportJob, error) {
	stored, err := s.Store.Job(ctx, id, user)
	if err != nil {
		return core.ImportJob{}, err
	}
	if stored == nil {
		return core.ImportJob{}, apperr.NotFound()
	}
	job := *stored
	if job.State != core.JobPlanned {
		message := "This import has no plan yet."
		if job.State.IsTerminal() {
			message = "This import was already applied."
		}
		return core.ImportJob{}, apperr.New(http.StatusConflict, "import_not_planned", message)
	}
	if job.Source.IsListens() {
		return s.applyListens(ctx, job)
	}
	rows, err := s.Store.Rows(ctx, id)
	if err != nil {
		return core.ImportJob{}, err
	}
	ops, err := s.writes(ctx, rows, user)
	if err != nil {
		return core.ImportJob{}, err
	}
	job.Stats = Stats(rows)
	var actionID *uuid.UUID
	if len(ops) > 0 {
		action, err := s.Library.Apply(ctx, library.Batch(ops...), user, library.UserCaller, "import", summary(job.Source, job.Stats))
		if err != nil {
			return core.ImportJob{}, err
		}
		actionID = &action.ID
	}
	job.State = core.JobSucceeded
	if job.Stats.Unmatched > 0 {
		job.State = core.JobPartial
	}
	job.UpdatedAt = s.now()
	job.ActionID = actionID
	if err := s.Store.SavePlan(ctx, job, rows); err != nil {
		return core.ImportJob{}, err
	}
	if job.Source == core.SourceCapture {
		telemetry.Capture(telemetry.CapturePlanDecided, user, map[string]string{"decision": "approved"})
	}
	if s.Game != nil {
		s.Game.BatchApplied(ctx, user, actionID, true)
	}
	return job, nil
}

// writes are every write a matched plan makes, decided again against the library as it is now (the
// plan may be stale). Each row's outcome is updated (in place) to what it does.
func (s *Service) writes(ctx context.Context, rows []PlannedRow, user uuid.UUID) ([]library.Op, error) {
	var ops []library.Op
	listMembers := map[string][]uuid.UUID{}
	for _, r := range rows {
		if r.Outcome == OutcomeUnmatched || r.TitleID == nil {
			continue
		}
		for _, list := range r.Row.Lists {
			listMembers[list] = append(listMembers[list], *r.TitleID)
		}
	}
	mc, err := s.mergeContext(ctx, rows, user)
	if err != nil {
		return nil, err
	}
	for _, g := range groups(rows) {
		group := make([]PlannedRow, len(g.indices))
		for i, idx := range g.indices {
			group[i] = rows[idx]
		}
		merged := Merged(seasonRows(group, mc))
		// A list-only title joins its list without joining the library.
		if isTrue(merged.ListOnly) {
			continue
		}
		ops = append(ops, s.rowWrites(&rows[g.indices[0]], merged, g.titleID, stateFor(mc, g.titleID))...)
	}
	lists, err := s.listOps(ctx, listMembers, user)
	if err != nil {
		return nil, err
	}
	return append(ops, lists...), nil
}

// rowWrites decides one title again (the library may have changed since the plan) and returns its
// writes.
func (s *Service) rowWrites(row *PlannedRow, merged Row, titleID uuid.UUID, item *library.ImportItemState) []library.Op {
	d := Decide(merged, item)
	row.Outcome = d.Outcome
	row.Reason = d.Reason
	switch {
	case d.Outcome == OutcomeCreate && d.Fields != nil:
		watched := d.Watch
		if watched == nil {
			watched = []core.EpisodeKey{}
		}
		return []library.Op{library.InsertItem(library.ItemSnapshot{
			ID: uuid.New(), TitleID: titleID, Fields: *d.Fields, AddedAt: s.now(), Watched: watched,
		})}
	case d.Outcome == OutcomeUpdate && d.Fields != nil && d.ItemID != nil:
		var ops []library.Op
		if d.FieldsChanged {
			ops = append(ops, library.SetFields(*d.ItemID, *d.Fields))
		}
		if len(d.Watch) > 0 {
			ops = append(ops, library.SetEpisodes(*d.ItemID, d.Watch, nil))
		}
		return ops
	}
	return nil
}
