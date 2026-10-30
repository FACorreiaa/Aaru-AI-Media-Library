// Package core is AaruCore in Go: the models and rules the server shares with
// the clients (media types, statuses, external ids, ratings, progress, title
// matching). Raw values here are a wire contract; changing one breaks stored data.
package core

// MediaType is the kind of work a Title describes.
//
// This is catalog vocabulary, not library vocabulary. A user's relationship to a
// title is a LibraryItem.
type MediaType string

// The media types.
const (
	MediaMovie MediaType = "movie"
	MediaShow  MediaType = "show"
	MediaBook  MediaType = "book"
	// MediaAlbum is a music album or EP: one MusicBrainz release group (MUS-001). Status only, no progress.
	MediaAlbum MediaType = "album"
	// MediaManga is manga, manhwa, manhua and light novels: one AniList work of type MANGA (MNG-001).
	// Progress is a chapter and a volume.
	MediaManga MediaType = "manga"
)

// MediaTypes are every media type, in declaration order.
var MediaTypes = []MediaType{MediaMovie, MediaShow, MediaBook, MediaAlbum, MediaManga}

// Valid reports whether t is a known media type.
func (t MediaType) Valid() bool {
	switch t {
	case MediaMovie, MediaShow, MediaBook, MediaAlbum, MediaManga:
		return true
	}
	return false
}

// LibraryStatus is how far the user has got with a title.
//
// Consumption only. Ownership is LibraryItem.IsOwned — do not overload this type.
//
// on_hold is paused on purpose (LIB-007). It ranks with in_progress for imports, is
// left off Now, Up Next, Tonight and the week, and a live tick moves it back to
// in_progress. The UI label is "On hold" for every kind.
type LibraryStatus string

// The library statuses.
const (
	StatusWishlist   LibraryStatus = "wishlist"
	StatusInProgress LibraryStatus = "in_progress"
	StatusOnHold     LibraryStatus = "on_hold"
	StatusFinished   LibraryStatus = "finished"
	StatusDropped    LibraryStatus = "dropped"
)

// LibraryStatuses are every status, in declaration order.
var LibraryStatuses = []LibraryStatus{StatusWishlist, StatusInProgress, StatusOnHold, StatusFinished, StatusDropped}

// Valid reports whether s is a known status.
func (s LibraryStatus) Valid() bool {
	switch s {
	case StatusWishlist, StatusInProgress, StatusOnHold, StatusFinished, StatusDropped:
		return true
	}
	return false
}
