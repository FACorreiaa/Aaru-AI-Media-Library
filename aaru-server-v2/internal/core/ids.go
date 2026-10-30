package core

// ExternalIDs are the provider identifiers Aaru knows for a title. An empty
// string means unknown.
//
// Every saved title stores whichever of these are known. They are the primary
// matching key during import — normalized title + year is only the fallback.
//
// TMDB and Trakt number movies and shows separately, so a `tmdb` or `trakt` match
// only means "same work" between titles of the same MediaType.
type ExternalIDs struct {
	TMDB        string `json:"tmdb,omitempty"`
	IMDB        string `json:"imdb,omitempty"`
	Trakt       string `json:"trakt,omitempty"`
	TVDB        string `json:"tvdb,omitempty"`
	ISBN        string `json:"isbn,omitempty"`
	OpenLibrary string `json:"openLibrary,omitempty"`
	AniList     string `json:"anilist,omitempty"`
	MAL         string `json:"mal,omitempty"`
	AniDB       string `json:"anidb,omitempty"`
	// MusicBrainz is the release-group MBID, for albums.
	MusicBrainz string `json:"musicbrainz,omitempty"`
}

// KnownID is one identifier that is set: its provider's field name and value.
type KnownID struct {
	Provider string
	Value    string
}

// IDProviders are the provider field names, in ExternalIDs order.
var IDProviders = []string{"tmdb", "imdb", "trakt", "tvdb", "isbn", "openLibrary", "anilist", "mal", "anidb", "musicbrainz"}

func (ids *ExternalIDs) fields() []*string {
	return []*string{
		&ids.TMDB, &ids.IMDB, &ids.Trakt, &ids.TVDB, &ids.ISBN,
		&ids.OpenLibrary, &ids.AniList, &ids.MAL, &ids.AniDB, &ids.MusicBrainz,
	}
}

// IsEmpty is true when no provider identifier is known.
func (ids ExternalIDs) IsEmpty() bool {
	for _, f := range ids.fields() {
		if *f != "" {
			return false
		}
	}
	return true
}

// Known is every identifier that is set, in field order.
func (ids ExternalIDs) Known() []KnownID {
	var out []KnownID
	for i, f := range ids.fields() {
		if *f != "" {
			out = append(out, KnownID{Provider: IDProviders[i], Value: *f})
		}
	}
	return out
}

// Matches is true when both sides agree on at least one provider identifier.
//
// Two titles that share no identifier must never be merged on name alone. Callers
// comparing titles must also require the same MediaType (see CanMerge).
func (ids ExternalIDs) Matches(other ExternalIDs) bool {
	mine, theirs := ids.fields(), other.fields()
	for i := range mine {
		if *mine[i] != "" && *mine[i] == *theirs[i] {
			return true
		}
	}
	return false
}

// Filling copies identifiers from other into fields that are still empty.
//
// Fill-empty-only: a later import source never overwrites an identifier an
// earlier source already established.
func (ids ExternalIDs) Filling(other ExternalIDs) ExternalIDs {
	result := ids
	mine, theirs := result.fields(), other.fields()
	for i := range mine {
		if *mine[i] == "" {
			*mine[i] = *theirs[i]
		}
	}
	return result
}
