package library

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// MARK: List ops (LST-001, LST-002), applied inside a library transaction like every write.

func runListOp(ctx context.Context, q *sqlc.Queries, op Op, user uuid.UUID) (Op, error) {
	switch op.Kind {
	case OpInsertList:
		s := op.ListSnapshot
		if err := q.ListInsert(ctx, sqlc.ListInsertParams{ID: s.ID, UserID: user, Name: s.Name, CreatedAt: s.CreatedAt}); err != nil {
			return Op{}, fmt.Errorf("insert list: %w", err)
		}
		if err := writeMembers(ctx, q, s.Members, s.ID); err != nil {
			return Op{}, err
		}
		return DeleteList(s.ID), nil
	case OpDeleteList:
		snapshot, err := lockedList(ctx, q, op.List, user)
		if err != nil {
			return Op{}, err
		}
		if err := q.ListDelete(ctx, op.List); err != nil {
			return Op{}, fmt.Errorf("delete list: %w", err)
		}
		return InsertList(snapshot), nil
	case OpRenameList:
		previous, err := lockedList(ctx, q, op.List, user)
		if err != nil {
			return Op{}, err
		}
		if err := q.ListRename(ctx, sqlc.ListRenameParams{ID: op.List, Name: op.Name}); err != nil {
			return Op{}, fmt.Errorf("rename list: %w", err)
		}
		return RenameList(op.List, previous.Name), nil
	case OpSetListMembers:
		previous, err := lockedList(ctx, q, op.List, user)
		if err != nil {
			return Op{}, err
		}
		if err := writeMembers(ctx, q, op.Members, op.List); err != nil {
			return Op{}, err
		}
		if err := q.ListTouch(ctx, op.List); err != nil {
			return Op{}, fmt.Errorf("touch list: %w", err)
		}
		return SetListMembers(op.List, previous.Members), nil
	}
	return Op{}, fmt.Errorf("runListOp got a non-list op %q", op.Kind)
}

// lockedList locks the user's list and returns it. Another user's list is 404.
func lockedList(ctx context.Context, q *sqlc.Queries, id, user uuid.UUID) (ListSnapshot, error) {
	row, err := q.ListLock(ctx, sqlc.ListLockParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return ListSnapshot{}, apperr.NotFound("No such list.")
	}
	if err != nil {
		return ListSnapshot{}, fmt.Errorf("lock list: %w", err)
	}
	members, err := q.ListMemberIDs(ctx, id)
	if err != nil {
		return ListSnapshot{}, fmt.Errorf("list members: %w", err)
	}
	return ListSnapshot{ID: id, Name: row.Name, CreatedAt: row.CreatedAt.UTC(), Members: members}, nil
}

func writeMembers(ctx context.Context, q *sqlc.Queries, members []uuid.UUID, list uuid.UUID) error {
	if err := q.ListClearMembers(ctx, list); err != nil {
		return fmt.Errorf("clear members: %w", err)
	}
	if len(members) == 0 {
		return nil
	}
	ids := make([]uuid.UUID, len(members))
	for i := range ids {
		ids[i] = uuid.New()
	}
	if err := q.ListWriteMembers(ctx, sqlc.ListWriteMembersParams{Ids: ids, ListID: list, TitleIds: members}); err != nil {
		return fmt.Errorf("write members: %w", err)
	}
	return nil
}

// MARK: List reads (PostgresListStore). List writes are Ops through Store.Apply.

// Lists are the user's lists, oldest first, with their members in order.
func (s *Store) Lists(ctx context.Context, user uuid.UUID) ([]core.AaruList, error) {
	return s.loadLists(ctx, user, nil)
}

// List is one of the user's lists, or nil.
func (s *Store) List(ctx context.Context, id, user uuid.UUID) (*core.AaruList, error) {
	lists, err := s.loadLists(ctx, user, &id)
	if err != nil || len(lists) == 0 {
		return nil, err
	}
	return &lists[0], nil
}

func (s *Store) loadLists(ctx context.Context, user uuid.UUID, id *uuid.UUID) ([]core.AaruList, error) {
	rows, err := s.q.ListsOfUser(ctx, sqlc.ListsOfUserParams{UserID: user, ID: id})
	if err != nil {
		return nil, fmt.Errorf("lists: %w", err)
	}
	if len(rows) == 0 {
		return []core.AaruList{}, nil
	}
	ids := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	members, err := s.q.ListMembersOf(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("list members: %w", err)
	}
	byList := map[uuid.UUID][]uuid.UUID{}
	for _, m := range members {
		byList[m.ListID] = append(byList[m.ListID], m.TitleID)
	}
	out := make([]core.AaruList, len(rows))
	for i, r := range rows {
		titles := byList[r.ID]
		if titles == nil {
			titles = []uuid.UUID{}
		}
		out[i] = core.AaruList{
			ID: r.ID, UserID: r.UserID, Name: r.Name, TitleIDs: titles, CreatedAt: r.CreatedAt.UTC(), UpdatedAt: r.UpdatedAt.UTC(),
		}
	}
	return out, nil
}

// MARK: Shelves (PostgresShelfStore): saved queries, never membership (X-008).

// Shelf is a saved query over the library (SHF-001).
type Shelf struct {
	ID        uuid.UUID
	Name      string
	Filter    Filter
	IsPinned  bool
	CreatedAt time.Time
}

func shelfFromRow(id uuid.UUID, name string, filter json.RawMessage, pinned bool, created time.Time) (Shelf, error) {
	var f Filter
	if err := json.Unmarshal(filter, &f); err != nil {
		return Shelf{}, fmt.Errorf("shelf %s filter: %w", id, err)
	}
	return Shelf{ID: id, Name: name, Filter: f, IsPinned: pinned, CreatedAt: created.UTC()}, nil
}

// Shelves are the user's shelves, pinned first, then oldest first.
func (s *Store) Shelves(ctx context.Context, user uuid.UUID) ([]Shelf, error) {
	rows, err := s.q.ShelvesOfUser(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("shelves: %w", err)
	}
	out := make([]Shelf, 0, len(rows))
	for _, r := range rows {
		shelf, err := shelfFromRow(r.ID, r.Name, r.Filter, r.IsPinned, r.CreatedAt)
		if err != nil {
			return nil, err
		}
		out = append(out, shelf)
	}
	return out, nil
}

// Shelf is one of the user's shelves, or nil.
func (s *Store) Shelf(ctx context.Context, id, user uuid.UUID) (*Shelf, error) {
	r, err := s.q.ShelfByID(ctx, sqlc.ShelfByIDParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none
	}
	if err != nil {
		return nil, fmt.Errorf("shelf: %w", err)
	}
	shelf, err := shelfFromRow(r.ID, r.Name, r.Filter, r.IsPinned, r.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &shelf, nil
}

// SaveShelf inserts or updates a shelf the user owns.
func (s *Store) SaveShelf(ctx context.Context, shelf Shelf, user uuid.UUID) error {
	filter, err := json.Marshal(shelf.Filter)
	if err != nil {
		return fmt.Errorf("encode filter: %w", err)
	}
	if err := s.q.ShelfSave(ctx, sqlc.ShelfSaveParams{
		ID: shelf.ID, UserID: user, Name: shelf.Name, Filter: filter, IsPinned: shelf.IsPinned, CreatedAt: shelf.CreatedAt,
	}); err != nil {
		return fmt.Errorf("save shelf: %w", err)
	}
	return nil
}

// DeleteShelf removes a shelf; false when the user has none by that id.
func (s *Store) DeleteShelf(ctx context.Context, id, user uuid.UUID) (bool, error) {
	ids, err := s.q.ShelfDelete(ctx, sqlc.ShelfDeleteParams{ID: id, UserID: user})
	if err != nil {
		return false, fmt.Errorf("delete shelf: %w", err)
	}
	return len(ids) > 0, nil
}
