package imports

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"fmt"
	"slices"
	"strings"

	"github.com/google/uuid"
)

// What an import does to one title (IMP-004, ImportService+Decide). It never overwrites: it fills
// an empty rating, finish date or notes, sets owned but never clears it (IMP-020), adds missing
// ticks, and moves a status forward (wishlist → in progress → finished), never backward, never out
// of dropped, never past a status the user chose. In progress and on hold are one step; a source
// may move an item between them (LIB-007).

// Decision is what an import does to one title.
type Decision struct {
	Outcome       Outcome
	Reason        *string
	Fields        *library.ItemFields
	FieldsChanged bool
	ItemID        *uuid.UUID
	// Watch are episodes to tick: all of them on create, only the missing ones on update.
	Watch []core.EpisodeKey
}

// ImportRank is how far along a status is, for imports that only move forward. Dropped is not on
// the line: an import never moves an item into or out of it. On hold ranks with in progress
// (LIB-007): the import moves between the two sideways only.
func ImportRank(s core.LibraryStatus) int {
	switch s {
	case core.StatusWishlist:
		return 0
	case core.StatusInProgress, core.StatusOnHold:
		return 1
	case core.StatusFinished:
		return 2
	case core.StatusDropped:
		return -1
	}
	return -1
}

// Decide is what the row does to the title; item is the user's item as ImportStates read it, nil
// when they have none.
func Decide(row Row, item *library.ImportItemState) Decision {
	if item == nil {
		status := core.StatusWishlist
		switch {
		case row.Status != nil:
			status = *row.Status
		case row.HasProgress():
			status = core.StatusInProgress
		}
		isManga := row.Type == core.MediaManga
		fields := library.ItemFields{Status: status, Rating: rating(row.Rating), Notes: row.Notes, IsOwned: isTrue(row.IsOwned)}
		if status == core.StatusFinished {
			fields.FinishedAt = row.FinishedAt
		}
		if isManga {
			fields.MangaChapter, fields.MangaVolume = row.MangaChapter, row.MangaVolume
		}
		watch := row.Watched
		if watch == nil {
			watch = []core.EpisodeKey{}
		}
		return Decision{Outcome: OutcomeCreate, Fields: &fields, Watch: watch}
	}
	fields := item.Fields
	moved := promote(&fields, row, item.StatusByHand)
	var filled []string
	if fields.Rating == nil {
		if r := rating(row.Rating); r != nil {
			fields.Rating = r
			filled = append(filled, "rating")
		}
	}
	if fields.FinishedAt == nil && fields.Status == core.StatusFinished && row.FinishedAt != nil {
		fields.FinishedAt = row.FinishedAt
		filled = append(filled, "finish date")
	}
	if (fields.Notes == nil || strings.TrimSpace(*fields.Notes) == "") && row.Notes != nil {
		fields.Notes = row.Notes
		filled = append(filled, "notes")
	}
	if !fields.IsOwned && isTrue(row.IsOwned) {
		fields.IsOwned = true
		filled = append(filled, "owned mark")
	}
	if row.Type == core.MediaManga {
		filled = append(filled, forwardMangaProgress(&fields, row)...)
	}
	fieldsChanged := moved != nil || len(filled) > 0
	var missing []core.EpisodeKey
	for _, k := range row.Watched {
		if !item.Watched[k] {
			missing = append(missing, k)
		}
	}
	slices.SortFunc(missing, core.EpisodeKey.Compare)
	if len(missing) == 1 {
		filled = append(filled, "1 watched episode")
	} else if len(missing) > 1 {
		filled = append(filled, fmt.Sprintf("%d watched episodes", len(missing)))
	}
	reason := decisionReason(moved, filled, row.Type)
	if reason == nil {
		return Decision{Outcome: OutcomeSkip, Reason: ptr("Already on your shelf; nothing new to add.")}
	}
	itemID := item.ItemID
	if missing == nil {
		missing = []core.EpisodeKey{}
	}
	return Decision{
		Outcome: OutcomeUpdate, Reason: reason, Fields: &fields, FieldsChanged: fieldsChanged, ItemID: &itemID,
		Watch: missing,
	}
}

// promote moves the status forward when the row is further along, or sideways between in progress
// and on hold (LIB-007) when the row says so. It returns the new status, if any.
func promote(fields *library.ItemFields, row Row, byHand bool) *core.LibraryStatus {
	var incoming *core.LibraryStatus
	switch {
	case row.Status != nil:
		incoming = row.Status
	case row.HasProgress():
		incoming = ptr(core.StatusInProgress)
	}
	if incoming == nil || fields.Status == core.StatusDropped || byHand {
		return nil
	}
	if ImportRank(*incoming) <= ImportRank(fields.Status) && !sideways(fields.Status, *incoming, row) {
		return nil
	}
	fields.Status = *incoming
	return ptr(*incoming)
}

// sideways is in progress ↔ on hold, the one move that is not forward. Any row that says on hold
// pauses an item in progress; only a source that has on hold (Row.KnowsOnHold) resumes one, so a
// Trakt or Netflix history, where everything started is in progress, never does.
func sideways(current, incoming core.LibraryStatus, row Row) bool {
	switch {
	case current == core.StatusInProgress && incoming == core.StatusOnHold:
		return true
	case current == core.StatusOnHold && incoming == core.StatusInProgress:
		return row.Status != nil && *row.Status == core.StatusInProgress && isTrue(row.KnowsOnHold)
	}
	return false
}

// forwardMangaProgress moves a reading position forward only, like ticks are only added. It
// returns what it filled.
func forwardMangaProgress(fields *library.ItemFields, row Row) []string {
	var filled []string
	if row.MangaChapter != nil && *row.MangaChapter > deref(fields.MangaChapter) {
		fields.MangaChapter = ptr(*row.MangaChapter)
		filled = append(filled, fmt.Sprintf("chapter %d", *row.MangaChapter))
	}
	if row.MangaVolume != nil && *row.MangaVolume > deref(fields.MangaVolume) {
		fields.MangaVolume = ptr(*row.MangaVolume)
		filled = append(filled, fmt.Sprintf("volume %d", *row.MangaVolume))
	}
	return filled
}

func deref(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

func decisionReason(moved *core.LibraryStatus, filled []string, mediaType core.MediaType) *string {
	adds := ""
	if len(filled) > 0 {
		adds = "adds the " + strings.Join(filled, " and ")
	}
	switch {
	case moved != nil && adds != "":
		return ptr("Moves it to " + library.StatusLabel(*moved, mediaType) + " and " + adds + ".")
	case moved != nil:
		return ptr("Moves it to " + library.StatusLabel(*moved, mediaType) + ".")
	case adds != "":
		return ptr("A" + adds[1:] + ".")
	}
	return nil
}
