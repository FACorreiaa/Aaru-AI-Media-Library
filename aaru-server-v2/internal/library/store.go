package library

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/telemetry"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is the library, its journal and undo, over one Postgres transaction per write
// (PostgresLibraryStore).
type Store struct {
	pool *pgxpool.Pool
	q    *sqlc.Queries
	// Now stamps points written with a write; defaults to time.Now.
	Now func() time.Time
}

// NewStore builds the store over a pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool, q: sqlc.New(pool), Now: time.Now}
}

func (s *Store) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

// UndatedKinds are writes whose ticks were not watched today: an import, a season marked watched
// (a catch-up, owner 2026-10-25), and the whole show marked watched (PROG-005).
var UndatedKinds = map[string]bool{"import": true, "season": true, "show": true}

// ProgressKinds are kinds that are progress on an item: episode, season and whole-show ticks, and
// field edits (status, pages). A committed one accepts a Tonight pick (AG-005).
var ProgressKinds = map[string]bool{"episode": true, "season": true, "show": true, "update": true}

// isConstraintFailure is Fluent's `isConstraintFailure`: any integrity constraint violation.
func isConstraintFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && strings.HasPrefix(pgErr.Code, "23")
}

// Apply applies op for the user in one transaction and journals its inverse. Points and the
// streak day commit with it (GAM-001). A duplicate (user, title) is a StoreConflict; an op naming
// an item or list the user does not own is a 404. It does not run the gamification after-write
// hooks; Service.Commit does.
func (s *Store) Apply(ctx context.Context, op Op, user uuid.UUID, caller Caller, kind, summary string) (ActionRecord, error) {
	zone := reqctx.TimeZone(ctx)
	var action ActionRecord
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		inverse, err := run(ctx, q, op, user)
		if err != nil {
			return err
		}
		if UndatedKinds[kind] {
			if ids := op.ItemIDs(); len(ids) > 0 {
				if err := q.LibraryMarkUndatedTicks(ctx, ids); err != nil {
					return fmt.Errorf("mark undated ticks: %w", err)
				}
			}
		}
		action, err = journal(ctx, q, journalEntry{
			inverse: inverse, itemIDs: op.ItemIDs(), actor: caller.Actor, kind: kind, summary: summary,
			agentTokenID: caller.AgentTokenID,
		}, user)
		if err != nil {
			return err
		}
		facts := gamification.NewWriteFacts(kind)
		collectFacts(facts, op, inverse)
		return gamification.RecordLibraryWrite(ctx, tx, gamification.LibraryWrite{
			Facts: facts, Scrobbled: caller.Scrobbled, ActionID: action.ID, UserID: user, RequestedZone: zone, Now: s.now(),
		})
	})
	if err != nil {
		if isConstraintFailure(err) {
			return ActionRecord{}, &StoreConflict{Message: "This title is already in the library."}
		}
		return ActionRecord{}, err
	}
	// After the commit, so a rolled-back write is never counted.
	s.countWrite(ctx, op.ItemIDs(), kind, caller.Actor, user)
	return action, nil
}

// countWrite counts a committed write: the library action, and, when it is progress on a Tonight
// pick shown in the last six hours, that pick as taken (AG-005). Counting never fails the write it
// follows, so errors are dropped.
func (s *Store) countWrite(ctx context.Context, ids []uuid.UUID, kind string, actor Actor, user uuid.UUID) {
	telemetry.Capture(telemetry.LibraryAction, user, map[string]string{"kind": kind, "actor": string(actor)})
	if !ProgressKinds[kind] || len(ids) == 0 {
		return
	}
	days, err := s.q.LibraryAcceptTonightPicks(ctx, sqlc.LibraryAcceptTonightPicksParams{UserID: user, ItemIds: ids})
	if err != nil {
		return
	}
	for range days {
		telemetry.Capture(telemetry.TonightAccepted, user, nil)
	}
}

// Undo applies the action's inverse and journals that as a new `undo` action. An action already
// undone, or whose target changed, is an ActionConflict. It does not run the gamification
// after-undo hook; Service.Undo does.
func (s *Store) Undo(ctx context.Context, actionID, user uuid.UUID) (ActionRecord, error) {
	zone := reqctx.TimeZone(ctx)
	changed := &ActionConflict{Message: "The library changed since; that action can no longer be undone."}
	var undo ActionRecord
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := s.q.WithTx(tx)
		row, err := q.LibraryLockAction(ctx, sqlc.LibraryLockActionParams{ID: actionID, UserID: user})
		if db.IsNoRows(err) {
			return apperr.NotFound("No such action.")
		}
		if err != nil {
			return fmt.Errorf("lock action: %w", err)
		}
		if row.UndoneAt != nil {
			return &ActionConflict{Message: "That action was already undone."}
		}
		var inverse Op
		if err := json.Unmarshal(row.Inverse, &inverse); err != nil {
			return fmt.Errorf("action %s inverse: %w", actionID, err)
		}
		redo, err := run(ctx, q, inverse, user)
		if err != nil {
			if e := apperr.From(err); e != nil && e.Status == 404 {
				return changed
			}
			return err
		}
		if err := q.LibraryMarkUndone(ctx, actionID); err != nil {
			return fmt.Errorf("mark undone: %w", err)
		}
		undo, err = journal(ctx, q, journalEntry{
			inverse: redo, itemIDs: row.ItemIds, actor: ActorUser, kind: "undo",
			summary: "Undid: " + row.Summary, undoOf: &actionID,
		}, user)
		if err != nil {
			return err
		}
		// Undone ticks and finishes take their points back; a redo earns them again.
		facts := gamification.NewWriteFacts("undo")
		collectFacts(facts, inverse, redo)
		return gamification.RecordLibraryWrite(ctx, tx, gamification.LibraryWrite{
			Facts: facts, ActionID: undo.ID, UserID: user, RequestedZone: zone, Now: s.now(),
		})
	})
	if err != nil {
		if isConstraintFailure(err) {
			return ActionRecord{}, changed
		}
		return ActionRecord{}, err
	}
	telemetry.Capture(telemetry.LibraryAction, user, map[string]string{"kind": "undo", "actor": string(ActorUser)})
	return undo, nil
}

// collectFacts walks an op and its inverse for points (LibraryWriteFacts.derive). A batch's
// inverses come back reversed.
func collectFacts(f *gamification.WriteFacts, op, inverse Op) {
	switch {
	case op.Kind == OpBatch && inverse.Kind == OpBatch:
		n := len(inverse.Ops)
		for i, child := range op.Ops {
			if i >= n {
				break
			}
			collectFacts(f, child, inverse.Ops[n-1-i])
		}
	case op.Kind == OpSetEpisodes && inverse.Kind == OpSetEpisodes:
		f.Episodes(op.Item, inverse.Unwatch, inverse.Watch)
	case op.Kind == OpSetFields && inverse.Kind == OpSetFields:
		f.Fields(op.Item, progressFields(*op.Fields), progressFields(*inverse.Fields))
	case op.Kind == OpInsertItem:
		f.Inserted(op.Snapshot.ID, op.Snapshot.Fields.Status)
	}
}

func progressFields(f ItemFields) gamification.ProgressFields {
	return gamification.ProgressFields{
		Status: f.Status, BookPage: f.BookPage, BookPercent: f.BookPercent, MangaChapter: f.MangaChapter,
		MangaVolume: f.MangaVolume,
	}
}

// MARK: Running ops

// run applies one op inside the caller's transaction and returns its inverse.
func run(ctx context.Context, q *sqlc.Queries, op Op, user uuid.UUID) (Op, error) {
	switch op.Kind {
	case OpInsertList, OpDeleteList, OpRenameList, OpSetListMembers:
		return runListOp(ctx, q, op, user)
	case OpBatch:
		inverses := make([]Op, 0, len(op.Ops))
		for _, child := range op.Ops {
			inv, err := run(ctx, q, child, user)
			if err != nil {
				return Op{}, err
			}
			inverses = append(inverses, inv)
		}
		slices.Reverse(inverses)
		return Batch(inverses...), nil
	case OpInsertItem:
		if err := insertItem(ctx, q, *op.Snapshot, user); err != nil {
			return Op{}, err
		}
		return DeleteItem(op.Snapshot.ID), nil
	case OpDeleteItem:
		snapshot, err := deleteItem(ctx, q, op.Item, user)
		if err != nil {
			return Op{}, err
		}
		return InsertItem(snapshot), nil
	case OpSetFields:
		previous, err := lockedFields(ctx, q, op.Item, user)
		if err != nil {
			return Op{}, err
		}
		f := op.Fields
		err = q.LibrarySetFields(ctx, sqlc.LibrarySetFieldsParams{
			ID: op.Item, Status: string(f.Status), Rating: f.Rating, Notes: f.Notes, IsOwned: f.IsOwned,
			FinishedAt: f.FinishedAt, BookPage: i32(f.BookPage), BookPercent: f.BookPercent,
			MangaChapter: i32(f.MangaChapter), MangaVolume: i32(f.MangaVolume), StatusByHand: f.StatusByHand,
		})
		if err != nil {
			return Op{}, fmt.Errorf("set fields: %w", err)
		}
		return SetFields(op.Item, previous), nil
	case OpSetEpisodes:
		return setEpisodes(ctx, q, op.Item, op.Watch, op.Unwatch, user)
	}
	return Op{}, fmt.Errorf("library op: unknown kind %q", op.Kind)
}

func setEpisodes(ctx context.Context, q *sqlc.Queries, id uuid.UUID, watch, unwatch []core.EpisodeKey, user uuid.UUID) (Op, error) {
	if _, err := lockedFields(ctx, q, id, user); err != nil {
		return Op{}, err
	}
	current, err := watchedKeys(ctx, q, id)
	if err != nil {
		return Op{}, err
	}
	var added, removed []core.EpisodeKey
	for _, k := range watch {
		if !current[k] {
			added = append(added, k)
		}
	}
	for _, k := range unwatch {
		if current[k] {
			removed = append(removed, k)
		}
	}
	// One statement each way: a season on a long show is one round trip, not one per episode.
	if err := insertTicks(ctx, q, added, id, true); err != nil {
		return Op{}, err
	}
	if len(removed) > 0 {
		seasons, episodes := splitKeys(removed)
		if err := q.LibraryDeleteTicks(ctx, sqlc.LibraryDeleteTicksParams{
			LibraryItemID: id, Seasons: seasons, Episodes: episodes,
		}); err != nil {
			return Op{}, fmt.Errorf("delete ticks: %w", err)
		}
	}
	if err := q.LibraryTouchItem(ctx, id); err != nil {
		return Op{}, fmt.Errorf("touch item: %w", err)
	}
	return SetEpisodes(id, removed, added), nil
}

func insertItem(ctx context.Context, q *sqlc.Queries, s ItemSnapshot, user uuid.UUID) error {
	f := s.Fields
	byHand := f.StatusByHand != nil && *f.StatusByHand
	err := q.LibraryInsertItem(ctx, sqlc.LibraryInsertItemParams{
		ID: s.ID, UserID: user, TitleID: s.TitleID, Status: string(f.Status), IsOwned: f.IsOwned, Rating: f.Rating,
		Notes: f.Notes, AddedAt: s.AddedAt, FinishedAt: f.FinishedAt, BookPage: i32(f.BookPage),
		BookPercent: f.BookPercent, MangaChapter: i32(f.MangaChapter), MangaVolume: i32(f.MangaVolume),
		StatusByHand: byHand,
	})
	if err != nil {
		return fmt.Errorf("insert item: %w", err)
	}
	if err := insertTicks(ctx, q, s.Watched, s.ID, false); err != nil {
		return err
	}
	if err := q.LibraryClearTombstone(ctx, sqlc.LibraryClearTombstoneParams{UserID: user, LibraryItemID: s.ID}); err != nil {
		return fmt.Errorf("clear tombstone: %w", err)
	}
	return nil
}

func deleteItem(ctx context.Context, q *sqlc.Queries, id, user uuid.UUID) (ItemSnapshot, error) {
	fields, err := lockedFields(ctx, q, id, user)
	if err != nil {
		return ItemSnapshot{}, err
	}
	row, err := q.LibraryItemTitleAndAdded(ctx, id)
	if db.IsNoRows(err) {
		return ItemSnapshot{}, apperr.NotFound()
	}
	if err != nil {
		return ItemSnapshot{}, fmt.Errorf("item title: %w", err)
	}
	current, err := watchedKeys(ctx, q, id)
	if err != nil {
		return ItemSnapshot{}, err
	}
	watched := sortedKeys(current)
	if err := q.LibraryDeleteItem(ctx, id); err != nil {
		return ItemSnapshot{}, fmt.Errorf("delete item: %w", err)
	}
	if err := q.LibraryWriteTombstone(ctx, sqlc.LibraryWriteTombstoneParams{UserID: user, LibraryItemID: id}); err != nil {
		return ItemSnapshot{}, fmt.Errorf("tombstone: %w", err)
	}
	return ItemSnapshot{ID: id, TitleID: row.TitleID, Fields: fields, AddedAt: row.AddedAt.UTC(), Watched: watched}, nil
}

// insertTicks writes episode ticks in one statement. known is false for imports and restores,
// whose `watched_at` is write time, not when the user watched (GAM-006a).
func insertTicks(ctx context.Context, q *sqlc.Queries, keys []core.EpisodeKey, item uuid.UUID, known bool) error {
	if len(keys) == 0 {
		return nil
	}
	ids := make([]uuid.UUID, len(keys))
	for i := range ids {
		ids[i] = uuid.New()
	}
	seasons, episodes := splitKeys(keys)
	if err := q.LibraryInsertTicks(ctx, sqlc.LibraryInsertTicksParams{
		Ids: ids, LibraryItemID: item, Seasons: seasons, Episodes: episodes, Known: known,
	}); err != nil {
		return fmt.Errorf("insert ticks: %w", err)
	}
	return nil
}

// lockedFields locks the user's item row and returns its fields. Another user's item is 404.
func lockedFields(ctx context.Context, q *sqlc.Queries, id, user uuid.UUID) (ItemFields, error) {
	row, err := q.LibraryLockedFields(ctx, sqlc.LibraryLockedFieldsParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return ItemFields{}, apperr.NotFound()
	}
	if err != nil {
		return ItemFields{}, fmt.Errorf("lock item: %w", err)
	}
	status := core.LibraryStatus(row.Status)
	if !status.Valid() {
		return ItemFields{}, apperr.NotFound()
	}
	byHand := row.StatusByHand
	return ItemFields{
		Status: status, Rating: row.Rating, Notes: row.Notes, IsOwned: row.IsOwned, FinishedAt: utcPtr(row.FinishedAt),
		BookPage: iptr(row.BookPage), BookPercent: row.BookPercent, MangaChapter: iptr(row.MangaChapter),
		MangaVolume: iptr(row.MangaVolume), StatusByHand: &byHand,
	}, nil
}

func watchedKeys(ctx context.Context, q *sqlc.Queries, id uuid.UUID) (map[core.EpisodeKey]bool, error) {
	rows, err := q.LibraryWatchedKeys(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("watched keys: %w", err)
	}
	out := make(map[core.EpisodeKey]bool, len(rows))
	for _, r := range rows {
		if k, err := core.NewEpisodeKey(int(r.Season), int(r.Episode)); err == nil {
			out[k] = true
		}
	}
	return out, nil
}

type journalEntry struct {
	inverse      Op
	itemIDs      []uuid.UUID
	actor        Actor
	kind         string
	summary      string
	undoOf       *uuid.UUID
	agentTokenID *uuid.UUID
}

// journal writes one `actions` row: the inverse of a write, and who made it.
func journal(ctx context.Context, q *sqlc.Queries, e journalEntry, user uuid.UUID) (ActionRecord, error) {
	inverse, err := json.Marshal(e.inverse)
	if err != nil {
		return ActionRecord{}, fmt.Errorf("encode inverse: %w", err)
	}
	if e.itemIDs == nil {
		e.itemIDs = []uuid.UUID{}
	}
	id := uuid.New()
	created, err := q.LibraryJournal(ctx, sqlc.LibraryJournalParams{
		ID: id, UserID: user, Actor: string(e.actor), Kind: e.kind, Summary: e.summary, ItemIds: e.itemIDs,
		Inverse: inverse, UndoOf: e.undoOf, AgentTokenID: e.agentTokenID,
	})
	if err != nil {
		return ActionRecord{}, fmt.Errorf("journal: %w", err)
	}
	return ActionRecord{
		ID: id, Actor: e.actor, Kind: e.kind, Summary: e.summary, ItemIDs: e.itemIDs, CreatedAt: created.UTC(),
		UndoOf: e.undoOf,
	}, nil
}

// MARK: Reads

// Actions are the user's newest journal rows, at most limit (clamped to 1…100).
func (s *Store) Actions(ctx context.Context, user uuid.UUID, limit int) ([]ActionRecord, error) {
	rows, err := s.q.LibraryActions(ctx, sqlc.LibraryActionsParams{UserID: user, RowLimit: int32(max(1, min(limit, 100)))}) //nolint:gosec // clamped
	if err != nil {
		return nil, fmt.Errorf("actions: %w", err)
	}
	out := make([]ActionRecord, 0, len(rows))
	for _, r := range rows {
		actor := Actor(r.Actor)
		switch actor {
		case ActorUser, ActorAgent, ActorExternalAgent:
		default:
			actor = ActorUser
		}
		out = append(out, ActionRecord{
			ID: r.ID, Actor: actor, Kind: r.Kind, Summary: r.Summary, ItemIDs: r.ItemIds, CreatedAt: r.CreatedAt.UTC(),
			UndoneAt: utcPtr(r.UndoneAt), UndoOf: r.UndoOf, AgentName: r.AgentName,
		})
	}
	return out, nil
}

// Watched is an item's episode ticks.
func (s *Store) Watched(ctx context.Context, item uuid.UUID) (map[core.EpisodeKey]bool, error) {
	return watchedKeys(ctx, s.q, item)
}

// WatchedSorted is an item's episode ticks in order.
func (s *Store) WatchedSorted(ctx context.Context, item uuid.UUID) ([]core.EpisodeKey, error) {
	keys, err := s.Watched(ctx, item)
	if err != nil {
		return nil, err
	}
	return sortedKeys(keys), nil
}

// WatchedOf is the ticks of many items in one query, keyed by item.
func (s *Store) WatchedOf(ctx context.Context, items []uuid.UUID) (map[uuid.UUID]map[core.EpisodeKey]bool, error) {
	out := map[uuid.UUID]map[core.EpisodeKey]bool{}
	if len(items) == 0 {
		return out, nil
	}
	rows, err := s.q.LibraryWatchedKeysOf(ctx, items)
	if err != nil {
		return nil, fmt.Errorf("watched keys: %w", err)
	}
	for _, r := range rows {
		k, err := core.NewEpisodeKey(int(r.Season), int(r.Episode))
		if err != nil {
			continue
		}
		if out[r.LibraryItemID] == nil {
			out[r.LibraryItemID] = map[core.EpisodeKey]bool{}
		}
		out[r.LibraryItemID][k] = true
	}
	return out, nil
}

// ImportItemState is what an import decides against for one title the user has: the item's
// fields (StatusByHand nil, so a write built from them leaves the flag alone), whether its status
// was set by hand, and its ticks.
type ImportItemState struct {
	ItemID       uuid.UUID
	Fields       ItemFields
	StatusByHand bool
	Watched      map[core.EpisodeKey]bool
}

// ImportStates are the user's items among these titles, keyed by title. A plan asks once.
func (s *Store) ImportStates(ctx context.Context, user uuid.UUID, titleIDs []uuid.UUID) (map[uuid.UUID]ImportItemState, error) {
	out := map[uuid.UUID]ImportItemState{}
	if len(titleIDs) == 0 {
		return out, nil
	}
	rows, err := s.q.LibraryImportStates(ctx, sqlc.LibraryImportStatesParams{UserID: user, TitleIds: titleIDs})
	if err != nil {
		return nil, fmt.Errorf("import states: %w", err)
	}
	ids := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	watched, err := s.WatchedOf(ctx, ids)
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		status := core.LibraryStatus(r.Status)
		if !status.Valid() {
			continue
		}
		w := watched[r.ID]
		if w == nil {
			w = map[core.EpisodeKey]bool{}
		}
		out[r.TitleID] = ImportItemState{
			ItemID: r.ID,
			Fields: ItemFields{
				Status: status, Rating: r.Rating, Notes: r.Notes, IsOwned: r.IsOwned, FinishedAt: utcPtr(r.FinishedAt),
				BookPage: iptr(r.BookPage), BookPercent: r.BookPercent, MangaChapter: iptr(r.MangaChapter),
				MangaVolume: iptr(r.MangaVolume),
			},
			StatusByHand: r.StatusByHand,
			Watched:      w,
		}
	}
	return out, nil
}

// StatusSetByHand is whether the user set the item's status themselves (imports never move it).
func (s *Store) StatusSetByHand(ctx context.Context, item uuid.UUID) (bool, error) {
	rows, err := s.q.LibraryStatusByHand(ctx, item)
	if err != nil {
		return false, fmt.Errorf("status by hand: %w", err)
	}
	return len(rows) > 0 && rows[0], nil
}

// MARK: Helpers

func splitKeys(keys []core.EpisodeKey) (seasons, episodes []int32) {
	seasons = make([]int32, len(keys))
	episodes = make([]int32, len(keys))
	for i, k := range keys {
		seasons[i] = int32(k.Season)   //nolint:gosec // an episode key
		episodes[i] = int32(k.Episode) //nolint:gosec // an episode key
	}
	return seasons, episodes
}

func sortedKeys(set map[core.EpisodeKey]bool) []core.EpisodeKey {
	out := make([]core.EpisodeKey, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	slices.SortFunc(out, core.EpisodeKey.Compare)
	return out
}

func i32(p *int) *int32 {
	if p == nil {
		return nil
	}
	v := int32(*p) //nolint:gosec // validated progress numbers
	return &v
}

func iptr(p *int32) *int {
	if p == nil {
		return nil
	}
	v := int(*p)
	return &v
}

func utcPtr(t *time.Time) *time.Time {
	if t == nil {
		return nil
	}
	u := t.UTC()
	return &u
}
