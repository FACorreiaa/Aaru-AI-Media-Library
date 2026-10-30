// Package music is the listening log (MUS-004…008, SCR-011): listens scrobblers send through the
// ListenBrainz submit protocol, the extension's YouTube music videos, and listening-history imports.
// A listen never touches the library. It is the port of Sources/App/Music (ListenTypes,
// ListenSubmission, ListenService, ListenResolver) and PostgresListenStore(+Imports).swift.
//
// Other areas call: Service.Submit (scrobbles, SCR-011), Store.Stage/ClearStaged/CountNew/
// ApplyStaged/DeleteImported/NewestImported (MUS-004 imports: stage a job's plays, apply them as
// the job's `import` listens, undo by job), ParseHistoryPage (ListenBrainz history pages), and
// Service.All (the account export).
package music

import (
	"aaru-go-api/internal/catalog"
	"net/url"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
	"golang.org/x/text/unicode/norm"
)

// NewListen is one play of a track as a scrobbler reported it, before it is stored.
type NewListen struct {
	ListenedAt       time.Time
	Artist           string
	Track            string
	Album            *string
	DurationMs       *int
	ISRC             *string
	RecordingMBID    *string
	ReleaseMBID      *string
	ReleaseGroupMBID *string
	ArtistMBID       *string
	SpotifyID        *string
	OriginURL        *string
	// Client is the scrobbler ("Web Scrobbler"); MusicService the service it heard ("YouTube Music").
	Client       *string
	MusicService *string
}

// TrackKey is the folded artist and track: what makes two scrobblers' spellings of one play the same.
func (l NewListen) TrackKey() string { return TrackKey(l.Artist, l.Track) }

// DuplicateWindow is how close two listens of the same track are one play sent twice, by one
// scrobbler retrying or by two scrobblers on the same play: half the track, at most 90 s; 30 s when
// the length is unknown.
func (l NewListen) DuplicateWindow() time.Duration {
	if l.DurationMs == nil {
		return 30 * time.Second
	}
	return seconds(min(90, float64(*l.DurationMs)/2000))
}

// YouTubeVideoID is the YouTube video a listen was heard on, from its origin URL (SCR-011).
func (l NewListen) YouTubeVideoID() *string {
	if l.OriginURL == nil {
		return nil
	}
	return YouTubeVideoID(*l.OriginURL)
}

// VideoWindow is how close two listens of the same YouTube video are one play, whatever their
// spellings: the extension's and a music scrobbler's (SCR-011). The video's length; 30 s when unknown.
func (l NewListen) VideoWindow() time.Duration {
	if l.DurationMs == nil {
		return 30 * time.Second
	}
	return seconds(float64(*l.DurationMs) / 1000)
}

func seconds(s float64) time.Duration { return time.Duration(s * float64(time.Second)) }

// Listen is one stored listen.
type Listen struct {
	ID               uuid.UUID
	ListenedAt       time.Time
	Artist           string
	Track            string
	Album            *string
	DurationMs       *int
	ReleaseGroupMBID *string
	// AlbumTitleID is the album's title when it is in Aaru's catalog (MUS-006).
	AlbumTitleID *uuid.UUID
	OriginURL    *string
	Client       *string
	MusicService *string
}

// TrackKey is the artist and track, case-, width- and space-folded, joined by a unit separator.
func TrackKey(artist, track string) string {
	return Fold(artist) + "\u001F" + Fold(track)
}

// Fold is case-, width- and space-folded, so two spellings of one name compare equal (Listen.fold):
// NFKC, lowercased, whitespace runs joined by one space. Swift's lowercased() maps each scalar fully
// and without context: per rune here, with U+0130's two-scalar mapping, so the keys match the rows
// Swift stored. Greek final sigma is not special-cased, as in Swift.
func Fold(text string) string {
	composed := norm.NFKC.String(text)
	var b strings.Builder
	b.Grow(len(composed))
	for _, r := range composed {
		if r == '\u0130' {
			b.WriteString("i\u0307")
			continue
		}
		b.WriteRune(unicode.ToLower(r))
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// YouTubeVideoPattern finds a video id in a YouTube URL, here and in SQL.
const YouTubeVideoPattern = `(?:[?&]v=|youtu\.be/)([A-Za-z0-9_-]{11})`

// YouTubeVideoID is a YouTube watch link's video id: `youtube.com/watch?v=…`,
// `music.youtube.com/watch?v=…` or `youtu.be/…`. Nil for any other link.
func YouTubeVideoID(raw string) *string {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return nil
	}
	host := strings.ToLower(u.Hostname())
	id := ""
	switch {
	case host == "youtu.be":
		id = strings.TrimPrefix(u.Path, "/")
	case (host == "youtube.com" || strings.HasSuffix(host, ".youtube.com")) && u.Path == "/watch":
		id = u.Query().Get("v")
	}
	if !IsYouTubeID(id) {
		return nil
	}
	return &id
}

// IsYouTubeID is YouTube's 11-character video id: ASCII letters, digits, `-` and `_`.
func IsYouTubeID(id string) bool {
	if len(id) != 11 {
		return false
	}
	for _, r := range id {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' && r != '_' {
			return false
		}
	}
	return true
}

// Lookup is MUS-006: one track no one has asked MusicBrainz about yet: its keys, and the newest
// listen's spelling with any ids a scrobbler sent.
type Lookup struct {
	TrackKey string
	// AlbumKey is the album, lowercased; empty when the scrobbler sent none.
	AlbumKey string
	Query    catalog.RecordingQuery
}

// Grouping is what the top lists rank by.
type Grouping string

// The groupings.
const (
	ByArtist Grouping = "artist"
	ByTrack  Grouping = "track"
	ByAlbum  Grouping = "album"
)

// Total is one row of a top list: an artist, a track (with its artist) or an album (with its artist).
type Total struct {
	Artist     string
	Track      *string
	Album      *string
	Count      int
	DurationMs int64
	// ReleaseGroupMBID is the newest identified album among the row's listens: its cover, and its
	// link once the album is in the catalog (MUS-008).
	ReleaseGroupMBID *string
	AlbumTitleID     *uuid.UUID
}

// Top is a period's top list and the period's totals.
type Top struct {
	Listens    int
	DurationMs int64
	Items      []Total
}

// maxText is what a listen's text columns accept.
const maxText = 500

// Text is trimmed, at most 500 characters, nil when empty.
func Text(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	trimmed = prefix(trimmed, maxText)
	return &trimmed
}

// prefix is the first n characters of s.
func prefix(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	i := 0
	for pos := range s {
		if i == n {
			return s[:pos]
		}
		i++
	}
	return s
}

// MBID keeps a MusicBrainz id (a UUID), lowercased; anything else is dropped rather than stored.
func MBID(value *string) *string {
	if value == nil || len(*value) != 36 {
		return nil
	}
	id, err := uuid.Parse(*value)
	if err != nil {
		return nil
	}
	s := id.String()
	return &s
}
