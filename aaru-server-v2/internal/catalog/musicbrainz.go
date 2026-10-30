package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"slices"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// MusicBrainzBaseURL is MusicBrainz's web service root.
const MusicBrainzBaseURL = "https://musicbrainz.org/ws/2"

// MusicBrainzTrackedTypes are the types Aaru tracks: albums and EPs, not singles,
// broadcasts or compilations of others.
var MusicBrainzTrackedTypes = map[string]bool{"Album": true, "EP": true}

// TrackLister lists an album's tracks.
type TrackLister interface {
	// Tracks is the tracklist for an album it can identify from ids; nil when it cannot.
	Tracks(ctx context.Context, ids core.ExternalIDs) ([]AlbumTrack, error)
}

// MusicArtist is a music artist by MusicBrainz id, as an album credits them.
type MusicArtist struct {
	MusicBrainzID string
	Name          string
}

// AlbumArtistLister is an album's credited artists by MusicBrainz id (MUS-003).
type AlbumArtistLister interface {
	// Artists is nil when the provider does not know the release group.
	Artists(ctx context.Context, releaseGroup string) ([]MusicArtist, error)
}

// MusicBrainz is the MusicBrainz adapter (MUS-001): albums and EPs as release groups,
// the artist credit, genres, and a tracklist from the release group's earliest
// official release; album artists for concerts (MUS-003) and recording matching for
// listens (MUS-006). Covers are Cover Art Archive URLs, referenced, never
// downloaded. MusicBrainz allows one request a second and asks every client to
// identify itself.
type MusicBrainz struct {
	Client    *provider.Client
	UserAgent string
	// BaseURL defaults to MusicBrainzBaseURL.
	BaseURL string
}

// MusicBrainzCoverURL is the release group's front cover on the Cover Art Archive.
func MusicBrainzCoverURL(releaseGroup string) *string {
	return strPtr("https://coverartarchive.org/release-group/" + releaseGroup + "/front-250")
}

// Search finds albums and EPs whose title or artist matches the user's words.
func (m *MusicBrainz) Search(ctx context.Context, query string, _ core.MediaType) ([]Hit, error) {
	// Lucene syntax: the user's words match the album or its artist; their punctuation
	// is escaped so it is never query syntax.
	terms := LuceneEscaped(query)
	lucene := "(releasegroup:(" + terms + ") OR artist:(" + terms + ")) AND (primarytype:album OR primarytype:ep)"
	var page struct {
		ReleaseGroups []mbReleaseGroup `json:"release-groups"`
	}
	if err := m.get(ctx, "release-group", map[string]string{"query": lucene, "limit": "25"}, &page); err != nil {
		return nil, err
	}
	hits := []Hit{}
	for _, g := range page.ReleaseGroups {
		if g.isTracked() {
			hits = append(hits, g.hit())
		}
	}
	return hits, nil
}

// LuceneEscaped escapes Lucene's special characters with a backslash.
func LuceneEscaped(text string) string {
	const special = `+-&|!(){}[]^"~*?:\/`
	var b strings.Builder
	for _, r := range text {
		if strings.ContainsRune(special, r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String()
}

// Hydrate is the album record for a release-group id, with its five most-tagged genres.
func (m *MusicBrainz) Hydrate(ctx context.Context, ids core.ExternalIDs, _ core.MediaType) (*Record, error) {
	if ids.MusicBrainz == "" {
		return nil, nil //nolint:nilnil // nil: no release-group id
	}
	var group mbReleaseGroup
	err := m.get(ctx, "release-group/"+ids.MusicBrainz, map[string]string{"inc": "artist-credits+genres"}, &group)
	if provider.IsNotFound(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, err
	}
	hit := group.hit()
	hit.IDs = hit.IDs.Filling(ids)
	genres := slices.Clone(group.Genres)
	slices.SortStableFunc(genres, func(a, b mbGenre) int { return b.Count - a.Count })
	names := []string{}
	for _, g := range genres[:min(5, len(genres))] {
		names = append(names, g.Name)
	}
	return &Record{Hit: hit, Genres: names}, nil
}

// Artists are the album's credited artists, for matching concerts by MusicBrainz id
// (MUS-003). Nil when MusicBrainz does not know the release group.
func (m *MusicBrainz) Artists(ctx context.Context, releaseGroup string) ([]MusicArtist, error) {
	var group mbReleaseGroup
	err := m.get(ctx, "release-group/"+releaseGroup, map[string]string{"inc": "artist-credits"}, &group)
	if provider.IsNotFound(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	artists := []MusicArtist{}
	for _, c := range group.ArtistCredit {
		if c.Artist == nil || seen[c.Artist.ID] {
			continue
		}
		seen[c.Artist.ID] = true
		artists = append(artists, MusicArtist{MusicBrainzID: strings.ToLower(c.Artist.ID), Name: c.Artist.Name})
	}
	return artists, nil
}

// Tracks is the tracklist of the release group's earliest dated official release;
// undated releases come last. Nil without a release-group id.
func (m *MusicBrainz) Tracks(ctx context.Context, ids core.ExternalIDs) ([]AlbumTrack, error) {
	if ids.MusicBrainz == "" {
		return nil, nil //nolint:nilnil // nil: not known
	}
	var page struct {
		Releases []struct {
			Date  *string `json:"date"`
			Media []struct {
				Position *int `json:"position"`
				Tracks   []struct {
					Position *int   `json:"position"`
					Title    string `json:"title"`
					Length   *int   `json:"length"`
				} `json:"tracks"`
			} `json:"media"`
		} `json:"releases"`
	}
	err := m.get(ctx, "release", map[string]string{
		"release-group": ids.MusicBrainz, "status": "official", "inc": "recordings", "limit": "25",
	}, &page)
	if err != nil {
		return nil, err
	}
	if len(page.Releases) == 0 {
		return []AlbumTrack{}, nil
	}
	date := func(d *string) string { return cmp.Or(sval(d), "9999") }
	earliest := 0
	for i, r := range page.Releases {
		if date(r.Date) < date(page.Releases[earliest].Date) {
			earliest = i
		}
	}
	tracks := []AlbumTrack{}
	for mi, medium := range page.Releases[earliest].Media {
		disc := mi + 1
		if medium.Position != nil {
			disc = *medium.Position
		}
		for ti, t := range medium.Tracks {
			position := ti + 1
			if t.Position != nil {
				position = *t.Position
			}
			tracks = append(tracks, AlbumTrack{Disc: disc, Position: position, Name: t.Title, LengthMs: t.Length})
		}
	}
	return tracks, nil
}

func (m *MusicBrainz) get(ctx context.Context, path string, query map[string]string, v any) error {
	headers := [][2]string{{"User-Agent", cmp.Or(m.UserAgent, config.DefaultProviderUserAgent)}, {"Accept", "application/json"}}
	return getJSON(ctx, m.Client, buildURL(cmp.Or(m.BaseURL, MusicBrainzBaseURL), path, query, [2]string{"fmt", "json"}), headers, v)
}

// MARK: - Recordings (MUS-006)

// RecordingQuery is one scrobbled track to identify: its spelling, plus any ids the
// scrobbler sent.
type RecordingQuery struct {
	Artist        string
	Track         string
	Album         *string
	RecordingMBID *string
	ISRC          *string
}

// RecordingMatch is what MusicBrainz identified. A field is nil whenever the answer
// was not one exact thing.
type RecordingMatch struct {
	RecordingMBID    *string
	ReleaseGroupMBID *string
	ArtistMBID       *string
}

// RecordingMatcher identifies a scrobbled track.
type RecordingMatcher interface {
	Match(ctx context.Context, query RecordingQuery) (RecordingMatch, error)
}

// Match is MUS-006: one recording search per track, through the catalog's own
// paced client so listens and album search share MusicBrainz's one request a
// second. The search asks by the recording id the scrobbler sent, else its ISRC,
// else the exact artist and title.
func (m *MusicBrainz) Match(ctx context.Context, query RecordingQuery) (RecordingMatch, error) {
	var lucene string
	switch {
	case query.RecordingMBID != nil:
		lucene = "rid:" + *query.RecordingMBID
	case query.ISRC != nil:
		lucene = "isrc:" + LuceneEscaped(*query.ISRC)
	default:
		lucene = `recording:"` + LuceneEscaped(query.Track) + `" AND artist:"` + LuceneEscaped(query.Artist) + `"`
	}
	var page struct {
		Recordings []MusicBrainzRecording `json:"recordings"`
	}
	if err := m.get(ctx, "recording", map[string]string{"query": lucene, "limit": "25"}, &page); err != nil {
		return RecordingMatch{}, err
	}
	return MatchRecording(query, page.Recordings), nil
}

// FoldName is case-, width- and space-folded, so two spellings of one name compare
// equal (the listens' fold).
func FoldName(text string) string {
	return strings.Join(strings.FieldsFunc(strings.ToLower(norm.NFKC.String(text)), unicode.IsSpace), " ")
}

// MatchRecording guesses nothing. A recording counts when it is the id the scrobbler
// sent, or when its title and artist are the listen's, folded, at a search score of
// 100. The album is the one whose title is the listen's album; with no album sent,
// it is the only album or EP the matching recordings appear on.
func MatchRecording(query RecordingQuery, recordings []MusicBrainzRecording) RecordingMatch {
	title, artist := FoldName(query.Track), FoldName(query.Artist)
	var exact []MusicBrainzRecording
	for _, r := range recordings {
		if query.RecordingMBID != nil && r.ID == *query.RecordingMBID {
			exact = append(exact, r)
			continue
		}
		firstCredit := ""
		if len(r.ArtistCredit) > 0 {
			firstCredit = r.ArtistCredit[0].Name
		}
		if r.Score != nil && *r.Score == 100 && FoldName(r.Title) == title &&
			(FoldName(r.Byline()) == artist || FoldName(firstCredit) == artist) {
			exact = append(exact, r)
		}
	}
	var groups, ids, artists []string
	for _, r := range exact {
		ids = append(ids, r.ID)
		if len(r.ArtistCredit) > 0 && r.ArtistCredit[0].Artist != nil {
			artists = append(artists, r.ArtistCredit[0].Artist.ID)
		}
		for _, release := range r.Releases {
			g := release.ReleaseGroup
			if g == nil {
				continue
			}
			var fits bool
			if query.Album != nil {
				album := FoldName(*query.Album)
				fits = FoldName(sval(g.Title)) == album || FoldName(release.Title) == album
			} else {
				fits = MusicBrainzTrackedTypes[sval(g.PrimaryType)]
			}
			if fits {
				groups = append(groups, g.ID)
			}
		}
	}
	return RecordingMatch{RecordingMBID: only(ids), ReleaseGroupMBID: only(groups), ArtistMBID: only(artists)}
}

// only is the value when every one is the same, else nil.
func only(values []string) *string {
	if len(values) == 0 {
		return nil
	}
	for _, v := range values[1:] {
		if v != values[0] {
			return nil
		}
	}
	return &values[0]
}

// MusicBrainzRecording is one recording search result.
type MusicBrainzRecording struct {
	ID           string              `json:"id"`
	Score        *int                `json:"score"`
	Title        string              `json:"title"`
	ArtistCredit []MusicBrainzCredit `json:"artist-credit"`
	Releases     []struct {
		Title        string `json:"title"`
		ReleaseGroup *struct {
			ID          string  `json:"id"`
			Title       *string `json:"title"`
			PrimaryType *string `json:"primary-type"`
		} `json:"release-group"`
	} `json:"releases"`
}

// Byline is the credit as MusicBrainz joins it: "Simon & Garfunkel".
func (r MusicBrainzRecording) Byline() string {
	var b strings.Builder
	for _, c := range r.ArtistCredit {
		b.WriteString(c.Name + sval(c.JoinPhrase))
	}
	return b.String()
}

// MusicBrainzCredit is one name in an artist credit.
type MusicBrainzCredit struct {
	Name       string  `json:"name"`
	JoinPhrase *string `json:"joinphrase"`
	Artist     *struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	} `json:"artist"`
}

// MARK: - MusicBrainz wire shapes

type mbGenre struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

type mbReleaseGroup struct {
	ID               string              `json:"id"`
	Title            string              `json:"title"`
	PrimaryType      *string             `json:"primary-type"`
	FirstReleaseDate *string             `json:"first-release-date"`
	ArtistCredit     []MusicBrainzCredit `json:"artist-credit"`
	Genres           []mbGenre           `json:"genres"`
}

func (g mbReleaseGroup) isTracked() bool { return MusicBrainzTrackedTypes[sval(g.PrimaryType)] }

// byline is "Simon & Garfunkel", "Jay-Z feat. Alicia Keys": the credit as MusicBrainz joins it.
func (g mbReleaseGroup) byline() *string {
	if len(g.ArtistCredit) == 0 {
		return nil
	}
	var b strings.Builder
	for _, c := range g.ArtistCredit {
		b.WriteString(c.Name + sval(c.JoinPhrase))
	}
	return strPtr(b.String())
}

func (g mbReleaseGroup) hit() Hit {
	return Hit{
		Type: core.MediaAlbum, Title: g.Title, Year: ParseYear(g.FirstReleaseDate),
		PosterURL: MusicBrainzCoverURL(g.ID), Byline: g.byline(), IDs: core.ExternalIDs{MusicBrainz: g.ID},
		ReleaseDate: ParseDate(g.FirstReleaseDate),
	}
}
