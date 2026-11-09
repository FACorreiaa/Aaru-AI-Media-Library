package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ONB-001: the first-run flow's rows of well-known titles, and the titles related to its picks.

func genreOf(t *testing.T, kind RowKind, key string) OnboardingGenre {
	t.Helper()
	for _, g := range OnboardingGenres[kind] {
		if g.Key == key {
			return g
		}
	}
	require.Failf(t, "no such row", "%s %s", kind, key)
	return OnboardingGenre{}
}

func TestOnboardingRowIDsAndTitles(t *testing.T) {
	assert.Equal(t, "onb_show_popular", OnboardingGenres[RowShow][0].ID(RowShow))
	assert.Equal(t, "onb_show_drama", genreOf(t, RowShow, "drama").ID(RowShow))
	for kind, genres := range OnboardingGenres {
		if kind != RowBook {
			assert.Equal(t, "Popular", genres[0].Title, kind)
		}
		seen := map[string]bool{}
		for _, g := range genres {
			assert.False(t, seen[g.Key], "%s %s once", kind, g.Key)
			seen[g.Key] = true
		}
	}
	assert.Len(t, OnboardingGenres[RowAlbum], 1, "albums have Popular only")
}

func TestTMDBOnboardingShowRowsByGenreLeaveAnimationOut(t *testing.T) {
	stub := routes(map[string]string{"/discover/tv": `{"results":[
	  {"id":1,"name":"The Wire","poster_path":"/w.jpg","genre_ids":[18,80],"original_language":"en"},
	  {"id":2,"name":"Talk","poster_path":"/t.jpg","genre_ids":[18,10767],"original_language":"en"}]}`})
	tmdb := &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}
	hits, err := tmdb.Popular(context.Background(), RowShow, genreOf(t, RowShow, "drama"))
	require.NoError(t, err)
	assert.Equal(t, []string{"The Wire"}, titlesOf(hits))
	q := urlQuery(stub.first(t).URL)
	assert.Equal(t, "18", q.Get("with_genres"))
	assert.Equal(t, "popularity.desc", q.Get("sort_by"))
	assert.Equal(t, "300", q.Get("vote_count.gte"))
	assert.Equal(t, "16,10763,10766,10767", q.Get("without_genres"))
	assert.Equal(t, "false", q.Get("include_adult"))
}

func TestTMDBOnboardingFilmRows(t *testing.T) {
	stub := routes(map[string]string{"/discover/movie": `{"results":[{"id":9,"title":"Heat","release_date":"1995-12-15","poster_path":"/h.jpg"}]}`})
	tmdb := &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}
	hits, err := tmdb.Popular(context.Background(), RowFilm, OnboardingGenres[RowFilm][0])
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, core.MediaMovie, hits[0].Type)
	q := urlQuery(stub.first(t).URL)
	assert.Empty(t, q.Get("with_genres"), "Popular is every genre")
	assert.Equal(t, "1000", q.Get("vote_count.gte"))
	assert.Equal(t, "popularity.desc", q.Get("sort_by"))

	_, err = tmdb.Popular(context.Background(), RowFilm, genreOf(t, RowFilm, "science_fiction"))
	require.NoError(t, err)
	assert.Equal(t, "878", urlQuery(stub.all()[1].URL).Get("with_genres"))
}

func TestTMDBOnboardingAnimeStandInIsJapaneseAnimation(t *testing.T) {
	stub := routes(map[string]string{"/discover/tv": `{"results":[{"id":5,"name":"Frieren","poster_path":"/f.jpg","genre_ids":[16],"original_language":"ja"}]}`})
	hits, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).Popular(context.Background(), RowAnime, OnboardingGenres[RowAnime][0])
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.True(t, hits[0].IsAnime)
	q := urlQuery(stub.first(t).URL)
	assert.Equal(t, "16", q.Get("with_genres"))
	assert.Equal(t, "JP", q.Get("with_origin_country"))
	assert.Empty(t, q.Get("air_date.gte"), "well known, not this week's")
}

func TestAniListOnboardingRowsAreAllTimePopularByGenre(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Page":{"media":[
	  {"id":21,"idMal":21,"type":"ANIME","format":"TV","title":{"english":"One Piece"},"coverImage":{"large":"https://img/o.jpg"}}]}}}`})
	anilist := &AniList{Client: testClient(stub, "anilist")}
	hits, err := anilist.Popular(context.Background(), RowAnime, genreOf(t, RowAnime, "slice_of_life"))
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, "21", hits[0].IDs.AniList)
	var sent struct {
		Query     string         `json:"query"`
		Variables map[string]any `json:"variables"`
	}
	require.NoError(t, json.Unmarshal(stub.first(t).Body, &sent))
	assert.Contains(t, sent.Query, "type: ANIME, isAdult: false")
	assert.Contains(t, sent.Query, "genre_in: $genres")
	assert.Contains(t, sent.Query, "sort: POPULARITY_DESC")
	assert.Equal(t, []any{"Slice of Life"}, sent.Variables["genres"])

	_, err = anilist.Popular(context.Background(), RowManga, OnboardingGenres[RowManga][0])
	require.NoError(t, err)
	manga := string(stub.all()[1].Body)
	assert.Contains(t, manga, "type: MANGA, isAdult: false")
	assert.NotContains(t, manga, "genre_in", "Popular is every genre")
	assert.NotContains(t, manga, "RELEASING", "all time, not what is publishing now")
}

func TestOpenLibraryOnboardingRowsAreASubjectsMostLoggedBooks(t *testing.T) {
	stub := routes(map[string]string{"/search.json": `{"docs":[
	  {"key":"/works/OL1W","title":"A Good Girl's Guide to Murder","first_publish_year":2019,"cover_i":7,"author_name":["Holly Jackson"]}]}`})
	hits, err := (&OpenLibrary{Client: testClient(stub, "openlibrary")}).Popular(context.Background(), RowBook, genreOf(t, RowBook, "mystery"))
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, "OL1W", hits[0].IDs.OpenLibrary)
	query := urlQuery(stub.first(t).URL)
	assert.Equal(t, "subject_key:mystery_and_detective_stories language:eng", query.Get("q"))
	assert.Equal(t, "readinglog", query.Get("sort"), "the books people log most, not the most reprinted")
	assert.Equal(t, "30", query.Get("limit"))
}

func TestListenBrainzOnboardingRowIsAllTimeMostPlayed(t *testing.T) {
	stub := routes(map[string]string{"/stats/sitewide/release-groups": `{"payload":{"release_groups":[
	  {"artist_mbids":["a1"],"artist_name":"Radiohead","caa_id":11,"caa_release_mbid":"r1","listen_count":90,
	   "release_group_mbid":"g1","release_group_name":"OK Computer"},
	  {"artist_mbids":["89ad4ac3-39f7-470e-963a-56509c546377"],"artist_name":"Various Artists","caa_id":12,
	   "caa_release_mbid":"r2","listen_count":80,"release_group_mbid":"g2","release_group_name":"Now 50"},
	  {"artist_mbids":["a3"],"artist_name":"No Cover","listen_count":70,"release_group_mbid":"g3","release_group_name":"Bare"}]}}`})
	hits, err := (&ListenBrainz{Client: testClient(stub, "listenbrainz")}).Popular(context.Background(), RowAlbum, OnboardingGenres[RowAlbum][0])
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, "OK Computer", hits[0].Title)
	assert.Equal(t, "g1", hits[0].IDs.MusicBrainz)
	assert.Equal(t, "Radiohead", *hits[0].Byline)
	assert.Equal(t, "https://coverartarchive.org/release/r1/11-250.jpg", *hits[0].PosterURL)
	q := urlQuery(stub.first(t).URL)
	assert.Equal(t, "all_time", q.Get("range"))
}

// countingPopular serves every film row, counting the fetches; "horror" fails.
type countingPopular struct {
	mu    sync.Mutex
	calls map[string]int
}

func (c *countingPopular) OnboardingKinds() []RowKind { return []RowKind{RowFilm} }

func (c *countingPopular) Popular(_ context.Context, _ RowKind, genre OnboardingGenre) ([]Hit, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.calls[genre.Key]++
	if genre.Key == "horror" {
		return nil, provider.NewError("tmdb", provider.KindUnavailable)
	}
	hits := []Hit{discoverHit("No poster "+genre.Key, core.MediaMovie, "np-"+genre.Key, false)}
	for i := range 25 {
		hits = append(hits, discoverHit(genre.Key+strconv.Itoa(i), core.MediaMovie, genre.Key+"-"+strconv.Itoa(i), true))
	}
	return hits, nil
}

func rowIDs(rows []OnboardingRow) []string {
	out := []string{}
	for _, r := range rows {
		out = append(out, r.ID)
	}
	return out
}

func TestOnboardingRowsAreCachedADayAndAFailingRowIsLeftOut(t *testing.T) {
	env := newRefreshEnv(t)
	owned := env.title(core.MediaMovie, "Owned", core.ExternalIDs{TMDB: "drama-3"})
	env.track(owned.ID, "finished")
	source := &countingPopular{calls: map[string]int{}}
	service := NewOnboardingService(NewDiscoverService(env.store, nil, nil, nil, nil), []any{source}, nil, nil)
	service.Now = func() time.Time { return discoverNow }

	rows, err := service.Rows(env.ctx, RowFilm, env.user)
	require.NoError(t, err)
	assert.Equal(t, []string{
		"onb_film_popular", "onb_film_action", "onb_film_comedy", "onb_film_drama",
		"onb_film_science_fiction", "onb_film_thriller", "onb_film_romance",
	}, rowIDs(rows), "in display order, horror left out")
	for _, r := range rows {
		assert.Equal(t, RowFilm, r.Kind)
		assert.Len(t, r.Items, DiscoverRowLimit, "20 a row, poster-less hits dropped")
		assert.Equal(t, strings.TrimPrefix(r.ID, "onb_film_")+"0", r.Items[0].Hit.Title)
		assert.Nil(t, r.Note)
	}
	assert.Equal(t, "Popular", rows[0].Title)
	drama := rows[3]
	require.NotNil(t, drama.Items[3].LibraryItemID, "marked against the caller's library")
	assert.Nil(t, drama.Items[2].LibraryItemID)

	_, err = service.Rows(env.ctx, RowFilm, env.user)
	require.NoError(t, err)
	assert.Equal(t, 1, source.calls["horror"], "a failed row is not asked again at once")
	service.Now = func() time.Time { return discoverNow.Add(OnboardingTTL - time.Minute) }
	_, err = service.Rows(env.ctx, RowFilm, env.user)
	require.NoError(t, err)
	assert.Equal(t, 1, source.calls["drama"], "cached for a day")

	service.Now = func() time.Time { return discoverNow.Add(OnboardingTTL) }
	_, err = service.Rows(env.ctx, RowFilm, env.user)
	require.NoError(t, err)
	assert.Equal(t, 2, source.calls["drama"], "asked again after a day")

	none, err := service.Rows(env.ctx, RowAlbum, env.user)
	require.NoError(t, err)
	assert.Empty(t, none, "no provider for the kind, no rows")
}

// slowPopular holds its Horror row until release is closed; every other row answers at once.
type slowPopular struct{ release chan struct{} }

func (*slowPopular) OnboardingKinds() []RowKind { return []RowKind{RowFilm} }

func (p *slowPopular) Popular(ctx context.Context, _ RowKind, genre OnboardingGenre) ([]Hit, error) {
	if genre.Key == "horror" {
		select {
		case <-p.release:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return []Hit{discoverHit(genre.Key, core.MediaMovie, genre.Key+"-1", true)}, nil
}

func TestOnboardingRowsLeaveOutASlowRowAndServeItOnceItLoads(t *testing.T) {
	source := &slowPopular{release: make(chan struct{})}
	service := NewOnboardingService(NewDiscoverService(NewStore(testdb.New(t)), nil, nil, nil, nil), []any{source}, nil, nil)
	service.Now = func() time.Time { return discoverNow }
	service.Wait = 50 * time.Millisecond
	ctx := context.Background()

	rows, err := service.Rows(ctx, RowFilm, uuid.New())
	require.NoError(t, err, "a slow row is not a failed request")
	assert.NotContains(t, rowIDs(rows), "onb_film_horror")
	assert.Contains(t, rowIDs(rows), "onb_film_drama")

	close(source.release)
	require.Eventually(t, func() bool {
		rows, err := service.Rows(ctx, RowFilm, uuid.New())
		return err == nil && slices.Contains(rowIDs(rows), "onb_film_horror")
	}, 5*time.Second, 20*time.Millisecond, "the fetch went on into the cache")
}

func TestOnboardingWarmLoadsTheRowsBeforeAnyoneAsks(t *testing.T) {
	source := &countingPopular{calls: map[string]int{}}
	service := NewOnboardingService(NewDiscoverService(NewStore(testdb.New(t)), nil, nil, nil, nil), []any{source}, nil, nil)
	service.Now = func() time.Time { return discoverNow }
	service.Warm(context.Background())
	assert.Equal(t, 1, source.calls["drama"])

	rows, err := service.Rows(context.Background(), RowFilm, uuid.New())
	require.NoError(t, err)
	assert.Contains(t, rowIDs(rows), "onb_film_drama")
	assert.Equal(t, 1, source.calls["drama"], "served from the warm cache")
}

// downOnboardingAniList answers "unavailable" for every anime and manga row.
type downOnboardingAniList struct{}

func (downOnboardingAniList) OnboardingKinds() []RowKind { return []RowKind{RowAnime, RowManga} }

func (downOnboardingAniList) Popular(context.Context, RowKind, OnboardingGenre) ([]Hit, error) {
	return nil, provider.NewError("anilist", provider.KindUnavailable)
}

type onboardingStandIn struct{ asked atomic.Int32 }

func (*onboardingStandIn) OnboardingKinds() []RowKind { return nil }

func (s *onboardingStandIn) Popular(_ context.Context, kind RowKind, genre OnboardingGenre) ([]Hit, error) {
	s.asked.Add(1)
	h := discoverHit("Frieren "+string(kind)+" "+genre.Key, core.MediaShow, "209867", true)
	h.IsAnime = true
	return []Hit{h}, nil
}

func TestOnboardingAnimeFallsBackToTMDBWhileAniListIsDownAndMangaHasNone(t *testing.T) {
	standIn := &onboardingStandIn{}
	service := NewOnboardingService(NewDiscoverService(NewStore(testdb.New(t)), nil, nil, nil, nil),
		[]any{downOnboardingAniList{}}, standIn, nil)
	anime, err := service.Rows(context.Background(), RowAnime, uuid.New())
	require.NoError(t, err)
	require.Equal(t, []string{"onb_anime_popular"}, rowIDs(anime), "Popular stands in; the genre rows wait for AniList")
	require.NotNil(t, anime[0].Note)
	assert.Equal(t, AnimeFallbackNote, *anime[0].Note)
	assert.True(t, anime[0].Items[0].Hit.IsAnime)
	assert.Equal(t, int32(1), standIn.asked.Load())

	manga, err := service.Rows(context.Background(), RowManga, uuid.New())
	require.NoError(t, err)
	assert.Empty(t, manga, "manga has no stand-in")
	assert.Equal(t, int32(1), standIn.asked.Load())
}

// MARK: Related

type relatedEnv struct {
	*refreshEnv
	service *RelationService
}

func newRelatedEnv(t *testing.T, sources ...RelationSource) *relatedEnv {
	env := newRefreshEnv(t)
	return &relatedEnv{refreshEnv: env, service: NewRelationService(env.store, sources, nil)}
}

func (e *relatedEnv) film(tmdb, name string) core.Title {
	return e.title(core.MediaMovie, name, core.ExternalIDs{TMDB: tmdb})
}

func relatedTitles(r RelatedPicks) []string {
	out := []string{}
	for _, item := range r.Items {
		out = append(out, item.Hit.Title+" ("+string(item.Relation)+")")
	}
	return out
}

func TestOnboardingRelatedLeavesOutTheLibraryAndThePicksOnceEach(t *testing.T) {
	env := newRelatedEnv(t, lotrSources()...)
	fellowship := env.film("120", "The Fellowship of the Ring")
	towers := env.film("121", "The Two Towers")
	king := env.film("122", "The Return of the King")
	env.track(fellowship.ID, "finished")

	related, err := env.service.OnboardingRelated(env.ctx, env.user, []uuid.UUID{towers.ID, king.ID, uuid.New()})
	require.NoError(t, err)
	assert.False(t, related.Partial)
	assert.Equal(t, []string{
		"The Fellowship of the Ring (novel) (source)",
		"The Two Towers (novel) (source)",
		"The Return of the King (novel) (sequel)",
	}, relatedTitles(related), "the film in the library and the other pick are left out; the books come once")
	for _, item := range related.Items {
		assert.Equal(t, towers.ID, item.FromTitleID, "all of them from the first pick")
		assert.Equal(t, "The Two Towers", item.FromTitle)
		assert.Equal(t, core.MediaBook, item.Hit.Type)
	}
	assert.Equal(t, 1954, *related.Items[1].Hit.Year)

	// From the last film, the chain reads backward: the films before it are its prequels.
	related, err = env.service.OnboardingRelated(env.ctx, env.user, []uuid.UUID{king.ID})
	require.NoError(t, err)
	assert.Equal(t, "The Two Towers (prequel)", relatedTitles(related)[0], "main chain first")
}

func TestOnboardingRelatedCapsAtThirty(t *testing.T) {
	centre := film("1", "Doctor Who", "1963-11-23")
	var edges []RelatedEdge
	for i := range 35 {
		edges = append(edges, RelatedEdge{To: film(fmt.Sprint(100+i), fmt.Sprint("Special ", i), "1990-01-01"), Relation: core.RelationSideStory})
	}
	env := newRelatedEnv(t, &fakeRelations{name: "s", answers: map[string]Relations{"tmdb:movie:1": {Edges: edges}}})
	pick := env.film("1", centre.Title)
	related, err := env.service.OnboardingRelated(env.ctx, env.user, []uuid.UUID{pick.ID})
	require.NoError(t, err)
	assert.Len(t, related.Items, MaxOnboardingRelated)
	assert.Equal(t, core.RelationSideStory, related.Items[0].Relation)
}

// blockingRelations answers only once released, or never within a deadline.
type blockingRelations struct{ release chan struct{} }

func (b *blockingRelations) RelationSourceName() string       { return "blocking" }
func (b *blockingRelations) RelationKey(n RelatedNode) string { return NodeKeys(n)[0] }
func (b *blockingRelations) Relations(ctx context.Context, _ RelatedNode) (Relations, error) {
	select {
	case <-ctx.Done():
		return Relations{}, ctx.Err()
	case <-b.release:
		return Relations{Edges: []RelatedEdge{}}, nil
	}
}

func TestOnboardingRelatedSharesTheThirtyAcrossPicks(t *testing.T) {
	var whoEdges, trekEdges []RelatedEdge
	for i := range 35 {
		whoEdges = append(whoEdges, RelatedEdge{To: film(fmt.Sprint(100+i), fmt.Sprint("Special ", i), "1990-01-01"), Relation: core.RelationSideStory})
	}
	for i := range 3 {
		trekEdges = append(trekEdges, RelatedEdge{To: film(fmt.Sprint(300+i), fmt.Sprint("Trek ", i), "1990-01-01"), Relation: core.RelationSequel})
	}
	env := newRelatedEnv(t, &fakeRelations{name: "s", answers: map[string]Relations{
		"tmdb:movie:1": {Edges: whoEdges}, "tmdb:movie:2": {Edges: trekEdges},
	}})
	who := env.film("1", "Doctor Who")
	trek := env.film("2", "Star Trek")
	related, err := env.service.OnboardingRelated(env.ctx, env.user, []uuid.UUID{who.ID, trek.ID})
	require.NoError(t, err)
	require.Len(t, related.Items, MaxOnboardingRelated)
	from := map[uuid.UUID]int{}
	for _, item := range related.Items {
		from[item.FromTitleID]++
	}
	assert.Equal(t, 3, from[trek.ID], "the short franchise keeps all of its titles")
	assert.Equal(t, 27, from[who.ID])
	assert.Equal(t, who.ID, related.Items[0].FromTitleID, "grouped by pick, in the picks' order")
	assert.Equal(t, trek.ID, related.Items[27].FromTitleID)
}

func TestOnboardingRelatedIsPartialWhenGraphsRunOutOfTime(t *testing.T) {
	source := &blockingRelations{release: make(chan struct{})}
	t.Cleanup(func() { close(source.release) })
	env := newRelatedEnv(t, source)
	env.service.OnboardingDeadline = 50 * time.Millisecond
	picks := []uuid.UUID{env.film("1", "A").ID, env.film("2", "B").ID, env.film("3", "C").ID, env.film("4", "D").ID, env.film("5", "E").ID}
	started := time.Now()
	related, err := env.service.OnboardingRelated(env.ctx, env.user, picks)
	require.NoError(t, err)
	assert.True(t, related.Partial)
	assert.Empty(t, related.Items)
	assert.Less(t, time.Since(started), 2*time.Second, "one deadline for every graph, not one each")
	_, warming := env.service.warming.Load("tmdb:movie:1")
	assert.True(t, warming, "a graph cut short keeps loading for the next call")
}

func TestOnboardingRelatedTakesOneToThirtyTitles(t *testing.T) {
	env := newRelatedEnv(t)
	_, err := env.service.OnboardingRelated(env.ctx, env.user, nil)
	require.Equal(t, 422, apperr.From(err).Status)
	_, err = env.service.OnboardingRelated(env.ctx, env.user, make([]uuid.UUID, 31))
	require.Equal(t, 422, apperr.From(err).Status)
}
