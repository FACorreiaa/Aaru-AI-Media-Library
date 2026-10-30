package schedule

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"time"

	"github.com/google/uuid"
)

// CalendarKind marks a season's first and last episode.
type CalendarKind string

// The calendar kinds.
const (
	KindPremiere CalendarKind = "premiere"
	KindFinale   CalendarKind = "finale"
	KindRegular  CalendarKind = "regular"
)

// CalendarEntry is one airing episode of a tracked show (CAL-001). Times are UTC; clients localize.
type CalendarEntry struct {
	LibraryItemID  uuid.UUID
	Title          core.Title
	Key            core.EpisodeKey
	EpisodeName    *string
	AirsAt         time.Time
	RuntimeMinutes *int
	Watched        bool
	Kind           CalendarKind
	// AirTimeKnown is false when the source gives only a date: AirsAt is then midnight UTC of
	// that date and clients show the day without a time.
	AirTimeKnown    bool
	EpisodeOverview *string
	// StillURL is the episode's still (TMDB), for the calendar's episode sheet.
	StillURL *string
}

// ContinueEntry is a show to continue (UPN-001): the next aired episode not yet watched.
type ContinueEntry struct {
	LibraryItemID      uuid.UUID
	Title              core.Title
	Next               core.EpisodeKey
	NextName           *string
	NextRuntimeMinutes *int
	// RemainingCount is aired, unwatched, non-special episodes, including Next.
	RemainingCount   int
	RemainingMinutes int
	// IsFinale: Next is the last episode of its season.
	IsFinale bool
}

// WatchingRow is one title on Library's Watching page (APP-018): the entry, a show's status and
// next episode to air, and what is left to watch when an aired episode is.
type WatchingRow struct {
	Entry  LibraryEntry
	Airing *catalog.TitleAiring
	Next   *ContinueEntry
}

// StartEntry is a wishlist title to start.
type StartEntry struct {
	LibraryItemID  uuid.UUID
	Title          core.Title
	RuntimeMinutes *int
}

// LibraryCounts is how many of the user's items are in each status (UPN-002).
type LibraryCounts struct {
	Wishlist, InProgress, OnHold, Finished, Dropped int
}

// UnfinishedReason is why an item is unfinished business.
type UnfinishedReason string

// The unfinished reasons.
const (
	ReasonDropped UnfinishedReason = "dropped"
	ReasonStalled UnfinishedReason = "stalled"
)

// UnfinishedEntry is unfinished business (UPN-002): a dropped item, or one in progress and
// untouched for a while.
type UnfinishedEntry struct {
	LibraryItemID uuid.UUID
	Title         core.Title
	Reason        UnfinishedReason
	// Since is the item's last change.
	Since time.Time
	// Next is shows only: the first aired episode not yet watched.
	Next *core.EpisodeKey
}

// UpNext is everything the home screen's rows need, in one answer.
type UpNext struct {
	ContinueWatching []ContinueEntry
	StartWatching    []StartEntry
	Counts           LibraryCounts
	Unfinished       []UnfinishedEntry
}
