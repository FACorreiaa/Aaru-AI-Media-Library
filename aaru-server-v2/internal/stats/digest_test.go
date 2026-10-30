package stats

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ported from StatsTests.swift (StatsDigestTests), StatsTests+Rolling.swift and
// StatsTests+YearReview.swift: the pure parts.

func day(t *testing.T, text string) LocalDay {
	t.Helper()
	d, ok := ParseDay(text)
	require.True(t, ok, text)
	return d
}

type rowOpt func(*Activity)

func typ(m core.MediaType) rowOpt { return func(a *Activity) { a.Type = m } }
func anime() rowOpt               { return func(a *Activity) { a.IsAnime = true } }
func eps(n int) rowOpt            { return func(a *Activity) { a.Episodes = n } }
func mins(n int) rowOpt           { return func(a *Activity) { a.Minutes = n } }
func finished() rowOpt            { return func(a *Activity) { a.Finished = true } }
func rating(r float64) rowOpt     { return func(a *Activity) { a.Rating = &r } }
func genres(g ...string) rowOpt   { return func(a *Activity) { a.Genres = g } }

func row(t *testing.T, d string, id uuid.UUID, opts ...rowOpt) Activity {
	t.Helper()
	noon, err := time.Parse(time.RFC3339, d+"T12:00:00Z")
	require.NoError(t, err)
	a := Activity{Day: day(t, d), TitleID: id, Type: core.MediaShow, FirstAt: noon, LastAt: noon}
	for _, o := range opts {
		o(&a)
	}
	return a
}

func year2026() Period { return CalendarPeriod(2026, nil, time.UTC) }

func intp(v int) *int { return &v }

func TestBuckets(t *testing.T) {
	assert.Len(t, CalendarPeriod(2026, nil, time.UTC).BucketStarts(), 12)
	assert.Len(t, CalendarPeriod(2028, intp(2), time.UTC).BucketStarts(), 29)
	assert.Equal(t, day(t, "2027-01-01"), CalendarPeriod(2026, intp(12), time.UTC).End)
	assert.Equal(t, day(t, "2027-01-01"), day(t, "2026-12-31").Adding(1, 0))
}

func TestLongestRun(t *testing.T) {
	var days []LocalDay
	for _, d := range []string{"2026-01-30", "2026-01-31", "2026-02-01", "2026-03-01", "2026-03-02", "2026-03-03"} {
		days = append(days, day(t, d))
	}
	assert.Equal(t, &Run{Days: 3, Start: day(t, "2026-01-30"), End: day(t, "2026-02-01")}, LongestRun(days))
	assert.Nil(t, LongestRun(nil))
}

func TestDigest(t *testing.T) {
	show, an, movie, book := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	rows := []Activity{
		row(t, "2026-03-10", show, eps(2), mins(90)),
		row(t, "2026-03-11", an, anime(), eps(3), mins(72), finished(), rating(9)),
		row(t, "2026-07-04", movie, typ(core.MediaMovie), mins(120), finished(), rating(6)),
		row(t, "2026-07-05", book, typ(core.MediaBook), finished()),
	}
	d := NewDigest(rows, year2026(), day(t, "2026-10-16"))
	assert.True(t, d.isPartial)
	assert.Equal(t, Totals{
		EpisodesWatched: 5, MinutesWatched: 282, ActiveDays: 4, MoviesFinished: 1, AnimeFinished: 1, BooksFinished: 1,
	}, d.totals)
	// A book takes no time, so it is not a top title.
	var top []uuid.UUID
	for _, tt := range d.topTitles {
		top = append(top, tt.titleID)
	}
	assert.Equal(t, []uuid.UUID{movie, show, an}, top)
	assert.Equal(t, 2, d.ratingCount)
	assert.InDelta(t, 7.5, *d.ratingMean, 1e-9)
	assert.Equal(t, an, d.highest.titleID)
	assert.Equal(t, show, d.first.titleID)
	assert.Equal(t, book, d.last.titleID)

	titles := map[uuid.UUID]core.Title{}
	for _, id := range []uuid.UUID{show, an, movie, book} {
		titles[id] = core.Title{ID: id, Type: core.MediaShow, Title: id.String()}
	}
	s := d.Stats(titles)
	assert.Equal(t, day(t, "2026-03-01"), s.Busiest.Start, "162 minutes beat July's 120")
	assert.Equal(t, day(t, "2026-03-01"), s.MostEpisodes.Start)
	assert.Equal(t, 2, s.Buckets[6].Finished)
	assert.Equal(t, 2, s.LongestRun.Days)

	done := NewDigest(nil, CalendarPeriod(2025, nil, time.UTC), day(t, "2026-10-16"))
	assert.False(t, done.isPartial)
	assert.Nil(t, done.Stats(nil).Busiest)
	assert.Nil(t, done.Stats(nil).MostEpisodes)
}

func TestMostEpisodes(t *testing.T) {
	b := func(d string, episodes, minutes int) Bucket {
		return Bucket{Start: day(t, d), Episodes: episodes, Minutes: minutes}
	}
	// Time and episodes disagree: a 166-minute film month loses on episodes.
	film, binge := b("2026-02-01", 1, 166), b("2026-06-01", 6, 144)
	assert.Equal(t, &binge, MostEpisodes([]Bucket{film, binge}))
	assert.Nil(t, MostEpisodes([]Bucket{b("2026-04-03", 1, 0), b("2026-04-04", 1, 0)}))
	assert.Nil(t, MostEpisodes([]Bucket{b("2026-04-03", 0, 0)}))
}

func TestByKind(t *testing.T) {
	rows := []Activity{
		row(t, "2026-03-10", uuid.New(), eps(2), mins(90)),
		row(t, "2026-03-11", uuid.New(), typ(core.MediaMovie), anime(), mins(72), finished(), rating(9)),
		row(t, "2026-07-04", uuid.New(), typ(core.MediaMovie), mins(120), finished(), rating(7.5)),
		row(t, "2026-07-05", uuid.New(), typ(core.MediaBook), finished(), rating(1)),
	}
	d := NewDigest(rows, year2026(), day(t, "2026-10-16"))
	// No album finished, so no album row: clients from before MUS-001 know four kinds.
	assert.Equal(t, []KindTotals{
		{Kind: KindMovie, Minutes: 120, Finished: 1},
		{Kind: KindShow, Episodes: 2, Minutes: 90},
		{Kind: KindAnime, Minutes: 72, Finished: 1},
		{Kind: KindBook, Finished: 1},
	}, d.Stats(nil).ByKind)
	sum := 0
	for _, k := range d.byKind {
		sum += k.Minutes
	}
	assert.Equal(t, d.totals.MinutesWatched, sum)
	assert.Equal(t, []int{1, 0, 0, 0, 0, 0, 0, 1, 1, 0}, d.distribution)
}

func TestAlbums(t *testing.T) {
	album, movie := uuid.New(), uuid.New()
	d := NewDigest([]Activity{
		row(t, "2026-07-04", movie, typ(core.MediaMovie), mins(120), finished()),
		row(t, "2026-07-05", album, typ(core.MediaAlbum), finished(), rating(8)),
	}, year2026(), day(t, "2026-10-16"))
	assert.Equal(t, 1, d.totals.AlbumsFinished)
	assert.Equal(t, 120, d.totals.MinutesWatched)
	kinds := d.Stats(nil).ByKind
	assert.Equal(t, KindTotals{Kind: KindAlbum, Finished: 1}, kinds[len(kinds)-1])
	require.Len(t, d.topTitles, 1, "an album takes no time")
	assert.Equal(t, movie, d.topTitles[0].titleID)
}

func TestRatingBins(t *testing.T) {
	var bins []int
	for _, r := range []float64{1, 1.5, 2, 7.5, 8, 9.5, 10} {
		bins = append(bins, RatingBin(r))
	}
	assert.Equal(t, []int{0, 1, 1, 7, 7, 9, 9}, bins)
}

func TestAllTimePeriod(t *testing.T) {
	p := AllTimeUntil(day(t, "2026-10-16"), time.UTC)
	assert.Equal(t, SpanAll, p.Span)
	assert.Equal(t, 2026, p.Year)
	assert.Equal(t, FirstDay, p.Start)
	assert.Equal(t, day(t, "2027-01-01"), p.End)
	assert.Equal(t, []LocalDay{day(t, "2026-01-01")}, p.BucketStarts(), "no activity: this year alone")
	p.FirstYear = 2024
	assert.Equal(t, []LocalDay{day(t, "2024-01-01"), day(t, "2025-01-01"), day(t, "2026-01-01")}, p.BucketStarts())
	assert.Equal(t, day(t, "2025-01-01"), p.Bucket(day(t, "2025-06-03")))
	d := NewDigest([]Activity{row(t, "2024-02-10", uuid.New(), eps(1))}, p, day(t, "2026-10-16"))
	assert.True(t, d.isPartial)
	var episodes []int
	for _, b := range d.buckets {
		episodes = append(episodes, b.Episodes)
	}
	assert.Equal(t, []int{1, 0, 0}, episodes)
}

func detail(t *testing.T, err error, field string) bool {
	t.Helper()
	var e *apperr.Error
	if !errors.As(err, &e) {
		return false
	}
	_, ok := e.Details[field]
	return ok && e.Status == 422
}

func TestSpanValidation(t *testing.T) {
	now := time.Now()
	all := SpanAll
	for _, c := range []struct{ year, month *int }{{intp(2026), nil}, {nil, intp(3)}, {intp(2026), intp(3)}} {
		_, err := PeriodFor(&all, c.year, c.month, nil, now)
		assert.True(t, detail(t, err, "span"))
	}
	_, err := PeriodFor(nil, nil, intp(3), nil, now)
	assert.True(t, detail(t, err, "year"))
	lisbon := "Europe/Lisbon"
	p, err := PeriodFor(&all, nil, nil, &lisbon, now)
	require.NoError(t, err)
	assert.Equal(t, SpanAll, p.Span)
	assert.Equal(t, "Europe/Lisbon", p.TimeZone.String())
}

func TestValidation(t *testing.T) {
	for _, c := range []struct {
		year  int
		month *int
		zone  string
		field string
	}{
		{2026, intp(13), "UTC", "month"},
		{1200, nil, "UTC", "year"},
		{2026, nil, "Mars/Olympus", "tz"},
	} {
		_, err := CalendarPeriodFor(c.year, c.month, &c.zone)
		assert.True(t, detail(t, err, c.field), c.field)
	}
}

func TestRollingPeriod(t *testing.T) {
	week := LastDays(SpanLast7, day(t, "2026-10-21"), time.UTC)
	assert.Equal(t, day(t, "2026-10-15"), week.Start)
	assert.Equal(t, day(t, "2026-10-22"), week.End)
	assert.Equal(t, day(t, "2026-10-21"), week.LastDay())
	assert.Len(t, week.BucketStarts(), 7)
	assert.Equal(t, day(t, "2026-10-17"), week.Bucket(day(t, "2026-10-17")))
	prior := week.Previous()
	require.NotNil(t, prior)
	assert.Equal(t, day(t, "2026-10-08"), prior.Start)
	assert.Equal(t, day(t, "2026-10-15"), prior.End)
	assert.Len(t, prior.BucketStarts(), 7)

	month := LastDays(SpanLast30, day(t, "2027-01-03"), time.UTC)
	assert.Equal(t, day(t, "2026-12-05"), month.Start)
	assert.Len(t, month.BucketStarts(), 30)
	assert.Equal(t, 2027, month.Year, "the last year the window touches")
	assert.Nil(t, CalendarPeriod(2026, intp(3), time.UTC).Previous())

	d := NewDigest([]Activity{row(t, "2026-10-15", uuid.New(), eps(1)), row(t, "2026-10-21", uuid.New(), eps(2))}, week, day(t, "2026-10-21"))
	assert.True(t, d.isPartial)
	var episodes []int
	for _, b := range d.buckets {
		episodes = append(episodes, b.Episodes)
	}
	assert.Equal(t, []int{1, 0, 0, 0, 0, 0, 2}, episodes)
}

func TestRollingValidation(t *testing.T) {
	now := time.Now()
	for _, span := range []Span{SpanLast7, SpanLast30} {
		_, err := PeriodFor(&span, intp(2026), nil, nil, now)
		assert.True(t, detail(t, err, "span"))
	}
	tokyo := "Asia/Tokyo"
	last30 := SpanLast30
	p, err := PeriodFor(&last30, nil, nil, &tokyo, now)
	require.NoError(t, err)
	assert.Equal(t, SpanLast30, p.Span)
	assert.Equal(t, DayOf(now, p.TimeZone), p.LastDay())
}

func TestTopGenres(t *testing.T) {
	g := func(d string, id uuid.UUID, m core.MediaType, minutes int, names ...string) Activity {
		e := 0
		if m == core.MediaShow {
			e = 1
		}
		return row(t, d, id, typ(m), eps(e), mins(minutes), genres(names...))
	}
	rows := []Activity{
		g("2026-02-01", uuid.New(), core.MediaShow, 100, "Drama", "Mystery"),
		g("2026-02-02", uuid.New(), core.MediaShow, 50, "Drama", "Comedy"),
		g("2026-02-03", uuid.New(), core.MediaShow, 50, "Comedy", "Crime"),
		g("2026-02-04", uuid.New(), core.MediaShow, 500),
		g("2026-02-05", uuid.New(), core.MediaBook, 0, "Fiction"),
	}
	d := NewDigest(rows, year2026(), day(t, "2026-12-31"))
	assert.Equal(t, []GenreTime{
		{Name: "Drama", Minutes: 150, Titles: 2},
		{Name: "Comedy", Minutes: 100, Titles: 2},
		{Name: "Mystery", Minutes: 100, Titles: 1},
	}, d.topGenres)
}

func TestBiggestDay(t *testing.T) {
	show := uuid.New()
	rows := []Activity{
		row(t, "2026-03-01", show, eps(2), mins(90)),
		row(t, "2026-03-05", show, eps(3), mins(90)),
		row(t, "2026-04-01", show, eps(1), mins(45)),
		row(t, "2026-04-02", uuid.New(), typ(core.MediaBook), finished()),
	}
	d := NewDigest(rows, year2026(), day(t, "2026-12-31"))
	// 90 minutes twice: more episodes wins.
	assert.Equal(t, day(t, "2026-03-05"), d.biggestDay.Start)
	assert.Equal(t, day(t, "2026-05-01"), BiggestDay([]Bucket{
		{Start: day(t, "2026-05-02"), Episodes: 1, Minutes: 30},
		{Start: day(t, "2026-05-01"), Episodes: 1, Minutes: 30},
	}).Start)
	assert.Nil(t, BiggestDay([]Bucket{{Start: day(t, "2026-05-01"), Finished: 1}}))
}

func TestPersona(t *testing.T) {
	persona := func(rows []Activity) *Persona {
		return NewDigest(rows, year2026(), day(t, "2026-12-31")).Persona()
	}
	is := func(want Persona, rows []Activity, msg ...any) {
		t.Helper()
		got := persona(rows)
		if assert.NotNil(t, got, msg...) {
			assert.Equal(t, want, *got, msg...)
		}
	}
	show := uuid.New()
	assert.Nil(t, persona(nil))
	is(PersonaBinger, []Activity{row(t, "2026-01-10", show, eps(6), mins(270))})
	var fortnight []Activity
	for i := 1; i <= 14; i++ {
		fortnight = append(fortnight, row(t, fmt.Sprintf("2026-06-%02d", i), show, eps(1), mins(45)))
	}
	is(PersonaBinger, fortnight)
	books := []Activity{
		row(t, "2026-02-01", uuid.New(), typ(core.MediaBook), finished()),
		row(t, "2026-02-02", uuid.New(), typ(core.MediaBook), finished()),
	}
	is(PersonaBookworm, append(books, row(t, "2026-02-03", uuid.New(), typ(core.MediaMovie), mins(100), finished())))
	is(PersonaSteady, []Activity{row(t, "2026-02-01", uuid.New(), typ(core.MediaBook), finished())}, "one book is not a habit")
	is(PersonaAnime, []Activity{
		row(t, "2026-03-01", uuid.New(), anime(), eps(2), mins(48)),
		row(t, "2026-03-02", uuid.New(), typ(core.MediaMovie), mins(40), finished()),
	})
	var finishes, spread []Activity
	for i := 1; i <= 24; i++ {
		finishes = append(finishes, row(t, fmt.Sprintf("2026-05-%02d", i), uuid.New(), typ(core.MediaMovie), mins(90), finished()))
	}
	is(PersonaBinger, finishes, "24 days in a row is a run before it is a count")
	for i := range 24 {
		spread = append(spread, row(t, day(t, "2026-01-01").Adding(i*2, 0).String(), uuid.New(), typ(core.MediaMovie), mins(90), finished()))
	}
	is(PersonaCompletionist, spread)
	is(PersonaExplorer, []Activity{
		row(t, "2026-07-01", uuid.New(), typ(core.MediaMovie), mins(90), finished()),
		row(t, "2026-07-03", uuid.New(), eps(1), mins(45)),
		row(t, "2026-07-05", uuid.New(), typ(core.MediaBook), finished()),
	})
	is(PersonaSteady, []Activity{row(t, "2026-07-01", show, eps(1), mins(45))})
}

func TestFold(t *testing.T) {
	assert.Equal(t, "massive attack", fold("  Massive   ATTACK "))
	assert.Equal(t, "abc", fold("ＡＢＣ"), "width-folded")
}

func TestAddingMonthsClamps(t *testing.T) {
	assert.Equal(t, day(t, "2026-02-28"), day(t, "2026-01-31").Adding(0, 1))
	assert.Equal(t, day(t, "2025-12-01"), day(t, "2026-01-01").Adding(0, -1))
}
