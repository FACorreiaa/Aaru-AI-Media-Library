package catalog

import "aaru-go-api/internal/core"

// The adult rule (CAT-023, owner 2026-11-13): Aaru's catalog never offers adult works. The App
// Store age rating answers "Graphic sexual content: none", and that has to be true of everything
// a search, a Discover row, a relation graph, a title tree or an import can put in front of
// someone.
//
// A provider's own mark decides, never a guess from a title or a genre: AniList's `isAdult`,
// TMDB's `adult`, MyAnimeList's `nsfw: black` (internal/mal). Open Library and MusicBrainz have
// no such mark, so nothing is filtered there.
//
// Each provider keeps its half in one place:
//   - AniList: every list query asks with aniListNoAdult, every entry is read with `isAdult`
//     (aniListMediaFields, aniListRelationFields), and aniListOffered drops what still comes back.
//   - TMDB: every list request starts from tmdbNoAdult (the endpoints that take `include_adult`
//     honour it, the rest ignore it), and tmdbDetail.offered drops an entry marked `adult`.
//
// A read by id (Hydrate) still answers for an adult work, with Hit.Adult set: a title already in
// someone's library keeps refreshing. Resolver.resolveIDs is the one door a new `titles` row
// comes through, and it refuses a record so marked with ErrAdult, which an import reports as an
// unmatched row with AdultReason. Nothing already stored is removed.

// AdultReason is what an import row says when its title is an adult work.
const AdultReason = "Adult titles are not in Aaru's catalog."

// aniListNoAdult is the filter every AniList list query carries.
const aniListNoAdult = "isAdult: false"

// aniListOffered is the entries Aaru may show: AniList's adult works are left out, whatever the
// query asked for.
func aniListOffered(media []aniListMedia) []aniListMedia {
	offered := make([]aniListMedia, 0, len(media))
	for _, m := range media {
		if !m.IsAdult {
			offered = append(offered, m)
		}
	}
	return offered
}

// tmdbNoAdult starts the query of every TMDB list request. Search and discover take
// `include_adult`; trending, now playing and on the air do not, and are filtered by
// tmdbDetail.offered alone.
func tmdbNoAdult() map[string]string {
	return map[string]string{"include_adult": "false"}
}

// isAdult is TMDB's own mark on a film or show.
func (d tmdbDetail) isAdult() bool { return d.Adult != nil && *d.Adult }

// offered is the entry as a hit for a list (search, a row, a collection, a person's works): an
// adult title is no hit at all.
func (d tmdbDetail) offered(mediaType core.MediaType) (Hit, bool) {
	if d.isAdult() {
		return Hit{}, false
	}
	return d.hit(mediaType)
}
