package gamification

import (
	"aaru-go-api/internal/core"

	"github.com/google/uuid"
)

// LiveKinds are the journal kinds that are live writes. Imports, approved plans and list edits
// earn nothing per item.
var LiveKinds = map[string]bool{"add": true, "update": true, "remove": true, "episode": true, "season": true, "undo": true}

// WriteFacts is what one library write changed that points care about (LibraryWriteFacts),
// read from the op and the inverse the store computed for it. The inverse holds exactly what
// changed (the ticks added and removed, the previous fields), so the journal needs no finer kinds.
//
// The library package fills it while walking its op and inverse together (Swift's
// `LibraryWriteFacts.derive`): start with NewWriteFacts(kind), then for each (op, inverse) pair
// call Episodes, Fields or Inserted. A batch's inverses come back reversed, so pair
// `ops[i]` with `inverses[len-1-i]`. Every method is a no-op for a kind that is not live.
type WriteFacts struct {
	kind        string
	live        bool
	order       []uuid.UUID
	Ticked      map[uuid.UUID][]core.EpisodeKey
	Unticked    map[uuid.UUID][]core.EpisodeKey
	Finished    map[uuid.UUID]bool
	Unfinished  map[uuid.UUID]bool
	BookForward map[uuid.UUID]bool
}

// ProgressFields are the item fields points read (a subset of the library's ItemFields).
type ProgressFields struct {
	Status       core.LibraryStatus
	BookPage     *int
	BookPercent  *float64
	MangaChapter *int
	MangaVolume  *int
}

// NewWriteFacts starts the facts for a write of the journal kind.
func NewWriteFacts(kind string) *WriteFacts {
	return &WriteFacts{
		kind: kind, live: LiveKinds[kind],
		Ticked: map[uuid.UUID][]core.EpisodeKey{}, Unticked: map[uuid.UUID][]core.EpisodeKey{},
		Finished: map[uuid.UUID]bool{}, Unfinished: map[uuid.UUID]bool{}, BookForward: map[uuid.UUID]bool{},
	}
}

func (f *WriteFacts) see(item uuid.UUID) {
	for _, id := range f.order {
		if id == item {
			return
		}
	}
	f.order = append(f.order, item)
}

// Episodes is a `setEpisodes` op whose inverse is `setEpisodes(_, watch: removed, unwatch: added)`:
// pass the inverse's unwatch list as added and its watch list as removed.
func (f *WriteFacts) Episodes(item uuid.UUID, added, removed []core.EpisodeKey) {
	if !f.live {
		return
	}
	if len(added) > 0 {
		f.see(item)
		f.Ticked[item] = append(f.Ticked[item], added...)
	}
	if len(removed) > 0 {
		f.see(item)
		f.Unticked[item] = append(f.Unticked[item], removed...)
	}
}

// Fields is a `setFields(item, updated)` op whose inverse is `setFields(item, previous)`.
func (f *WriteFacts) Fields(item uuid.UUID, updated, previous ProgressFields) {
	if !f.live {
		return
	}
	switch {
	case updated.Status == core.StatusFinished && previous.Status != core.StatusFinished:
		f.see(item)
		f.Finished[item] = true
	case previous.Status == core.StatusFinished && updated.Status != core.StatusFinished:
		f.see(item)
		f.Unfinished[item] = true
	}
	if intOr0(updated.BookPage) > intOr0(previous.BookPage) || floatOr0(updated.BookPercent) > floatOr0(previous.BookPercent) ||
		intOr0(updated.MangaChapter) > intOr0(previous.MangaChapter) || intOr0(updated.MangaVolume) > intOr0(previous.MangaVolume) {
		f.see(item)
		f.BookForward[item] = true
	}
}

// Inserted is an `insertItem(snapshot)` op. A new item added as finished counts; an undo
// restoring a removed item does not (its finish was never revoked). Restored ticks are not
// activity either.
func (f *WriteFacts) Inserted(item uuid.UUID, status core.LibraryStatus) {
	if !f.live {
		return
	}
	if f.kind == "add" && status == core.StatusFinished {
		f.see(item)
		f.Finished[item] = true
	}
}

// IsEmpty is true when the write earns and revokes nothing.
func (f *WriteFacts) IsEmpty() bool {
	return len(f.Ticked) == 0 && len(f.Unticked) == 0 && len(f.Finished) == 0 && len(f.Unfinished) == 0 &&
		len(f.BookForward) == 0
}

// ItemIDs are the items the facts name, first seen first.
func (f *WriteFacts) ItemIDs() []uuid.UUID {
	return append([]uuid.UUID(nil), f.order...)
}

func intOr0(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

func floatOr0(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}
