package catalog

import (
	"context"
	"strings"
	"testing"
	"time"

	"aaru-go-api/internal/core"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Adapters against canned provider JSON (CAT-002, CAT-003, CAT-007).

func TestTMDBSearchCarriesTMDBAndIMDbIDs(t *testing.T) {
	stub := routes(map[string]string{
		"/search/movie": `{"results":[{"id":603,"title":"The Matrix","original_title":"The Matrix","release_date":"1999-03-30",
		 "poster_path":"/p.jpg","overview":"Neo.","genre_ids":[28],"original_language":"en"}]}`,
		"/movie/603/external_ids": `{"imdb_id":"tt0133093"}`,
	})
	hits, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "v3key"}).Search(context.Background(), "matrix", core.MediaMovie)
	require.NoError(t, err)
	assert.Equal(t, []Hit{{
		Type: core.MediaMovie, Title: "The Matrix", Year: ptr(1999), PosterURL: ptr("https://image.tmdb.org/t/p/w500/p.jpg"),
		Overview: ptr("Neo."), IDs: core.ExternalIDs{TMDB: "603", IMDB: "tt0133093"}, ReleaseDate: ptr("1999-03-30"),
	}}, hits)
	assert.Equal(t, "v3key", urlQuery(stub.first(t).URL).Get("api_key"))
}

func TestTMDBMultiKeepsFilmsAndShows(t *testing.T) {
	stub := routes(map[string]string{
		"/search/multi": `{"results":[
		  {"id":1,"media_type":"movie","title":"Mob Film","release_date":"2025-05-02"},
		  {"id":2,"media_type":"tv","name":"MobLand","first_air_date":"2025-03-30"},
		  {"id":3,"media_type":"person","name":"Tom Hardy"},
		  {"id":4,"media_type":"movie","title":"Adult","adult":true,"release_date":"2020-01-01"},
		  {"id":5,"media_type":"movie","title":"Undated","release_date":""}]}`,
		"/movie/1/external_ids": `{"imdb_id":"tt1"}`,
		"/tv/2/external_ids":    `{"imdb_id":"tt2"}`,
	})
	hits, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).SearchMulti(context.Background(), "mob")
	require.NoError(t, err)
	var titles, imdb []string
	var types []core.MediaType
	var dates []*string
	for _, h := range hits {
		titles, types, imdb, dates = append(titles, h.Title), append(types, h.Type), append(imdb, h.IDs.IMDB), append(dates, h.ReleaseDate)
	}
	assert.Equal(t, []string{"Mob Film", "MobLand", "Undated"}, titles)
	assert.Equal(t, []core.MediaType{core.MediaMovie, core.MediaShow, core.MediaMovie}, types)
	assert.Equal(t, []string{"tt1", "tt2", ""}, imdb, "external ids by each hit's own kind")
	assert.Equal(t, []*string{ptr("2025-05-02"), ptr("2025-03-30"), nil}, dates)
	first := stub.first(t)
	assert.True(t, strings.HasSuffix(urlPath(first.URL), "/search/multi"))
	assert.Equal(t, "false", urlQuery(first.URL).Get("include_adult"))
}

func TestTMDBReadTokenGoesInTheHeader(t *testing.T) {
	stub := routes(map[string]string{"/search/tv": `{"results":[]}`})
	_, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "eyJ.header.sig"}).Search(context.Background(), "x", core.MediaShow)
	require.NoError(t, err)
	req := stub.first(t)
	assert.NotContains(t, req.URL, "api_key")
	assert.True(t, hasHeader(req, "Authorization", "Bearer eyJ.header.sig"))
}

func TestTMDBEpisodesSpanEverySeason(t *testing.T) {
	stub := routes(map[string]string{
		"/tv/1399": `{"id":1399,"name":"GoT","status":"Ended","episode_run_time":[60],
		 "seasons":[{"season_number":1},{"season_number":2}]}`,
		"/tv/1399/season/1": `{"episodes":[{"id":1,"season_number":1,"episode_number":1,"name":"Winter Is Coming",
		  "air_date":"2011-04-17","runtime":62,"overview":"Lord Stark is troubled.","still_path":"/still.jpg"}]}`,
		"/tv/1399/season/2": `{"episodes":[{"id":2,"season_number":2,"episode_number":1,"name":"The North Remembers",
		  "air_date":"2012-04-01"}]}`,
	})
	result, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).Episodes(context.Background(), core.ExternalIDs{TMDB: "1399"})
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, StatusEnded, *result.Status)
	require.Len(t, result.Episodes, 2)
	assert.Equal(t, [2]int{1, 1}, [2]int{result.Episodes[0].Season, result.Episodes[0].Episode})
	assert.Equal(t, [2]int{2, 1}, [2]int{result.Episodes[1].Season, result.Episodes[1].Episode})
	assert.Equal(t, 60, *result.Episodes[1].RuntimeMinutes, "falls back to the show's episode run time")
	assert.Equal(t, "Lord Stark is troubled.", *result.Episodes[0].Overview)
	assert.Equal(t, "https://image.tmdb.org/t/p/w300/still.jpg", *result.Episodes[0].StillURL)
	assert.Nil(t, result.Episodes[1].StillURL)
}

func TestOpenLibrarySearchNormalizesISBN(t *testing.T) {
	stub := routes(map[string]string{"/search.json": `{"docs":[{"key":"/works/OL893415W","title":"Dune","first_publish_year":1965,
	  "isbn":["0441172717","9780441172719"],"cover_i":123,"author_name":["Frank Herbert"],"number_of_pages_median":412}]}`})
	hits, err := (&OpenLibrary{Client: testClient(stub, "ol"), UserAgent: "Aaru-test"}).Search(context.Background(), "dune", core.MediaBook)
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, core.ExternalIDs{ISBN: "9780441172719", OpenLibrary: "OL893415W"}, hits[0].IDs)
	assert.Equal(t, "Frank Herbert", *hits[0].Byline)
	assert.Equal(t, 412, *hits[0].PageCount)
	assert.True(t, hasHeader(stub.first(t), "User-Agent", "Aaru-test"))
}

func TestAniListSearchMarksAnime(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Page":{"media":[
	  {"id":16498,"idMal":16498,"format":"TV","status":"FINISHED","episodes":25,"duration":24,
	   "title":{"romaji":"Shingeki no Kyojin","english":"Attack on Titan","native":"進撃の巨人"},
	   "startDate":{"year":2013},"coverImage":{"large":"https://img/aot.jpg"},"description":"Titans."},
	  {"id":199,"idMal":199,"format":"MOVIE","status":"FINISHED","episodes":1,"duration":125,
	   "title":{"romaji":"Sen to Chihiro","english":"Spirited Away","native":null},
	   "startDate":{"year":2001},"coverImage":null,"description":null}]}}}`})
	hits, err := (&AniList{Client: testClient(stub, "anilist")}).Search(context.Background(), "x", core.MediaShow)
	require.NoError(t, err)
	require.Len(t, hits, 2)
	assert.Equal(t, core.MediaShow, hits[0].Type)
	assert.Equal(t, core.MediaMovie, hits[1].Type)
	assert.True(t, hits[0].IsAnime && hits[1].IsAnime)
	assert.Equal(t, core.ExternalIDs{AniList: "16498", MAL: "16498"}, hits[0].IDs)
	assert.Equal(t, "Attack on Titan", hits[0].Title)
	assert.Equal(t, "POST", stub.first(t).Method)
}

func TestAniListReleaseDateOnlyWithTheDay(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Page":{"media":[
	  {"id":1,"format":"TV","title":{"romaji":"A"},"startDate":{"year":2023,"month":9,"day":29}},
	  {"id":2,"format":"TV","title":{"romaji":"B"},"startDate":{"year":2027,"month":null,"day":null}}]}}}`})
	hits, err := (&AniList{Client: testClient(stub, "anilist")}).Search(context.Background(), "x", core.MediaShow)
	require.NoError(t, err)
	require.Len(t, hits, 2)
	assert.Equal(t, "2023-09-29", *hits[0].ReleaseDate)
	assert.Nil(t, hits[1].ReleaseDate)
	assert.Equal(t, 2023, *hits[0].Year)
	assert.Equal(t, 2027, *hits[1].Year)
	assert.Contains(t, string(stub.first(t).Body), "startDate { year month day }")
}

func TestAniListPlainText(t *testing.T) {
	html := "An elf mage <i>outlives</i> her party.<br><br>\n(Source: Crunchyroll &amp; others)"
	assert.Equal(t, "An elf mage outlives her party.\n\n(Source: Crunchyroll & others)", AniListPlainText(html))
	assert.Equal(t, "Use &lt;br&gt; tags", AniListPlainText("Use &amp;lt;br&amp;gt; tags"), "decoded once")
}

func TestParseDayRejectsRollover(t *testing.T) {
	assert.Nil(t, ParseDay(ptr("2025-02-30")))
	assert.Nil(t, ParseDay(ptr("2025-13-01")))
	assert.Nil(t, ParseDay(ptr("2025-00-10")))
	assert.Equal(t, time.Unix(1_709_164_800, 0).UTC(), *ParseDay(ptr("2024-02-29")))
	assert.Equal(t, time.Unix(1_741_910_400, 0).UTC(), *ParseDay(ptr("2025-03-14T10:00:00Z")))
}

func TestAniListEpisodesFromTheSchedule(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Media":{"id":1,"idMal":null,"format":"TV","status":"RELEASING","episodes":null,"duration":24,
	  "title":{"romaji":"X","english":null,"native":null},"startDate":{"year":2026},"coverImage":null,"description":null,
	  "airingSchedule":{"nodes":[{"episode":1,"airingAt":1790000000},{"episode":2,"airingAt":1790604800}]},
	  "nextAiringEpisode":{"episode":3,"airingAt":1791209600},
	  "streamingEpisodes":[{"title":"Episode 2 - The Second One"},{"title":"Episode 1 - Pilot"},
	    {"title":"Episode 9 - Out of Range"},{"title":"Recap Special"}]}}}`})
	result, err := (&AniList{Client: testClient(stub, "anilist")}).Episodes(context.Background(), core.ExternalIDs{AniList: "1"})
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, StatusReturning, *result.Status)
	var numbers []int
	var names []*string
	for _, e := range result.Episodes {
		numbers, names = append(numbers, e.Episode), append(names, e.Name)
		assert.Equal(t, 1, e.Season)
		assert.NotNil(t, e.AirsAt)
	}
	assert.Equal(t, []int{1, 2, 3}, numbers)
	assert.Equal(t, []*string{ptr("Pilot"), ptr("The Second One"), nil}, names, "named from streaming links")
}

func TestRecordsCarryGenreNames(t *testing.T) {
	tmdb := routes(map[string]string{"/movie/329865": `{"id":329865,"title":"Arrival","release_date":"2016-11-10","runtime":116,
	 "genres":[{"id":18,"name":"Drama"},{"id":878,"name":"Science Fiction"},{"id":9648,"name":" "}]}`})
	movie, err := (&TMDB{Client: testClient(tmdb, "tmdb"), APIKey: "v3key"}).Hydrate(context.Background(), core.ExternalIDs{TMDB: "329865"}, core.MediaMovie)
	require.NoError(t, err)
	require.NotNil(t, movie)
	assert.Equal(t, []string{"Drama", "Science Fiction"}, movie.Genres)

	anilist := routes(map[string]string{"": `{"data":{"Media":{"id":154587,"format":"TV","title":{"romaji":"Sousou no Frieren"},
	  "genres":["Adventure","Drama","Fantasy"]}}}`})
	anime, err := (&AniList{Client: testClient(anilist, "anilist")}).Hydrate(context.Background(), core.ExternalIDs{AniList: "154587"}, core.MediaShow)
	require.NoError(t, err)
	require.NotNil(t, anime)
	assert.Equal(t, []string{"Adventure", "Drama", "Fantasy"}, anime.Genres)
	assert.Contains(t, string(anilist.first(t).Body), "genres")
}
