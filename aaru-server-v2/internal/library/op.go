// Package library is the user's library (Library/*.swift): items, episode progress, lists,
// shelves, the action journal and undo.
//
// Every mutating library path (a tap, an agent call, an import, an undo) is expressed as an Op.
// Applying an op returns its exact inverse, which the journal stores (AUD-001) and undo applies
// (AUD-002), so nothing writes without an inverse (X-007).
//
// The API other areas call:
//
//   - Service.Add / Patch / PatchWrite / Delete / SetEpisode / SetEpisodes / MarkSeasonWatched /
//     MarkShowWatched: the tap-shaped writes, each one journaled action, with gamification hooks.
//   - Service.Prepare* + Service.Commit: the dry-run half and the commit of a write, for plans
//     (AG-003) that store a PreparedWrite's Op and apply it on approval.
//   - Store.Apply: one raw op as one journaled action (imports use it with kind "import").
//   - Service.Entry / Item / ItemForTitle / List / Sync / Actions / Undo: reads and undo.
//   - Store.ImportStates / StatusSetByHand / Watched / WatchedOf: what imports decide against.
//   - Lists and Shelves: list membership (journaled) and saved queries.
//
// Ops are stored as JSON in `actions.inverse` and `agent_plans.op` in the encoding the Swift
// server wrote (Swift's synthesized Codable for an enum with associated values, Foundation's
// default JSONEncoder: dates as seconds since 2001-01-01, uppercase UUIDs), so either server
// can undo or apply what the other stored.
package library

import (
	"aaru-go-api/internal/core"
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ItemFields are the user-editable fields of a library item. Episode progress is separate.
type ItemFields struct {
	Status      core.LibraryStatus
	Rating      *float64
	Notes       *string
	IsOwned     bool
	FinishedAt  *time.Time
	BookPage    *int
	BookPercent *float64
	// MangaChapter and MangaVolume are the last chapter and volume read (MNG-001).
	MangaChapter *int
	MangaVolume  *int
	// StatusByHand: the user chose this status themselves, so an import never moves it. nil leaves
	// the stored flag as it is; inverses carry the stored value, so undo restores it.
	StatusByHand *bool
}

// Equal compares every field, as Swift's synthesized Equatable does.
func (f ItemFields) Equal(o ItemFields) bool {
	return f.Status == o.Status && eqPtr(f.Rating, o.Rating) && eqPtr(f.Notes, o.Notes) && f.IsOwned == o.IsOwned &&
		eqTime(f.FinishedAt, o.FinishedAt) && eqPtr(f.BookPage, o.BookPage) && eqPtr(f.BookPercent, o.BookPercent) &&
		eqPtr(f.MangaChapter, o.MangaChapter) && eqPtr(f.MangaVolume, o.MangaVolume) && eqPtr(f.StatusByHand, o.StatusByHand)
}

func eqPtr[T comparable](a, b *T) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func eqTime(a, b *time.Time) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return a.Equal(*b)
}

// ItemSnapshot is everything needed to recreate a deleted item, including its episode ticks.
type ItemSnapshot struct {
	ID      uuid.UUID
	TitleID uuid.UUID
	Fields  ItemFields
	AddedAt time.Time
	Watched []core.EpisodeKey
}

// ListSnapshot is everything needed to recreate a deleted list.
type ListSnapshot struct {
	ID        uuid.UUID
	Name      string
	CreatedAt time.Time
	Members   []uuid.UUID
}

// OpKind names one primitive library write.
type OpKind string

// The op kinds, named as Swift's LibraryOp cases (the JSON keys).
const (
	OpInsertItem     OpKind = "insertItem"
	OpDeleteItem     OpKind = "deleteItem"
	OpSetFields      OpKind = "setFields"
	OpSetEpisodes    OpKind = "setEpisodes"
	OpInsertList     OpKind = "insertList"
	OpDeleteList     OpKind = "deleteList"
	OpRenameList     OpKind = "renameList"
	OpSetListMembers OpKind = "setListMembers"
	OpBatch          OpKind = "batch"
)

// Op is one primitive library write (LibraryOp). Build it with the constructors; only the fields
// of its kind are set.
type Op struct {
	Kind OpKind
	// Item is the item of deleteItem, setFields and setEpisodes.
	Item uuid.UUID
	// Snapshot is insertItem's.
	Snapshot *ItemSnapshot
	// Fields is setFields'.
	Fields *ItemFields
	// Watch and Unwatch are setEpisodes'.
	Watch, Unwatch []core.EpisodeKey
	// List is the list of deleteList, renameList and setListMembers.
	List uuid.UUID
	// ListSnapshot is insertList's.
	ListSnapshot *ListSnapshot
	// Name is renameList's.
	Name string
	// Members is setListMembers': the list's full ordered membership (add, remove and reorder).
	Members []uuid.UUID
	// Ops is batch's.
	Ops []Op
}

// InsertItem creates an item from a snapshot.
func InsertItem(s ItemSnapshot) Op { return Op{Kind: OpInsertItem, Snapshot: &s} }

// DeleteItem removes an item.
func DeleteItem(id uuid.UUID) Op { return Op{Kind: OpDeleteItem, Item: id} }

// SetFields replaces an item's fields.
func SetFields(id uuid.UUID, f ItemFields) Op { return Op{Kind: OpSetFields, Item: id, Fields: &f} }

// SetEpisodes ticks and unticks episodes of an item.
func SetEpisodes(id uuid.UUID, watch, unwatch []core.EpisodeKey) Op {
	return Op{Kind: OpSetEpisodes, Item: id, Watch: nonNilKeys(watch), Unwatch: nonNilKeys(unwatch)}
}

// InsertList creates a list from a snapshot.
func InsertList(s ListSnapshot) Op { return Op{Kind: OpInsertList, ListSnapshot: &s} }

// DeleteList removes a list.
func DeleteList(id uuid.UUID) Op { return Op{Kind: OpDeleteList, List: id} }

// RenameList renames a list.
func RenameList(id uuid.UUID, name string) Op { return Op{Kind: OpRenameList, List: id, Name: name} }

// SetListMembers sets a list's full ordered membership.
func SetListMembers(id uuid.UUID, members []uuid.UUID) Op {
	if members == nil {
		members = []uuid.UUID{}
	}
	return Op{Kind: OpSetListMembers, List: id, Members: members}
}

// Batch is several ops as one write; its inverse is the children's inverses, reversed.
func Batch(ops ...Op) Op {
	if ops == nil {
		ops = []Op{}
	}
	return Op{Kind: OpBatch, Ops: ops}
}

func nonNilKeys(k []core.EpisodeKey) []core.EpisodeKey {
	if k == nil {
		return []core.EpisodeKey{}
	}
	return k
}

// ItemIDs are the items this op touches, for the journal's `item_ids`: unique, sorted.
func (o Op) ItemIDs() []uuid.UUID {
	switch o.Kind {
	case OpInsertItem:
		return []uuid.UUID{o.Snapshot.ID}
	case OpDeleteItem, OpSetFields, OpSetEpisodes:
		return []uuid.UUID{o.Item}
	case OpBatch:
		seen := map[uuid.UUID]bool{}
		var out []uuid.UUID
		for _, child := range o.Ops {
			for _, id := range child.ItemIDs() {
				if !seen[id] {
					seen[id] = true
					out = append(out, id)
				}
			}
		}
		sortIDs(out)
		if out == nil {
			return []uuid.UUID{}
		}
		return out
	}
	return []uuid.UUID{}
}

// sortIDs orders by uuidString, which for uppercase hex is byte order.
func sortIDs(ids []uuid.UUID) {
	slices.SortFunc(ids, func(a, b uuid.UUID) int { return bytes.Compare(a[:], b[:]) })
}

// MARK: JSON (Swift's synthesized Codable)

// referenceDate is Foundation's 2001-01-01T00:00:00Z, the epoch of Date's default encoding.
var referenceDate = time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)

// swiftDate is a Date as Foundation's default JSONEncoder writes it: seconds since 2001-01-01.
type swiftDate time.Time

func (d swiftDate) MarshalJSON() ([]byte, error) {
	secs := float64(time.Time(d).Sub(referenceDate).Microseconds()) / 1e6
	return json.Marshal(secs)
}

// UnmarshalJSON reads seconds since 2001-01-01 (or an ISO 8601 string, leniently).
func (d *swiftDate) UnmarshalJSON(data []byte) error {
	var secs float64
	if err := json.Unmarshal(data, &secs); err == nil {
		micros := math.Round(secs * 1e6)
		*d = swiftDate(referenceDate.Add(time.Duration(micros) * time.Microsecond))
		return nil
	}
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return fmt.Errorf("date: %w", err)
	}
	t, err := time.Parse(time.RFC3339Nano, text)
	if err != nil {
		return fmt.Errorf("date: %w", err)
	}
	*d = swiftDate(t)
	return nil
}

func datePtr(t *time.Time) *swiftDate {
	if t == nil {
		return nil
	}
	d := swiftDate(*t)
	return &d
}

func timePtr(d *swiftDate) *time.Time {
	if d == nil {
		return nil
	}
	t := time.Time(*d).UTC()
	return &t
}

// swiftUUID is a UUID as Foundation writes it: uppercase.
type swiftUUID uuid.UUID

func (u swiftUUID) MarshalJSON() ([]byte, error) {
	return json.Marshal(strings.ToUpper(uuid.UUID(u).String()))
}

func (u *swiftUUID) UnmarshalJSON(data []byte) error {
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return err
	}
	id, err := uuid.Parse(text)
	if err != nil {
		return fmt.Errorf("uuid: %w", err)
	}
	*u = swiftUUID(id)
	return nil
}

func swiftUUIDs(ids []uuid.UUID) []swiftUUID {
	out := make([]swiftUUID, len(ids))
	for i, id := range ids {
		out[i] = swiftUUID(id)
	}
	return out
}

func plainUUIDs(ids []swiftUUID) []uuid.UUID {
	out := make([]uuid.UUID, len(ids))
	for i, id := range ids {
		out[i] = uuid.UUID(id)
	}
	return out
}

type fieldsJSON struct {
	Status       core.LibraryStatus `json:"status"`
	Rating       *float64           `json:"rating,omitempty"`
	Notes        *string            `json:"notes,omitempty"`
	IsOwned      bool               `json:"isOwned"`
	FinishedAt   *swiftDate         `json:"finishedAt,omitempty"`
	BookPage     *int               `json:"bookPage,omitempty"`
	BookPercent  *float64           `json:"bookPercent,omitempty"`
	MangaChapter *int               `json:"mangaChapter,omitempty"`
	MangaVolume  *int               `json:"mangaVolume,omitempty"`
	StatusByHand *bool              `json:"statusByHand,omitempty"`
}

// MarshalJSON writes Swift's ItemFields encoding.
func (f ItemFields) MarshalJSON() ([]byte, error) {
	return json.Marshal(fieldsJSON{
		Status: f.Status, Rating: f.Rating, Notes: f.Notes, IsOwned: f.IsOwned, FinishedAt: datePtr(f.FinishedAt),
		BookPage: f.BookPage, BookPercent: f.BookPercent, MangaChapter: f.MangaChapter, MangaVolume: f.MangaVolume,
		StatusByHand: f.StatusByHand,
	})
}

// UnmarshalJSON reads Swift's ItemFields encoding.
func (f *ItemFields) UnmarshalJSON(data []byte) error {
	var raw fieldsJSON
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	if !raw.Status.Valid() {
		return fmt.Errorf("item fields: unknown status %q", raw.Status)
	}
	*f = ItemFields{
		Status: raw.Status, Rating: raw.Rating, Notes: raw.Notes, IsOwned: raw.IsOwned, FinishedAt: timePtr(raw.FinishedAt),
		BookPage: raw.BookPage, BookPercent: raw.BookPercent, MangaChapter: raw.MangaChapter, MangaVolume: raw.MangaVolume,
		StatusByHand: raw.StatusByHand,
	}
	return nil
}

type snapshotJSON struct {
	ID      swiftUUID         `json:"id"`
	TitleID swiftUUID         `json:"titleID"`
	Fields  ItemFields        `json:"fields"`
	AddedAt swiftDate         `json:"addedAt"`
	Watched []core.EpisodeKey `json:"watched"`
}

type listSnapshotJSON struct {
	ID        swiftUUID   `json:"id"`
	Name      string      `json:"name"`
	CreatedAt swiftDate   `json:"createdAt"`
	Members   []swiftUUID `json:"members"`
}

// MarshalJSON writes `{"<case>": {"_0": …, "_1": …}}` as Swift's synthesized Codable does; the
// labeled setEpisodes payload uses its labels (`watch`, `unwatch`).
func (o Op) MarshalJSON() ([]byte, error) {
	var payload any
	switch o.Kind {
	case OpInsertItem:
		s := o.Snapshot
		payload = map[string]any{"_0": snapshotJSON{
			ID: swiftUUID(s.ID), TitleID: swiftUUID(s.TitleID), Fields: s.Fields, AddedAt: swiftDate(s.AddedAt),
			Watched: nonNilKeys(s.Watched),
		}}
	case OpDeleteItem:
		payload = map[string]any{"_0": swiftUUID(o.Item)}
	case OpSetFields:
		payload = map[string]any{"_0": swiftUUID(o.Item), "_1": *o.Fields}
	case OpSetEpisodes:
		payload = map[string]any{"_0": swiftUUID(o.Item), "watch": nonNilKeys(o.Watch), "unwatch": nonNilKeys(o.Unwatch)}
	case OpInsertList:
		s := o.ListSnapshot
		payload = map[string]any{"_0": listSnapshotJSON{
			ID: swiftUUID(s.ID), Name: s.Name, CreatedAt: swiftDate(s.CreatedAt), Members: swiftUUIDs(s.Members),
		}}
	case OpDeleteList:
		payload = map[string]any{"_0": swiftUUID(o.List)}
	case OpRenameList:
		payload = map[string]any{"_0": swiftUUID(o.List), "_1": o.Name}
	case OpSetListMembers:
		payload = map[string]any{"_0": swiftUUID(o.List), "_1": swiftUUIDs(o.Members)}
	case OpBatch:
		ops := o.Ops
		if ops == nil {
			ops = []Op{}
		}
		payload = map[string]any{"_0": ops}
	default:
		return nil, fmt.Errorf("library op: unknown kind %q", o.Kind)
	}
	return json.Marshal(map[string]any{string(o.Kind): payload})
}

// UnmarshalJSON reads Swift's encoding of a LibraryOp.
func (o *Op) UnmarshalJSON(data []byte) error {
	var outer map[string]json.RawMessage
	if err := json.Unmarshal(data, &outer); err != nil {
		return fmt.Errorf("library op: %w", err)
	}
	if len(outer) != 1 {
		return fmt.Errorf("library op: want one case, got %d", len(outer))
	}
	for key, body := range outer {
		var p map[string]json.RawMessage
		if err := json.Unmarshal(body, &p); err != nil {
			return fmt.Errorf("library op %s: %w", key, err)
		}
		op, err := decodeOp(OpKind(key), p)
		if err != nil {
			return fmt.Errorf("library op %s: %w", key, err)
		}
		*o = op
	}
	return nil
}

func field[T any](p map[string]json.RawMessage, name string) (T, error) {
	var v T
	raw, ok := p[name]
	if !ok {
		return v, fmt.Errorf("missing %s", name)
	}
	err := json.Unmarshal(raw, &v)
	return v, err
}

func decodeOp(kind OpKind, p map[string]json.RawMessage) (Op, error) {
	switch kind {
	case OpInsertItem:
		s, err := field[snapshotJSON](p, "_0")
		if err != nil {
			return Op{}, err
		}
		return InsertItem(ItemSnapshot{
			ID: uuid.UUID(s.ID), TitleID: uuid.UUID(s.TitleID), Fields: s.Fields, AddedAt: time.Time(s.AddedAt).UTC(),
			Watched: nonNilKeys(s.Watched),
		}), nil
	case OpDeleteItem, OpDeleteList:
		id, err := field[swiftUUID](p, "_0")
		if err != nil {
			return Op{}, err
		}
		if kind == OpDeleteItem {
			return DeleteItem(uuid.UUID(id)), nil
		}
		return DeleteList(uuid.UUID(id)), nil
	case OpSetFields:
		id, err := field[swiftUUID](p, "_0")
		if err != nil {
			return Op{}, err
		}
		f, err := field[ItemFields](p, "_1")
		if err != nil {
			return Op{}, err
		}
		return SetFields(uuid.UUID(id), f), nil
	case OpSetEpisodes:
		id, err := field[swiftUUID](p, "_0")
		if err != nil {
			return Op{}, err
		}
		watch, err := field[[]core.EpisodeKey](p, "watch")
		if err != nil {
			return Op{}, err
		}
		unwatch, err := field[[]core.EpisodeKey](p, "unwatch")
		if err != nil {
			return Op{}, err
		}
		return SetEpisodes(uuid.UUID(id), watch, unwatch), nil
	case OpInsertList:
		s, err := field[listSnapshotJSON](p, "_0")
		if err != nil {
			return Op{}, err
		}
		return InsertList(ListSnapshot{
			ID: uuid.UUID(s.ID), Name: s.Name, CreatedAt: time.Time(s.CreatedAt).UTC(), Members: plainUUIDs(s.Members),
		}), nil
	case OpRenameList:
		id, err := field[swiftUUID](p, "_0")
		if err != nil {
			return Op{}, err
		}
		name, err := field[string](p, "_1")
		if err != nil {
			return Op{}, err
		}
		return RenameList(uuid.UUID(id), name), nil
	case OpSetListMembers:
		id, err := field[swiftUUID](p, "_0")
		if err != nil {
			return Op{}, err
		}
		members, err := field[[]swiftUUID](p, "_1")
		if err != nil {
			return Op{}, err
		}
		return SetListMembers(uuid.UUID(id), plainUUIDs(members)), nil
	case OpBatch:
		ops, err := field[[]Op](p, "_0")
		if err != nil {
			return Op{}, err
		}
		return Batch(ops...), nil
	}
	return Op{}, fmt.Errorf("unknown case")
}
