package library

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/telemetry"
	"context"
	"net/http"
	"slices"
	"strings"

	"github.com/google/uuid"
)

// ListDetail is a list with its member titles, in order.
type ListDetail struct {
	List    core.AaruList
	Titles  []core.Title
	Members []ListMember
}

// ListMember is one list row (LST-003): the title, the caller's library entry when there is one,
// and for shows, their status and next episode to air.
type ListMember struct {
	Title  core.Title
	Entry  *Entry
	Airing *catalog.TitleAiring
}

// Lists is list membership (LST-001, LST-002), journaled like every library write (ListService).
// A list can hold a title the user has no library item for.
type Lists struct {
	Library *Service
}

func (l *Lists) store() *Store { return l.Library.Store }

// All are the user's lists.
func (l *Lists) All(ctx context.Context, user uuid.UUID) ([]core.AaruList, error) {
	return l.store().Lists(ctx, user)
}

// Detail is one list with its members' titles, entries and airing.
func (l *Lists) Detail(ctx context.Context, id, user uuid.UUID) (ListDetail, error) {
	list, err := l.store().List(ctx, id, user)
	if err != nil {
		return ListDetail{}, err
	}
	if list == nil {
		return ListDetail{}, apperr.NotFound("No such list.")
	}
	now := l.Library.now()
	kit := l.Library.Catalog
	titles, err := kit.Store.Titles(ctx, list.TitleIDs)
	if err != nil {
		return ListDetail{}, err
	}
	listID := list.ID
	entries, _, err := l.store().Entries(ctx, user, Filter{}.WithList(&listID), nil, max(len(list.TitleIDs), 1), now)
	if err != nil {
		return ListDetail{}, err
	}
	airing, err := kit.Store.Airing(ctx, list.TitleIDs, now)
	if err != nil {
		return ListDetail{}, err
	}
	byTitle := map[uuid.UUID]Entry{}
	for _, e := range entries {
		if _, ok := byTitle[e.Title.ID]; !ok {
			byTitle[e.Title.ID] = e
		}
	}
	members := make([]ListMember, 0, len(titles))
	for _, t := range titles {
		m := ListMember{Title: t}
		if e, ok := byTitle[t.ID]; ok {
			m.Entry = &e
		}
		if a, ok := airing[t.ID]; ok {
			m.Airing = &a
		}
		members = append(members, m)
	}
	return ListDetail{List: *list, Titles: titles, Members: members}, nil
}

func (l *Lists) apply(ctx context.Context, op Op, user uuid.UUID, summary string) (ActionRecord, error) {
	return l.store().Apply(ctx, op, user, UserCaller, "list", summary)
}

// Create makes an empty list.
func (l *Lists) Create(ctx context.Context, name string, user uuid.UUID) (ListDetail, error) {
	snapshot := ListSnapshot{ID: uuid.New(), Name: strings.TrimSpace(name), CreatedAt: l.Library.now(), Members: []uuid.UUID{}}
	if err := core.ValidateListName(snapshot.Name); err != nil {
		return ListDetail{}, err
	}
	action, err := l.apply(ctx, InsertList(snapshot), user, "Created list "+snapshot.Name)
	if err != nil {
		return ListDetail{}, err
	}
	telemetry.Capture(telemetry.ListCreated, user, nil)
	if l.Library.Gamification != nil {
		id := action.ID
		l.Library.Gamification.AfterWrite(ctx, user, &id)
	}
	return l.Detail(ctx, snapshot.ID, user)
}

// Rename renames a list; the same name changes nothing.
func (l *Lists) Rename(ctx context.Context, id uuid.UUID, name string, user uuid.UUID) (ListDetail, error) {
	current, err := l.Detail(ctx, id, user)
	if err != nil {
		return ListDetail{}, err
	}
	name = strings.TrimSpace(name)
	if err := core.ValidateListName(name); err != nil {
		return ListDetail{}, err
	}
	if name == current.List.Name {
		return current, nil
	}
	if _, err := l.apply(ctx, RenameList(id, name), user, "Renamed "+current.List.Name+" to "+name); err != nil {
		return ListDetail{}, err
	}
	return l.Detail(ctx, id, user)
}

// Delete removes a list, as one undoable action.
func (l *Lists) Delete(ctx context.Context, id, user uuid.UUID) error {
	current, err := l.Detail(ctx, id, user)
	if err != nil {
		return err
	}
	_, err = l.apply(ctx, DeleteList(id), user, "Deleted list "+current.List.Name)
	return err
}

// Add adds a title at the end. Adding a member again changes nothing.
func (l *Lists) Add(ctx context.Context, ref core.MediaRef, id, user uuid.UUID) (ListDetail, error) {
	current, err := l.Detail(ctx, id, user)
	if err != nil {
		return ListDetail{}, err
	}
	title, err := l.Library.Catalog.Resolver().Resolve(ctx, ref, nil)
	if err != nil {
		return ListDetail{}, err
	}
	if slices.Contains(current.List.TitleIDs, title.ID) {
		return current, nil
	}
	members := append(slices.Clone(current.List.TitleIDs), title.ID)
	if _, err := l.apply(ctx, SetListMembers(id, members), user, "Added "+title.Title+" to "+current.List.Name); err != nil {
		return ListDetail{}, err
	}
	if title.Type == core.MediaShow {
		// Load episodes now so the row shows the next airing. Best effort, as for a library add;
		// the catalog refresher retries.
		if _, err := l.Library.Catalog.Service.Detail(ctx, title.ID); err != nil {
			l.Library.log().DebugContext(ctx, "episodes after list add", "title", title.ID, "error", err)
		}
	}
	return l.Detail(ctx, id, user)
}

// Remove takes a title off a list.
func (l *Lists) Remove(ctx context.Context, titleID, id, user uuid.UUID) (ListDetail, error) {
	current, err := l.Detail(ctx, id, user)
	if err != nil {
		return ListDetail{}, err
	}
	if !slices.Contains(current.List.TitleIDs, titleID) {
		return ListDetail{}, apperr.NotFound("That title is not on this list.")
	}
	name := "a title"
	for _, t := range current.Titles {
		if t.ID == titleID {
			name = t.Title
			break
		}
	}
	members := slices.DeleteFunc(slices.Clone(current.List.TitleIDs), func(t uuid.UUID) bool { return t == titleID })
	if _, err := l.apply(ctx, SetListMembers(id, members), user, "Removed "+name+" from "+current.List.Name); err != nil {
		return ListDetail{}, err
	}
	return l.Detail(ctx, id, user)
}

// Reorder is manual ordering: the new order must be exactly the current members.
func (l *Lists) Reorder(ctx context.Context, id uuid.UUID, order []uuid.UUID, user uuid.UUID) (ListDetail, error) {
	current, err := l.Detail(ctx, id, user)
	if err != nil {
		return ListDetail{}, err
	}
	if len(order) != len(current.List.TitleIDs) || !sameSet(order, current.List.TitleIDs) {
		return ListDetail{}, &apperr.Error{
			Status: http.StatusUnprocessableEntity, Code: "validation_failed",
			Message: "The order must list every title on the list exactly once.",
			Details: map[string]string{"titleIds": "Must be a permutation of the list's titles."},
		}
	}
	if slices.Equal(order, current.List.TitleIDs) {
		return current, nil
	}
	if _, err := l.apply(ctx, SetListMembers(id, order), user, "Reordered "+current.List.Name); err != nil {
		return ListDetail{}, err
	}
	return l.Detail(ctx, id, user)
}

func sameSet(a, b []uuid.UUID) bool {
	sa, sb := map[uuid.UUID]bool{}, map[uuid.UUID]bool{}
	for _, x := range a {
		sa[x] = true
	}
	for _, x := range b {
		sb[x] = true
	}
	if len(sa) != len(sb) {
		return false
	}
	for x := range sa {
		if !sb[x] {
			return false
		}
	}
	return true
}

// Shelves are saved queries (SHF-001, SHF-002). A shelf resolves through the same code as
// `GET /v1/library/items`, so the two return identical payloads for the same filter.
type Shelves struct {
	Library *Service
}

// All are the user's shelves.
func (s *Shelves) All(ctx context.Context, user uuid.UUID) ([]Shelf, error) {
	return s.Library.Store.Shelves(ctx, user)
}

// Get is one shelf; 404 "No such shelf." when the user has none by that id.
func (s *Shelves) Get(ctx context.Context, id, user uuid.UUID) (Shelf, error) {
	shelf, err := s.Library.Store.Shelf(ctx, id, user)
	if err != nil {
		return Shelf{}, err
	}
	if shelf == nil {
		return Shelf{}, apperr.NotFound("No such shelf.")
	}
	return *shelf, nil
}

// Create saves a new shelf.
func (s *Shelves) Create(ctx context.Context, name string, filter Filter, pinned bool, user uuid.UUID) (Shelf, error) {
	valid, err := validShelfName(name)
	if err != nil {
		return Shelf{}, err
	}
	shelf := Shelf{ID: uuid.New(), Name: valid, Filter: filter, IsPinned: pinned, CreatedAt: s.Library.now()}
	if err := s.Library.Store.SaveShelf(ctx, shelf, user); err != nil {
		return Shelf{}, err
	}
	if s.Library.Gamification != nil {
		s.Library.Gamification.AfterWrite(ctx, user, nil)
	}
	return shelf, nil
}

// Update changes the fields given.
func (s *Shelves) Update(ctx context.Context, id, user uuid.UUID, name *string, filter *Filter, pinned *bool) (Shelf, error) {
	shelf, err := s.Get(ctx, id, user)
	if err != nil {
		return Shelf{}, err
	}
	if name != nil {
		if shelf.Name, err = validShelfName(*name); err != nil {
			return Shelf{}, err
		}
	}
	if filter != nil {
		shelf.Filter = *filter
	}
	if pinned != nil {
		shelf.IsPinned = *pinned
	}
	if err := s.Library.Store.SaveShelf(ctx, shelf, user); err != nil {
		return Shelf{}, err
	}
	return shelf, nil
}

// Delete removes a shelf.
func (s *Shelves) Delete(ctx context.Context, id, user uuid.UUID) error {
	deleted, err := s.Library.Store.DeleteShelf(ctx, id, user)
	if err != nil {
		return err
	}
	if !deleted {
		return apperr.NotFound("No such shelf.")
	}
	return nil
}

// Items is a page of the shelf's query.
func (s *Shelves) Items(ctx context.Context, id, user uuid.UUID, cursor *string, limit int) ([]Entry, *string, error) {
	shelf, err := s.Get(ctx, id, user)
	if err != nil {
		return nil, nil, err
	}
	return s.Library.List(ctx, user, shelf.Filter, cursor, limit)
}

func validShelfName(name string) (string, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return "", apperr.Validation("name", "A shelf needs a name.")
	}
	return trimmed, nil
}
