package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"fmt"
	"math/rand/v2"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Catalog resolution and detail (CAT-004…009).

func movieRecord(title string, year int, ids core.ExternalIDs) Record {
	return Record{Hit: Hit{Type: core.MediaMovie, Title: title, Year: &year, IDs: ids}, RuntimeMinutes: ptr(120)}
}

// testClock is a clock tests move by hand.
type testClock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *testClock) Now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.now }

func (c *testClock) advance(d time.Duration) { c.mu.Lock(); c.now = c.now.Add(d); c.mu.Unlock() }

func TestConcurrentResolutionsMakeOneRow(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	store := NewStore(pool)
	fake := newFake()
	fake.stubTitle(movieRecord("Dune", 2021, core.ExternalIDs{TMDB: "438631", IMDB: "tt1160419"}))
	resolver := NewResolver(store, fake.providers())
	ref := core.MediaRef{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "438631"}}
	var wg sync.WaitGroup
	var mu sync.Mutex
	ids := map[uuid.UUID]bool{}
	for range 8 {
		wg.Go(func() {
			title, err := resolver.Resolve(ctx, ref, nil)
			assert.NoError(t, err)
			mu.Lock()
			ids[title.ID] = true
			mu.Unlock()
		})
	}
	wg.Wait()
	assert.Len(t, ids, 1)
	var rows int
	require.NoError(t, pool.QueryRow(ctx, `SELECT count(*) FROM titles WHERE tmdb = '438631'`).Scan(&rows))
	assert.Equal(t, 1, rows)
}

func TestKnownTitleIsFoundWithoutTheProvider(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	fake.stubTitle(movieRecord("Arrival", 2016, core.ExternalIDs{TMDB: "329865", IMDB: "tt2543164"}))
	resolver := NewResolver(store, fake.providers())
	ref := core.MediaRef{Type: core.MediaMovie, IDs: core.ExternalIDs{IMDB: "tt2543164"}}
	first, err := resolver.Resolve(ctx, ref, nil)
	require.NoError(t, err)
	second, err := resolver.Resolve(ctx, ref, nil)
	require.NoError(t, err)
	assert.Equal(t, first.ID, second.ID)
	assert.Equal(t, 1, fake.callCount("hydrate"))
}

func TestTitleAndYearResolveOnlyAnUnambiguousMatch(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	solo := movieRecord("Heat", 1995, core.ExternalIDs{TMDB: "949"})
	fake.stubSearch("Heat", []Hit{solo.Hit})
	fake.stubTitle(solo)
	fake.stubSearch("Crash", []Hit{
		movieRecord("Crash", 2004, core.ExternalIDs{TMDB: "1"}).Hit, movieRecord("Crash", 2004, core.ExternalIDs{TMDB: "2"}).Hit,
	})
	resolver := NewResolver(store, fake.providers())
	heat, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaMovie, Title: ptr("Heat"), Year: ptr(1995)}, nil)
	require.NoError(t, err)
	assert.Equal(t, "949", heat.IDs.TMDB)
	_, err = resolver.Resolve(ctx, core.MediaRef{Type: core.MediaMovie, Title: ptr("Crash"), Year: ptr(2004)}, nil)
	assert.ErrorIs(t, err, ErrAmbiguous)
	_, err = resolver.Resolve(ctx, core.MediaRef{Type: core.MediaMovie, Title: ptr("Heat"), Year: ptr(1986)}, nil)
	assert.ErrorIs(t, err, ErrUnresolvable)
	assert.Equal(t, 422, ErrAmbiguous.AppError().Status)
	assert.Equal(t, "unresolvable", ErrUnresolvable.AppError().Code)
}

// isbn10Check is the ISBN-10 check character for nine digits.
func isbn10Check(nine string) string {
	sum := 0
	for i, r := range nine {
		sum += int(r-'0') * (10 - i)
	}
	check := (11 - sum%11) % 11
	if check == 10 {
		return "X"
	}
	return strconv.Itoa(check)
}

func TestISBN10And13ResolveToOneTitle(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	digits := fmt.Sprintf("%09d", rand.IntN(1_000_000_000)) //nolint:gosec // test data
	isbn10 := digits + isbn10Check(digits)
	isbn13 := core.NormalizeISBN(isbn10)
	require.NotEmpty(t, isbn13)
	fake := newFake()
	fake.stubTitle(Record{Hit: Hit{Type: core.MediaBook, Title: "A Book", Year: ptr(1965), IDs: core.ExternalIDs{ISBN: isbn13, OpenLibrary: "OL1W"}}})
	resolver := NewResolver(store, fake.providers())
	viaThirteen, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaBook, IDs: core.ExternalIDs{ISBN: isbn13}}, nil)
	require.NoError(t, err)
	viaTen, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaBook, IDs: core.ExternalIDs{ISBN: core.NormalizeISBN(isbn10)}}, nil)
	require.NoError(t, err)
	assert.Equal(t, viaThirteen.ID, viaTen.ID)
}

func TestMappedAnimeCoursResolveToOneShow(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	fake.stubTitle(Record{
		Hit:    Hit{Type: core.MediaShow, Title: "Long Anime", Year: ptr(2013), IDs: core.ExternalIDs{TMDB: "1429"}},
		Status: ptr(StatusEnded), RuntimeMinutes: ptr(24),
	})
	fake.stubTitle(Record{Hit: Hit{
		Type: core.MediaShow, Title: "Long Anime: Part 2 (AniList only)", Year: ptr(2014),
		IDs: core.ExternalIDs{AniList: "300"}, IsAnime: true,
	}, Status: ptr(StatusEnded), RuntimeMinutes: ptr(24)})
	require.NoError(t, store.UpsertMapping(ctx, AnimeMapping{AniList: "100", TMDB: ptr("1429"), TMDBSeason: ptr(1)}))
	require.NoError(t, store.UpsertMapping(ctx, AnimeMapping{AniList: "200", TMDB: ptr("1429"), TMDBSeason: ptr(2)}))
	resolver := NewResolver(store, fake.providers())
	resolve := func(anilist string) core.Title {
		title, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: anilist}}, nil)
		require.NoError(t, err)
		return title
	}
	first, second, separate := resolve("100"), resolve("200"), resolve("300")
	assert.Equal(t, first.ID, second.ID)
	assert.True(t, first.IsAnime)
	assert.NotEqual(t, first.ID, separate.ID)
}

func TestEpisodesHydrateOnceThenRefreshAfterTheWindow(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	show := core.Title{ID: uuid.New(), Type: core.MediaShow, Title: "Dormant Show", Year: ptr(2010), IDs: core.ExternalIDs{TMDB: "777"}}
	require.NoError(t, store.Insert(ctx, show, ptr(StatusEnded), nil, nil))
	longAgo := time.Unix(1_300_000_000, 0).UTC()
	fake.stubEpisodes("777", Episodes{Status: ptr(StatusEnded), Episodes: []Episode{{
		Season: 1, Episode: 1, Name: ptr("Pilot"), AirsAt: &longAgo, RuntimeMinutes: ptr(50),
		Overview: ptr("It begins."), StillURL: ptr("https://image.tmdb.org/t/p/w300/pilot.jpg"),
	}}})
	clock := &testClock{now: time.Now()}
	service := NewService(store, fake.providers())
	service.Now = clock.Now
	for range 2 {
		detail, err := service.Detail(ctx, show.ID)
		require.NoError(t, err)
		assert.Len(t, detail.Episodes, 1)
	}
	assert.Equal(t, 1, fake.callCount("episodes"), "second request served from Postgres")
	detail, err := service.Detail(ctx, show.ID)
	require.NoError(t, err)
	assert.Equal(t, "It begins.", *detail.Episodes[0].Overview)
	assert.Equal(t, "https://image.tmdb.org/t/p/w300/pilot.jpg", *detail.Episodes[0].StillURL)

	fake.stubEpisodes("777", Episodes{Status: ptr(StatusReturning), Episodes: []Episode{
		{Season: 1, Episode: 1, Name: ptr("Pilot"), AirsAt: &longAgo, RuntimeMinutes: ptr(50)},
		{Season: 2, Episode: 1, Name: ptr("Revival"), RuntimeMinutes: ptr(50)},
	}})
	clock.advance(DormantStaleness + time.Minute)
	refreshed, err := service.Detail(ctx, show.ID)
	require.NoError(t, err)
	assert.Equal(t, 2, fake.callCount("episodes"))
	require.Len(t, refreshed.Episodes, 2)
	assert.Equal(t, []int{1, 2}, []int{refreshed.Episodes[0].Season, refreshed.Episodes[1].Season})
	assert.Equal(t, StatusReturning, *refreshed.Status)
}
