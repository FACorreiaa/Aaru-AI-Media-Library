package core

import (
	"strings"

	"github.com/google/uuid"
)

// Years Aaru accepts. Wide enough for early cinema and for announced titles.
const (
	MinYear = 1870
	MaxYear = 2200
)

// ValidYear reports whether year is inside MinYear…MaxYear.
func ValidYear(year int) bool { return year >= MinYear && year <= MaxYear }

// Title is a canonical work Aaru knows about: one movie, show, book, album, or manga.
//
// Titles are shared across users. Ratings, status, notes, and progress belong on
// LibraryItem and must never appear here.
type Title struct {
	ID            uuid.UUID
	Type          MediaType
	Title         string
	OriginalTitle *string
	Year          *int
	Synopsis      *string
	// PosterURL is a catalog URL. Aaru does not host provider artwork.
	PosterURL *string
	// BackdropURL is wide art (TMDB backdrop, AniList banner): the week grid's cell banner.
	BackdropURL *string
	// Network is the network or streaming service, for shows: "HBO", "Netflix", "Crunchyroll".
	Network *string
	// Byline is who made it, as the catalog credits them: an album's artist.
	Byline *string
	// PageCount is a book's length in pages (Open Library's median across editions).
	PageCount *int
	// ChapterCount and VolumeCount are a manga's length as AniList knows it: nil while running.
	ChapterCount *int
	VolumeCount  *int
	IDs          ExternalIDs
	// IsAnime is a facet on movie/show, not a media type: an anime series shares show
	// progress, calendar, Up Next, and widgets with every other show.
	IsAnime bool
	// Seasons is shows only. nil means "not loaded yet", empty means "loaded, none known".
	Seasons []Season
}

// MatchKey is the key used when no external id matches on either side.
func (t Title) MatchKey() MatchKey {
	return NewMatchKey(t.Title, t.Year, t.Type)
}

// Validate rejects a blank name or an impossible year.
func (t Title) Validate() error {
	if strings.TrimSpace(t.Title) == "" {
		return &ValidationError{Kind: EmptyTitle}
	}
	if t.Year != nil && !ValidYear(*t.Year) {
		return &ValidationError{Kind: InvalidYear, Year: *t.Year}
	}
	return nil
}

// MediaRef is a pointer to a title that may not exist in Aaru yet.
//
// This is what a client sends to add something to the library, and what an
// importer produces for each source row. The server resolves it to a Title
// (find or hydrate) before creating a library item.
type MediaRef struct {
	// TitleID is set when the caller already knows Aaru's title.
	TitleID *uuid.UUID
	Type    MediaType
	IDs     ExternalIDs
	Title   *string
	Year    *int
}

// MatchKey is the fallback key; false when no name is known — a ref with only a
// type is not matchable.
func (r MediaRef) MatchKey() (MatchKey, bool) {
	if r.Title == nil {
		return MatchKey{}, false
	}
	return NewMatchKey(*r.Title, r.Year, r.Type), true
}

// IsResolvable is true when the server has something to resolve against.
func (r MediaRef) IsResolvable() bool {
	if r.TitleID != nil || !r.IDs.IsEmpty() {
		return true
	}
	if r.Title == nil {
		return false
	}
	return strings.TrimSpace(*r.Title) != "" && r.Year != nil
}

// Validate rejects a ref with nothing to resolve against or an impossible year.
func (r MediaRef) Validate() error {
	if !r.IsResolvable() {
		return &ValidationError{Kind: UnresolvableMediaRef}
	}
	if r.Year != nil && !ValidYear(*r.Year) {
		return &ValidationError{Kind: InvalidYear, Year: *r.Year}
	}
	return nil
}
