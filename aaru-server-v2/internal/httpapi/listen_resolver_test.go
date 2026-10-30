package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/music"
	"context"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ListenResolverTests.swift (MUS-006) against Postgres, and the top-row parts of ListenStatsTests.swift
// (MUS-008). The lookup cache is shared by every user, so each test's artists are unique.

// fakeRecordings answers per artist and counts what it was asked.
type fakeRecordings struct {
	mu      sync.Mutex
	answers map[string]catalog.RecordingMatch
	asked   []catalog.RecordingQuery
}

func newFakeRecordings() *fakeRecordings {
	return &fakeRecordings{answers: map[string]catalog.RecordingMatch{}}
}

func (f *fakeRecordings) answer(artist string, m catalog.RecordingMatch) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.answers[artist] = m
}

func (f *fakeRecordings) queries(artist string) []catalog.RecordingQuery {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []catalog.RecordingQuery
	for _, q := range f.asked {
		if q.Artist == artist {
			out = append(out, q)
		}
	}
	return out
}

func (f *fakeRecordings) Match(_ context.Context, q catalog.RecordingQuery) (catalog.RecordingMatch, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.asked = append(f.asked, q)
	return f.answers[q.Artist], nil
}

func resolverListen(artist, track string, album *string, minutesAgo float64) music.NewListen {
	return music.NewListen{
		ListenedAt: time.Now().Add(-time.Duration(minutesAgo * float64(time.Minute))), Artist: artist, Track: track,
		Album: album, Client: ptr("Web Scrobbler"),
	}
}

func (e *libEnv) insertListens(listens ...music.NewListen) {
	e.t.Helper()
	_, err := e.server.Listens.Store.Insert(context.Background(), listens, e.user, nil)
	require.NoError(e.t, err)
}

func (e *libEnv) resolver(recordings catalog.RecordingMatcher) *music.Resolver {
	return &music.Resolver{Store: e.server.Listens.Store, Recordings: recordings, PassLimit: 1000}
}

func runOnce(t *testing.T, r *music.Resolver) (tracks, listens int) {
	t.Helper()
	tracks, listens, err := r.RunOnce(context.Background())
	require.NoError(t, err)
	return tracks, listens
}

func TestListenResolverAsksEachTrackOnceAndItsListensGainTheAlbum(t *testing.T) {
	env := newLibEnv(t)
	artist := env.fake.uniqueID("Radiohead")
	recordings := newFakeRecordings()
	recordings.answer(artist, catalog.RecordingMatch{RecordingMBID: ptr("r-1"), ReleaseGroupMBID: ptr("rg-ok"), ArtistMBID: ptr("a-1")})
	env.insertListens(
		resolverListen(artist, "Airbag", ptr("OK Computer"), 30),
		resolverListen(artist, "airbag", ptr("ok computer"), 20),
		resolverListen(artist, "Airbag", ptr("OK Computer"), 10),
	)
	resolver := env.resolver(recordings)

	_, listens := runOnce(t, resolver)
	assert.GreaterOrEqual(t, listens, 3)
	asked := recordings.queries(artist)
	require.Len(t, asked, 1, "three spellings of one track and album")
	assert.Equal(t, "OK Computer", *asked[0].Album, "the newest listen's spelling")
	items := env.listenLog()
	require.Len(t, items, 3)
	for _, item := range items {
		assert.Equal(t, "https://coverartarchive.org/release-group/rg-ok/front-250", item["coverUrl"])
		ref := item["albumRef"].(map[string]any)
		assert.Equal(t, "rg-ok", ref["ids"].(map[string]any)["musicbrainz"])
		assert.NotContains(t, ref, "titleId", "the album is not in the catalog yet")
	}

	runOnce(t, resolver)
	assert.Len(t, recordings.queries(artist), 1, "a found track is not asked again")

	// A later play of the same track takes the ids as it is stored.
	env.insertListens(resolverListen(artist, "Airbag", ptr("OK Computer"), 1))
	assert.Contains(t, env.listenLog()[0], "coverUrl")
	runOnce(t, resolver)
	assert.Len(t, recordings.queries(artist), 1)
}

func TestListenResolverKeepsAMissForAMonthAndNeverOverwritesSentIDs(t *testing.T) {
	env := newLibEnv(t)
	unknown := env.fake.uniqueID("Nobody")
	sent := env.fake.uniqueID("Portishead")
	recordings := newFakeRecordings()
	recordings.answer(sent, catalog.RecordingMatch{RecordingMBID: ptr("r-x"), ReleaseGroupMBID: ptr("rg-x"), ArtistMBID: ptr("a-x")})
	withIDs := resolverListen(sent, "Roads", ptr("Dummy"), 5)
	withIDs.ReleaseGroupMBID = ptr("rg-dummy")
	env.insertListens(resolverListen(unknown, "Demo", nil, 5), withIDs)
	now := time.Now()
	resolver := env.resolver(recordings)
	resolver.Now = func() time.Time { return now }

	runOnce(t, resolver)
	runOnce(t, resolver)
	assert.Len(t, recordings.queries(unknown), 1, "a miss is remembered")
	assert.Empty(t, recordings.queries(sent), "a listen that came with its album is not looked up")

	resolver.Now = func() time.Time { return now.Add(music.RetryAfter + time.Minute) }
	runOnce(t, resolver)
	assert.Len(t, recordings.queries(unknown), 2, "asked again after a month")

	var roads, demo map[string]any
	for _, it := range env.listenLog() {
		switch it["track"] {
		case "Roads":
			roads = it
		case "Demo":
			demo = it
		}
	}
	require.NotNil(t, roads)
	require.NotNil(t, demo)
	assert.Equal(t, "https://coverartarchive.org/release-group/rg-dummy/front-250", roads["coverUrl"])
	assert.NotContains(t, demo, "albumRef")
}

func TestListenResolverLinksAnAlbumAlreadyInTheCatalogByItsAaruID(t *testing.T) {
	env := newLibEnv(t)
	artist := env.fake.uniqueID("Massive Attack")
	mbid := env.fake.uniqueID("rg")
	year := 1998
	env.fake.stubTitle(catalog.Record{Hit: catalog.Hit{
		Type: core.MediaAlbum, Title: "Mezzanine", Year: &year, PosterURL: catalog.MusicBrainzCoverURL(mbid),
		Byline: &artist, IDs: core.ExternalIDs{MusicBrainz: mbid},
	}})
	added := env.json(http.MethodPost, "/v1/library/items", map[string]any{
		"mediaRef": map[string]any{"type": "album", "ids": map[string]any{"musicbrainz": mbid}},
	})
	titleID := added["title"].(map[string]any)["id"].(string)

	recordings := newFakeRecordings()
	recordings.answer(artist, catalog.RecordingMatch{ReleaseGroupMBID: &mbid})
	env.insertListens(resolverListen(artist, "Teardrop", ptr("Mezzanine"), 3))
	runOnce(t, env.resolver(recordings))

	items := env.listenLog()
	require.NotEmpty(t, items)
	ref := items[0]["albumRef"].(map[string]any)
	assert.Equal(t, titleID, ref["titleId"])
	assert.Equal(t, "album", ref["type"])
	assert.Equal(t, "Mezzanine", ref["title"])
}

func statsListen(artist, track string, daysAgo float64, album, cover *string) music.NewListen {
	return music.NewListen{
		ListenedAt: time.Now().Add(-time.Duration(daysAgo*24*float64(time.Hour)) - time.Hour), Artist: artist, Track: track,
		Album: album, DurationMs: ptr(240_000), ReleaseGroupMBID: cover,
	}
}

func TestListensTopRowsCarryCoversLinkAlbumsAndNarrowToOneArtist(t *testing.T) {
	env := newLibEnv(t)
	env.insertListens(
		statsListen("Massive Attack", "Teardrop", 1, ptr("Mezzanine"), ptr("rg-mez")),
		statsListen("Massive Attack", "Angel", 1, ptr("Mezzanine"), nil),
		statsListen("Burial", "Archangel", 1, ptr("Untrue"), nil),
	)
	find := func(items []any, field, value string) map[string]any {
		for _, it := range items {
			if m := it.(map[string]any); m[field] == value {
				return m
			}
		}
		return nil
	}
	artists := env.json(http.MethodGet, "/v1/me/listens/top?by=artist&span=last7", nil)["items"].([]any)
	massive := find(artists, "artist", "Massive Attack")
	require.NotNil(t, massive)
	assert.Equal(t, "https://coverartarchive.org/release-group/rg-mez/front-250", massive["coverUrl"])
	assert.NotContains(t, massive, "albumRef")
	assert.NotContains(t, find(artists, "artist", "Burial"), "coverUrl")

	albums := env.json(http.MethodGet, "/v1/me/listens/top?by=album&span=last7", nil)["items"].([]any)
	mezzanine := find(albums, "album", "Mezzanine")
	require.NotNil(t, mezzanine)
	ref := mezzanine["albumRef"].(map[string]any)
	assert.Equal(t, "rg-mez", ref["ids"].(map[string]any)["musicbrainz"])
	assert.Equal(t, "album", ref["type"])

	narrowed := env.json(http.MethodGet, "/v1/me/listens/top?by=track&span=last7&artist=massive%20%20ATTACK", nil)["items"].([]any)
	var tracks []string
	for _, it := range narrowed {
		tracks = append(tracks, it.(map[string]any)["track"].(string))
	}
	assert.ElementsMatch(t, []string{"Teardrop", "Angel"}, tracks)
}
