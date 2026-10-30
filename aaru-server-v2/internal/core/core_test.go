package core

import (
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func ptr[T any](v T) *T { return &v }

func TestISBN(t *testing.T) {
	assert.Equal(t, "9780441172719", NormalizeISBN("0-441-17271-7"), "Dune, ISBN-10")
	assert.Equal(t, "9780441172719", NormalizeISBN("978-0-441-17271-9"), "Dune, ISBN-13")
	assert.Equal(t, "9780441172719", NormalizeISBN(`="0441172717"`))
	assert.Equal(t, "9780804429573", NormalizeISBN("080442957X"))
	for _, bad := range []string{"0441172718", "9780441172710", "", "12345"} {
		assert.Empty(t, NormalizeISBN(bad), bad)
	}
}

func TestRating(t *testing.T) {
	for _, v := range []float64{1.0, 1.5, 5.0, 7.5, 10.0} {
		r, err := NewRating(v)
		require.NoError(t, err)
		assert.InDelta(t, v, r.Value(), 0)
	}
	for _, v := range []float64{0.0, 0.5, 10.5, 11.0, -3.0} {
		_, err := NewRating(v)
		assert.ErrorIs(t, err, &ValidationError{Kind: RatingOutOfRange, Value: v})
	}
	for _, v := range []float64{1.2, 4.75, 9.9} {
		_, err := NewRating(v)
		assert.ErrorIs(t, err, &ValidationError{Kind: RatingNotInHalfSteps, Value: v})
	}
	var r Rating
	require.Error(t, json.Unmarshal([]byte("11"), &r))
	assert.Equal(t, "10", Rating(10).String())
	assert.Equal(t, "8.5", Rating(8.5).String())
	assert.Less(t, Rating(6.5), Rating(7))
}

func TestValidationMessagesAndFields(t *testing.T) {
	cases := []struct {
		err     *ValidationError
		field   string
		message string
	}{
		{&ValidationError{Kind: EmptyTitle}, "title", "Title text must not be empty."},
		{&ValidationError{Kind: InvalidYear, Year: 1600}, "year", "Year 1600 is outside 1870–2200."},
		{&ValidationError{Kind: RatingOutOfRange, Value: 11}, "rating", "Rating 11.0 is outside 1.0–10.0."},
		{&ValidationError{Kind: RatingNotInHalfSteps, Value: 4.75}, "rating", "Rating 4.75 is not a multiple of 0.5."},
		{&ValidationError{Kind: EmptyListName}, "name", "List name must not be empty."},
		{&ValidationError{Kind: InvalidEpisodeNumber, Season: 1, Episode: 0}, "episode", "Season 1 episode 0 is not a valid episode reference."},
		{&ValidationError{Kind: InvalidBookProgress}, "progress", "Book progress needs a non-negative page or a percent between 0 and 100."},
		{&ValidationError{Kind: InvalidMangaProgress}, "progress", "Manga progress needs a non-negative chapter or volume."},
		{&ValidationError{Kind: UnresolvableMediaRef}, "mediaRef", "A media reference needs a title id, an external id, or a title and year."},
	}
	for _, c := range cases {
		assert.Equal(t, c.message, c.err.Error())
		app := c.err.AppError()
		assert.Equal(t, http.StatusUnprocessableEntity, app.Status)
		assert.Equal(t, "validation_failed", app.Code)
		assert.Equal(t, map[string]string{c.field: c.message}, app.Details)
	}
}

func TestExternalIDs(t *testing.T) {
	assert.True(t, ExternalIDs{}.IsEmpty())
	assert.False(t, ExternalIDs{TMDB: "603"}.IsEmpty())

	merged := ExternalIDs{TMDB: "603", Trakt: "481"}.Filling(ExternalIDs{TMDB: "999", IMDB: "tt0133093"})
	assert.Equal(t, "603", merged.TMDB, "the earlier source keeps its value")
	assert.Equal(t, "481", merged.Trakt)
	assert.Equal(t, "tt0133093", merged.IMDB, "the later source fills what was empty")

	a := ExternalIDs{TMDB: "603", IMDB: "tt0133093"}
	assert.True(t, a.Matches(ExternalIDs{IMDB: "tt0133093"}))
	assert.False(t, a.Matches(ExternalIDs{IMDB: "tt0234215"}))
	assert.False(t, ExternalIDs{}.Matches(ExternalIDs{}), "two unknowns are not a match")
	assert.False(t, a.Matches(ExternalIDs{Trakt: "481"}), "no shared provider is no match")

	known := ExternalIDs{TMDB: "603", OpenLibrary: "OL123W"}.Known()
	assert.Equal(t, []KnownID{{"tmdb", "603"}, {"openLibrary", "OL123W"}}, known)
}

func TestValidation(t *testing.T) {
	assert.ErrorIs(t, Title{Type: MediaMovie, Title: "   "}.Validate(), &ValidationError{Kind: EmptyTitle})
	assert.ErrorIs(t, Title{Type: MediaMovie, Title: "Nosferatu", Year: ptr(1600)}.Validate(), &ValidationError{Kind: InvalidYear, Year: 1600})
	assert.NoError(t, Title{Type: MediaMovie, Title: "Nosferatu", Year: ptr(1922)}.Validate())

	assert.ErrorIs(t, AaruList{Name: " "}.Validate(), &ValidationError{Kind: EmptyListName})

	assert.False(t, MediaRef{Type: MediaMovie}.IsResolvable())
	assert.False(t, MediaRef{Type: MediaMovie, Title: ptr("Heat")}.IsResolvable(), "a name with no year is not enough")
	assert.True(t, MediaRef{Type: MediaMovie, Title: ptr("Heat"), Year: ptr(1995)}.IsResolvable())
	assert.True(t, MediaRef{Type: MediaMovie, IDs: ExternalIDs{TMDB: "949"}}.IsResolvable())
	id := uuid.New()
	assert.True(t, MediaRef{TitleID: &id, Type: MediaMovie}.IsResolvable())
	assert.ErrorIs(t, MediaRef{Type: MediaBook}.Validate(), &ValidationError{Kind: UnresolvableMediaRef})

	_, err := NewEpisodeKey(1, 0)
	assert.ErrorIs(t, err, &ValidationError{Kind: InvalidEpisodeNumber, Season: 1, Episode: 0})
	_, err = NewEpisodeKey(0, 1)
	assert.NoError(t, err, "specials")

	_, err = NewBookProgress(ptr(-1), nil)
	assert.ErrorIs(t, err, &ValidationError{Kind: InvalidBookProgress})
	_, err = NewBookProgress(nil, ptr(101.0))
	assert.ErrorIs(t, err, &ValidationError{Kind: InvalidBookProgress})
	_, err = NewBookProgress(ptr(0), ptr(0.0))
	assert.NoError(t, err)

	_, err = NewMangaProgress(ptr(-1), nil)
	assert.ErrorIs(t, err, &ValidationError{Kind: InvalidMangaProgress})
	_, err = NewMangaProgress(nil, ptr(-1))
	assert.ErrorIs(t, err, &ValidationError{Kind: InvalidMangaProgress})
	_, err = NewMangaProgress(ptr(112), ptr(12))
	assert.NoError(t, err)

	progress := ShowProgress{Watched: map[EpisodeKey]struct{}{{1, 9}: {}, {2, 1}: {}, {1, 10}: {}}}
	assert.Equal(t, 3, progress.WatchedCount())
	furthest, ok := progress.FurthestWatched()
	assert.True(t, ok)
	assert.Equal(t, EpisodeKey{2, 1}, furthest)
}

func TestNormalizeTitle(t *testing.T) {
	cases := map[string]string{
		"Amélie":              "amelie",
		"WALL·E":              "wall e",
		"  Spirited   Away  ": "spirited away",
		"Se7en":               "se7en",
		"The Office":          "office",
		"A Ghost Story":       "ghost story",
		"An Education":        "education",
		"The The Thing":       "the thing",
		"The":                 "the",
		"ＡＫＩＲＡ":               "akira",
	}
	for in, want := range cases {
		assert.Equal(t, want, NormalizeTitle(in), in)
	}
}

func TestCanMerge(t *testing.T) {
	a := MediaRef{Type: MediaMovie, IDs: ExternalIDs{IMDB: "tt0133093"}, Title: ptr("The Matrix"), Year: ptr(1999)}
	b := MediaRef{Type: MediaMovie, IDs: ExternalIDs{IMDB: "tt0133093"}, Title: ptr("Matrix")}
	assert.True(t, CanMerge(a, b), "matching identifiers merge regardless of name")

	assert.False(t, CanMerge(
		MediaRef{Type: MediaMovie, Title: ptr("The Matrix"), Year: ptr(1999)},
		MediaRef{Type: MediaMovie, Title: ptr("The Matrix"), Year: ptr(2021)},
	), "different years are different works")
	assert.False(t, CanMerge(
		MediaRef{Type: MediaShow, Title: ptr("Fargo"), Year: ptr(2014)},
		MediaRef{Type: MediaMovie, Title: ptr("Fargo"), Year: ptr(2014)},
	), "type is part of identity")

	matrix := MediaRef{Type: MediaMovie, Title: ptr("The Matrix"), Year: ptr(1999)}
	assert.False(t, CanMerge(matrix, MediaRef{Type: MediaMovie, Title: ptr("Matrix, The")}))
	assert.True(t, CanMerge(matrix, MediaRef{Type: MediaMovie, Title: ptr("the matrix")}))

	assert.False(t, CanMerge(
		MediaRef{Type: MediaMovie, IDs: ExternalIDs{TMDB: "1399"}, Title: ptr("Game of Thrones"), Year: ptr(2011)},
		MediaRef{Type: MediaShow, IDs: ExternalIDs{TMDB: "1399"}, Title: ptr("Game of Thrones"), Year: ptr(2011)},
	), "a shared tmdb number across movie and show is not a match")

	fromAniList := ExternalIDs{AniList: "21", MAL: "21"}
	fromMAL := ExternalIDs{MAL: "21", AniDB: "69"}
	assert.True(t, fromAniList.Matches(fromMAL))
	assert.Equal(t, ExternalIDs{AniList: "21", MAL: "21", AniDB: "69"}, fromAniList.Filling(fromMAL))
}

func TestBookYearTolerance(t *testing.T) {
	goodreads := MediaRef{Type: MediaBook, Title: ptr("Leviathan Wakes"), Year: ptr(2011)}
	hit := MediaRef{Type: MediaBook, Title: ptr("Leviathan Wakes"), Year: ptr(2012)}
	author := ptr("James S.A. Corey")
	assert.True(t, CanMergeBook(goodreads, author, hit, ptr("James S. A. Corey")))
	assert.True(t, CanMergeBook(goodreads, author, hit, ptr("Someone, James S. A. Corey")))
	assert.False(t, CanMerge(goodreads, hit), "plain matching stays exact")

	assert.False(t, CanMergeBook(goodreads, ptr("Someone Else"), hit, ptr("James S. A. Corey")))
	assert.False(t, CanMergeBook(goodreads, nil, hit, ptr("James S. A. Corey")))
	assert.False(t, CanMergeBook(goodreads, author, hit, nil))
	assert.False(t, SameAuthor("James Corey", "James S. A. Corey"))
	assert.False(t, SameAuthor("", ""))

	for _, other := range []MediaRef{
		{Type: MediaBook, Title: ptr("Leviathan Wakes"), Year: ptr(2013)},
		{Type: MediaBook, Title: ptr("Leviathan Wakes")},
		{Type: MediaBook, Title: ptr("Caliban's War"), Year: ptr(2012)},
	} {
		assert.False(t, CanMergeBook(goodreads, author, other, ptr("James S. A. Corey")))
	}
	film := MediaRef{Type: MediaMovie, Title: ptr("Dune"), Year: ptr(2021)}
	nextYear := MediaRef{Type: MediaMovie, Title: ptr("Dune"), Year: ptr(2022)}
	assert.False(t, CanMergeBook(film, ptr("Denis Villeneuve"), nextYear, ptr("Denis Villeneuve")))
}

func TestWireContract(t *testing.T) {
	assert.Equal(t, []LibraryStatus{"wishlist", "in_progress", "on_hold", "finished", "dropped"}, LibraryStatuses)
	assert.Equal(t, []MediaType{"movie", "show", "book", "album", "manga"}, MediaTypes)
	want := []ImportSource{
		"trakt", "stremio", "imdb_csv", "letterboxd_csv", "goodreads_csv", "cat_list", "cat_ics",
		"netflix_csv", "tvtime_csv", "mal_xml", "anilist", "csv", "capture",
		"lastfm", "listenbrainz", "spotify_json", "youtube_takeout",
	}
	assert.Equal(t, want, ImportSources)
	var listens []ImportSource
	for _, s := range ImportSources {
		if s.IsListens() {
			listens = append(listens, s)
		}
	}
	assert.Equal(t, []ImportSource{SourceLastFM, SourceListenBrainz, SourceSpotifyJSON, SourceYouTubeTakeout}, listens)

	var stats ImportStats
	require.NoError(t, json.Unmarshal([]byte(`{"created":1,"updated":2,"skipped":3,"unmatched":4}`), &stats))
	assert.Equal(t, ImportStats{Created: 1, Updated: 2, Skipped: 3, Unmatched: 4}, stats)
	assert.Equal(t, 10, stats.Total())

	order := []ImportSource{SourceTrakt, SourceStremio, SourceIMDbCSV, SourceLetterboxdCSV, SourceGoodreadsCSV, SourceCATList, SourceCATICS, SourceNetflixCSV, SourceTVTimeCSV, SourceMALXML}
	for i := 1; i < len(order); i++ {
		assert.Less(t, order[i-1].MergeRank(), order[i].MergeRank())
	}
	assert.False(t, JobQueued.IsTerminal())
	assert.False(t, JobRunning.IsTerminal())
	assert.False(t, JobPlanned.IsTerminal(), "a plan waits for the user's approval")
	assert.True(t, JobSucceeded.IsTerminal())
	assert.True(t, JobFailed.IsTerminal())
	assert.True(t, JobPartial.IsTerminal())
}

func TestProgressRoundTrip(t *testing.T) {
	show := Progress{Show: &ShowProgress{Watched: map[EpisodeKey]struct{}{{1, 1}: {}, {1, 2}: {}}, CurrentSeason: ptr(1), CurrentEpisode: ptr(3)}}
	data, err := json.Marshal(show)
	require.NoError(t, err)
	assert.JSONEq(t, `{"kind":"show","show":{"watched":[{"season":1,"episode":1},{"season":1,"episode":2}],"currentSeason":1,"currentEpisode":3}}`, string(data))
	var back Progress
	require.NoError(t, json.Unmarshal(data, &back))
	assert.Equal(t, show.Show.Watched, back.Show.Watched)

	book := Progress{Book: &BookProgress{Page: ptr(120), Percent: ptr(34.5)}}
	data, err = json.Marshal(book)
	require.NoError(t, err)
	back = Progress{}
	require.NoError(t, json.Unmarshal(data, &back))
	assert.Equal(t, 120, *back.Book.Page)
	assert.Nil(t, back.Show)

	manga := Progress{Manga: &MangaProgress{Chapter: ptr(112), Volume: ptr(12)}}
	data, err = json.Marshal(manga)
	require.NoError(t, err)
	back = Progress{}
	require.NoError(t, json.Unmarshal(data, &back))
	assert.Equal(t, 112, *back.Manga.Chapter)
	assert.Nil(t, back.Book)

	var key EpisodeKey
	err = json.Unmarshal([]byte(`{"season":1,"episode":0}`), &key)
	var verr *ValidationError
	assert.True(t, errors.As(err, &verr))
}

func TestNowWatching(t *testing.T) {
	id := uuid.MustParse("6f1c2a52-6a4e-4d4c-9b1a-6f2b8a1d3e4f")
	attrs := NowWatchingAttributes{LibraryItemID: "x", Title: "Show", Season: 1, Episode: 8, EpisodeName: ptr("Lanterns"), RuntimeMinutes: 41, WatchEventID: (*AppleUUID)(&id)}
	assert.Equal(t, "S1 · E8 · Lanterns", attrs.EpisodeLine())
	assert.True(t, attrs.Matches("x", 1, 8))
	data, err := json.Marshal(attrs)
	require.NoError(t, err)
	assert.Contains(t, string(data), `"watchEventId":"6F1C2A52-6A4E-4D4C-9B1A-6F2B8A1D3E4F"`)
	content, err := json.Marshal(NowWatchingContent{StartedAt: ReferenceTime{referenceEpoch.Add(90e9)}})
	require.NoError(t, err)
	assert.Contains(t, string(content), `"startedAt":90`)
}
