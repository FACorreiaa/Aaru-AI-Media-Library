package catalog

import (
	"context"
	"fmt"
	"math/rand/v2"
	"strconv"
	"testing"

	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fribbFixture: a mapped TV cour, a film (TMDB movie id, as a list), a row with no
// AniList id, and a TV entry whose TMDB id is a list.
func fribbFixture(anilist [3]string, tmdb, mal, anidb, tvdb string) []byte {
	return fmt.Appendf(nil, `[
	  {"type":"TV","anilist_id":%s,"mal_id":%s,"anidb_id":%s,"tvdb_id":%s,
	   "themoviedb_id":{"tv":%s},"season":{"tvdb":2,"tmdb":2}},
	  {"type":"MOVIE","anilist_id":%s,"mal_id":291,"themoviedb_id":{"movie":[1390599]},"season":{"tvdb":0}},
	  {"type":"SPECIAL","mal_id":292},
	  {"type":"TV","anilist_id":%s,"themoviedb_id":{"tv":[%s,999]},"season":{"tmdb":3}}
	]`, anilist[0], mal, anidb, tvdb, tmdb, anilist[1], anilist[2], tmdb)
}

func TestParseAnimeMappings(t *testing.T) {
	mappings, err := ParseAnimeMappings(fribbFixture([3]string{"10", "11", "12"}, "26209", "290", "1", "72025"))
	require.NoError(t, err)
	require.Len(t, mappings, 3)
	assert.Equal(t, []string{"10", "11", "12"}, []string{mappings[0].AniList, mappings[1].AniList, mappings[2].AniList})
	assert.Equal(t, AnimeMapping{AniList: "10", MAL: ptr("290"), AniDB: ptr("1"), TVDB: ptr("72025"), TMDB: ptr("26209"), TMDBSeason: ptr(2)}, mappings[0])
	assert.Nil(t, mappings[1].TMDB, "a film is not a TMDB show")
	assert.Nil(t, mappings[1].TMDBSeason)
	assert.Equal(t, "291", *mappings[1].MAL)
	assert.Equal(t, "26209", *mappings[2].TMDB)
	assert.Equal(t, 3, *mappings[2].TMDBSeason)
}

func randomID() string { return strconv.Itoa(10_000_000 + rand.IntN(89_999_999)) } //nolint:gosec // test ids

func TestAnimeMappingsLoadTwiceAndResolve(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	tmdb := randomID()
	ids := [3]string{randomID(), randomID(), randomID()}
	mappings, err := ParseAnimeMappings(fribbFixture(ids, tmdb, randomID(), randomID(), randomID()))
	require.NoError(t, err)
	require.NoError(t, store.UpsertMappings(ctx, mappings))
	require.NoError(t, store.UpsertMappings(ctx, mappings))
	got, err := store.MappingByAniList(ctx, ids[0])
	require.NoError(t, err)
	assert.Equal(t, mappings[0], *got)
	film, err := store.MappingByAniList(ctx, ids[1])
	require.NoError(t, err)
	assert.Nil(t, film.TMDB)

	fake := newFake()
	fake.stubTitle(Record{Hit: Hit{Type: core.MediaShow, Title: "Mapped Anime", Year: ptr(1999), IDs: core.ExternalIDs{TMDB: tmdb}},
		Status: ptr(StatusEnded), RuntimeMinutes: ptr(24)})
	title, err := NewResolver(store, fake.providers()).Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: ids[0]}}, nil)
	require.NoError(t, err)
	assert.Equal(t, tmdb, title.IDs.TMDB)
	assert.True(t, title.IsAnime)
}
