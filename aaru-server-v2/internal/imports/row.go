package imports

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
)

// Airing is one episode a calendar says a show airs, and the day (`YYYY-MM-DD`). When several
// shows share a CAT name, the one that airs that episode that day is the match (IMP-010).
type Airing = catalog.ImportAiring

// NamedEpisode is an episode a source names but does not number (Netflix, IMP-018).
type NamedEpisode = catalog.NamedEpisode

// Row is one row of an import, as the parser read it (ImportRow). This is what is kept; the
// uploaded file is not. It is stored as JSON in `import_rows.row` in the shape Swift's
// synthesized Codable wrote (MarshalJSON), so either server reads the other's rows.
type Row struct {
	// SourceKey is the row's identity in its source, for the person reading the plan (a
	// Letterboxd URI, an IMDb const, a Goodreads book id).
	SourceKey *string
	Type      core.MediaType
	Title     string
	Year      *int
	// Author is the authors, for books: narrows a title search when there is no ISBN.
	Author *string
	IDs    core.ExternalIDs
	// Status is what the source says about the user's relationship. nil says nothing.
	Status *core.LibraryStatus
	// Rating is on Aaru's 1–10 scale.
	Rating     *float64
	FinishedAt *time.Time
	// Lists are Goodreads custom shelves: each becomes one Aaru list.
	Lists []string
	// Unsupported is set when the parser already knows the row cannot be imported.
	Unsupported *string
	// Watched are watched episodes, for shows. Ticked on create; missing ones filled on update.
	// nil says nothing about episodes; an empty, non-nil slice is Swift's empty array.
	Watched []core.EpisodeKey
	// MangaChapter and MangaVolume are the last chapter and volume read (MNG-002). Moved
	// forward on update, never back.
	MangaChapter *int
	MangaVolume  *int
	// ListOnly is set on a source list only: the row joins that list, never the library.
	ListOnly *bool
	// StremioWatched is Stremio's compressed watched-episode bitfield, still undecoded. The
	// worker turns it into Watched once it has the show's episode list, then clears it.
	StremioWatched *string
	// NameOnly: Pogdesign CAT gives a show's name and nothing else, matched by exact name
	// across every year, only when exactly one show has it (IMP-009). On a row with ids (TV
	// Time, IMP-012), the same exact-name match is tried only when no provider knows the ids.
	NameOnly *bool
	// Airing is one episode CAT's calendar says this show airs (IMP-010).
	Airing *Airing
	// NamedEpisodes are the episodes Netflix names (IMP-018), numbered into Watched once the
	// show is matched, then cleared (nil). Non-nil and empty is kept apart from nil, as Swift did.
	NamedEpisodes []NamedEpisode
	// NotAfter is, on a name-only row, the year it was first watched, so a title released later
	// is not it.
	NotAfter *int
	// Notes are the source's own words about the title (IMP-020). They fill empty notes only.
	Notes *string
	// IsOwned: the source says the user owns a copy (IMP-020). Only ever sets the flag.
	IsOwned *bool
	// KnowsOnHold: the source has an on-hold status (MyAnimeList, AniList), so its "watching"
	// means not on hold and such a row may resume an on-hold item (LIB-007).
	KnowsOnHold *bool
}

// MediaRef is what the resolver matches the row by.
func (r Row) MediaRef() core.MediaRef {
	title := r.Title
	return core.MediaRef{Type: r.Type, IDs: r.IDs, Title: &title, Year: r.Year}
}

// HasProgress is ticks or a reading position: the row is under way even when it names no status.
func (r Row) HasProgress() bool {
	return len(r.Watched) > 0 || (r.MangaChapter != nil && *r.MangaChapter > 0) ||
		(r.MangaVolume != nil && *r.MangaVolume > 0)
}

// Outcome is what a plan does with one row (ImportOutcome).
type Outcome string

// The outcomes.
const (
	OutcomePending Outcome = "pending"
	// OutcomeCreate is a new library item.
	OutcomeCreate Outcome = "create"
	// OutcomeUpdate is an existing item gaining a field it did not have (fill-empty only, IMP-004).
	OutcomeUpdate Outcome = "update"
	// OutcomeSkip is already on the shelf with nothing new, or a repeat of an earlier row.
	OutcomeSkip Outcome = "skip"
	// OutcomeUnmatched is a row no title could be matched to; listed for the person to fix.
	OutcomeUnmatched Outcome = "unmatched"
)

// PlannedRow is a stored row with its plan.
type PlannedRow struct {
	Index   int
	Row     Row
	Outcome Outcome
	Reason  *string
	TitleID *uuid.UUID
}

// FormatError is a file that does not look like the source it claims to be (ImportFormatError).
type FormatError struct {
	Message string
}

func (e *FormatError) Error() string { return e.Message }

// formatError builds a FormatError.
func formatError(message string) error { return &FormatError{Message: message} }

// MARK: Swift-compatible JSON

// referenceEpoch is Foundation's reference date: Swift's default JSONEncoder writes a Date as
// seconds since it.
var referenceEpoch = time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)

// swiftDate is a Date as Swift's default JSONEncoder writes it.
type swiftDate time.Time

func (d swiftDate) MarshalJSON() ([]byte, error) {
	seconds := float64(time.Time(d).Sub(referenceEpoch)) / float64(time.Second)
	return json.Marshal(seconds)
}

func (d *swiftDate) UnmarshalJSON(data []byte) error {
	var seconds float64
	if err := json.Unmarshal(data, &seconds); err != nil {
		return fmt.Errorf("swift date: %w", err)
	}
	whole, frac := math.Modf(seconds)
	*d = swiftDate(referenceEpoch.Add(time.Duration(whole) * time.Second).Add(time.Duration(frac * float64(time.Second))).UTC())
	return nil
}

type rowJSON struct {
	SourceKey      *string             `json:"sourceKey,omitempty"`
	Type           core.MediaType      `json:"type"`
	Title          string              `json:"title"`
	Year           *int                `json:"year,omitempty"`
	Author         *string             `json:"author,omitempty"`
	IDs            core.ExternalIDs    `json:"ids"`
	Status         *core.LibraryStatus `json:"status,omitempty"`
	Rating         *float64            `json:"rating,omitempty"`
	FinishedAt     *swiftDate          `json:"finishedAt,omitempty"`
	Lists          []string            `json:"lists"`
	Unsupported    *string             `json:"unsupported,omitempty"`
	Watched        *[]core.EpisodeKey  `json:"watched,omitempty"`
	MangaChapter   *int                `json:"mangaChapter,omitempty"`
	MangaVolume    *int                `json:"mangaVolume,omitempty"`
	ListOnly       *bool               `json:"listOnly,omitempty"`
	StremioWatched *string             `json:"stremioWatched,omitempty"`
	NameOnly       *bool               `json:"nameOnly,omitempty"`
	Airing         *Airing             `json:"airing,omitempty"`
	NamedEpisodes  *[]NamedEpisode     `json:"namedEpisodes,omitempty"`
	NotAfter       *int                `json:"notAfter,omitempty"`
	Notes          *string             `json:"notes,omitempty"`
	IsOwned        *bool               `json:"isOwned,omitempty"`
	KnowsOnHold    *bool               `json:"knowsOnHold,omitempty"`
}

// MarshalJSON writes the row as Swift's synthesized Codable did: absent optionals left out,
// `ids` and `lists` always present, dates as seconds since 2001.
func (r Row) MarshalJSON() ([]byte, error) {
	out := rowJSON{
		SourceKey: r.SourceKey, Type: r.Type, Title: r.Title, Year: r.Year, Author: r.Author, IDs: r.IDs,
		Status: r.Status, Rating: r.Rating, Lists: r.Lists, Unsupported: r.Unsupported,
		MangaChapter: r.MangaChapter, MangaVolume: r.MangaVolume, ListOnly: r.ListOnly,
		StremioWatched: r.StremioWatched, NameOnly: r.NameOnly, Airing: r.Airing, NotAfter: r.NotAfter,
		Notes: r.Notes, IsOwned: r.IsOwned, KnowsOnHold: r.KnowsOnHold,
	}
	if out.Lists == nil {
		out.Lists = []string{}
	}
	if r.FinishedAt != nil {
		d := swiftDate(*r.FinishedAt)
		out.FinishedAt = &d
	}
	if r.Watched != nil {
		out.Watched = &r.Watched
	}
	if r.NamedEpisodes != nil {
		out.NamedEpisodes = &r.NamedEpisodes
	}
	return json.Marshal(out)
}

// UnmarshalJSON reads a row either server stored.
func (r *Row) UnmarshalJSON(data []byte) error {
	var in rowJSON
	if err := json.Unmarshal(data, &in); err != nil {
		return fmt.Errorf("import row: %w", err)
	}
	*r = Row{
		SourceKey: in.SourceKey, Type: in.Type, Title: in.Title, Year: in.Year, Author: in.Author, IDs: in.IDs,
		Status: in.Status, Rating: in.Rating, Lists: in.Lists, Unsupported: in.Unsupported,
		MangaChapter: in.MangaChapter, MangaVolume: in.MangaVolume, ListOnly: in.ListOnly,
		StremioWatched: in.StremioWatched, NameOnly: in.NameOnly, Airing: in.Airing, NotAfter: in.NotAfter,
		Notes: in.Notes, IsOwned: in.IsOwned, KnowsOnHold: in.KnowsOnHold,
	}
	if r.Lists == nil {
		r.Lists = []string{}
	}
	if in.FinishedAt != nil {
		t := time.Time(*in.FinishedAt)
		r.FinishedAt = &t
	}
	if in.Watched != nil {
		r.Watched = append([]core.EpisodeKey{}, *in.Watched...)
	}
	if in.NamedEpisodes != nil {
		r.NamedEpisodes = append([]NamedEpisode{}, *in.NamedEpisodes...)
	}
	return nil
}

// MARK: Small helpers for parsers and the plan

func ptr[T any](v T) *T { return &v }

func isTrue(b *bool) bool { return b != nil && *b }
