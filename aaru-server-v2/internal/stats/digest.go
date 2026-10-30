package stats

import (
	"aaru-go-api/internal/core"
	"cmp"
	"math"
	"slices"
	"time"

	"github.com/google/uuid"
)

// TopTitleCount is how many titles a period shows.
const TopTitleCount = 5

// TopGenreCount is how many genres a period shows (GAM-006e).
const TopGenreCount = 3

// Activity is one title's activity on one local day: episode ticks with known dates, and its
// finish if it finished that day. Imported or restored ticks are never activity.
type Activity struct {
	Day      LocalDay
	TitleID  uuid.UUID
	Type     core.MediaType
	IsAnime  bool
	Rating   *float64
	Episodes int
	Minutes  int
	Finished bool
	FirstAt  time.Time
	LastAt   time.Time
	// Genres are the title's stored genres (CAT-018); empty for books and titles not yet filled.
	Genres []string
}

// Totals are a period's sums.
type Totals struct {
	EpisodesWatched, MinutesWatched, ActiveDays                          int
	MoviesFinished, ShowsFinished, AnimeFinished, BooksFinished          int
	AlbumsFinished, MangaFinished                                        int
}

// Bucket is one month, day or year of a period.
type Bucket struct {
	Start                       LocalDay
	Episodes, Minutes, Finished int
}

func (b Bucket) isEmpty() bool { return b.Episodes == 0 && b.Minutes == 0 && b.Finished == 0 }

// Run is a stretch of consecutive active days.
type Run struct {
	Days       int
	Start, End LocalDay
}

// TitleTime is one title's time in a period.
type TitleTime struct {
	Title             core.Title
	Episodes, Minutes int
}

// Ratings are the ratings of titles finished in a period (or, for the profile, every rated item).
type Ratings struct {
	Count         int
	Mean          *float64
	Highest       *core.Title
	HighestRating *float64
	// Distribution is ten bins on the 1–10 scale: bin n holds ratings in (n, n + 1].
	Distribution []int
}

// Kind is the kind a person counts in: anime is its own kind, whatever its type.
type Kind string

// The kinds, in order.
const (
	KindMovie Kind = "movie"
	KindShow  Kind = "show"
	KindAnime Kind = "anime"
	KindBook  Kind = "book"
	KindAlbum Kind = "album"
	KindManga Kind = "manga"
)

var allKinds = []Kind{KindMovie, KindShow, KindAnime, KindBook, KindAlbum, KindManga}

// KindTotals are one kind's sums.
type KindTotals struct {
	Kind                        Kind
	Episodes, Minutes, Finished int
}

// Moment is a title at an instant (the period's first and last).
type Moment struct {
	Title core.Title
	At    time.Time
}

// GenreTime is GAM-006e: time spent in one genre, and how many titles carried it.
type GenreTime struct {
	Name           string
	Minutes, Titles int
}

// Persona is GAM-006e: one word for how the period went. The first rule that holds wins.
type Persona string

// The personas, in rule order.
const (
	PersonaBinger        Persona = "binger"
	PersonaBookworm      Persona = "bookworm"
	PersonaAnime         Persona = "anime"
	PersonaCompletionist Persona = "completionist"
	PersonaExplorer      Persona = "explorer"
	PersonaSteady        Persona = "steady"
)

// PeriodStats is GAM-006a/c: what one user watched and read in a period.
type PeriodStats struct {
	Period    Period
	IsPartial bool
	Totals    Totals
	// Prior is the previous equal-length window's totals; rolling spans only (GAM-006d).
	Prior *Totals
	// ByKind is movie, show, anime and book, always; album and manga only when the period
	// finished one. They sum to Totals.
	ByKind       []KindTotals
	Buckets      []Bucket
	Busiest      *Bucket
	MostEpisodes *Bucket
	LongestRun   *Run
	TopTitles    []TitleTime
	Ratings      Ratings
	First, Last  *Moment
	TopGenres    []GenreTime
	BiggestDay   *Bucket
	Persona      *Persona
	// Music is MUS-008's listening, apart from the library's numbers; nil when nothing was heard.
	Music *ListenSummary
}

type titleMinutes struct {
	titleID           uuid.UUID
	episodes, minutes int
}

type rated struct {
	titleID uuid.UUID
	rating  float64
	at      time.Time
}

type mark struct {
	titleID uuid.UUID
	at      time.Time
}

// Digest is everything the stats need, computed from activity rows alone. Titles are looked up
// after, only for the few that are shown.
type Digest struct {
	period       Period
	isPartial    bool
	totals       Totals
	byKind       []KindTotals
	distribution []int
	buckets      []Bucket
	longestRun   *Run
	topTitles    []titleMinutes
	ratingCount  int
	ratingMean   *float64
	highest      *rated
	first, last  *mark
	topGenres    []GenreTime
	biggestDay   *Bucket
}

// NewDigest digests the rows of one period.
func NewDigest(rows []Activity, period Period, today LocalDay) Digest {
	d := Digest{period: period, isPartial: today.Less(period.End), distribution: make([]int, 10)}
	for _, k := range allKinds {
		d.byKind = append(d.byKind, KindTotals{Kind: k})
	}
	starts := period.BucketStarts()
	buckets := make(map[LocalDay]*Bucket, len(starts))
	for _, s := range starts {
		buckets[s] = &Bucket{Start: s}
	}
	perTitle := map[uuid.UUID]*titleMinutes{}
	var ratings []rated
	days := map[LocalDay]bool{}
	for _, row := range rows {
		days[row.Day] = true
		d.totals.EpisodesWatched += row.Episodes
		d.totals.MinutesWatched += row.Minutes
		k := kindIndex(row.Type, row.IsAnime)
		d.byKind[k].Episodes += row.Episodes
		d.byKind[k].Minutes += row.Minutes
		b := buckets[period.Bucket(row.Day)]
		if b != nil {
			b.Episodes += row.Episodes
			b.Minutes += row.Minutes
		}
		if row.Episodes > 0 || row.Minutes > 0 {
			t := perTitle[row.TitleID]
			if t == nil {
				t = &titleMinutes{titleID: row.TitleID}
				perTitle[row.TitleID] = t
			}
			t.episodes += row.Episodes
			t.minutes += row.Minutes
		}
		if row.Finished {
			if b != nil {
				b.Finished++
			}
			d.byKind[k].Finished++
			countFinish(row.Type, row.IsAnime, &d.totals)
			if row.Rating != nil {
				ratings = append(ratings, rated{titleID: row.TitleID, rating: *row.Rating, at: row.LastAt})
				d.distribution[RatingBin(*row.Rating)]++
			}
		}
		if d.first == nil || row.FirstAt.Before(d.first.at) {
			d.first = &mark{row.TitleID, row.FirstAt}
		}
		if d.last == nil || !row.LastAt.Before(d.last.at) {
			d.last = &mark{row.TitleID, row.LastAt}
		}
	}
	for _, s := range starts {
		d.buckets = append(d.buckets, *buckets[s])
	}
	d.totals.ActiveDays = len(days)
	dayList := make([]LocalDay, 0, len(days))
	for day := range days {
		dayList = append(dayList, day)
	}
	d.longestRun = LongestRun(dayList)
	titles := make([]titleMinutes, 0, len(perTitle))
	for _, t := range perTitle {
		titles = append(titles, *t)
	}
	sortByTime(titles)
	d.topTitles = titles[:min(TopTitleCount, len(titles))]
	d.ratingCount = len(ratings)
	if len(ratings) > 0 {
		sum := 0.0
		for _, r := range ratings {
			sum += r.rating
		}
		mean := sum / float64(len(ratings))
		d.ratingMean = &mean
	}
	// The highest rating; among ties, the latest finish (the first such in row order).
	for i := range ratings {
		r := ratings[i]
		if d.highest == nil || r.rating > d.highest.rating || (r.rating == d.highest.rating && r.at.After(d.highest.at)) {
			d.highest = &r
		}
	}
	d.topGenres = TopGenres(rows)
	d.biggestDay = BiggestDay(Days(rows))
	return d
}

// sortByTime is most minutes, then episodes, then the title id's text, ascending.
func sortByTime(titles []titleMinutes) {
	slices.SortFunc(titles, func(a, b titleMinutes) int {
		if c := cmp.Compare(b.minutes, a.minutes); c != 0 {
			return c
		}
		if c := cmp.Compare(b.episodes, a.episodes); c != 0 {
			return c
		}
		return cmp.Compare(a.titleID.String(), b.titleID.String())
	})
}

// TopGenres is GAM-006e: time per genre over everything but books, most first, then by titles,
// then name.
func TopGenres(rows []Activity) []GenreTime {
	type acc struct {
		minutes int
		titles  map[uuid.UUID]bool
	}
	per := map[string]*acc{}
	for _, row := range rows {
		if row.Minutes <= 0 || row.Type == core.MediaBook {
			continue
		}
		seen := map[string]bool{}
		for _, g := range row.Genres {
			if seen[g] {
				continue
			}
			seen[g] = true
			a := per[g]
			if a == nil {
				a = &acc{titles: map[uuid.UUID]bool{}}
				per[g] = a
			}
			a.minutes += row.Minutes
			a.titles[row.TitleID] = true
		}
	}
	out := make([]GenreTime, 0, len(per))
	for name, a := range per {
		out = append(out, GenreTime{Name: name, Minutes: a.minutes, Titles: len(a.titles)})
	}
	sortShares(out)
	return out[:min(TopGenreCount, len(out))]
}

// sortShares is most minutes, then titles, then name.
func sortShares(out []GenreTime) {
	slices.SortFunc(out, func(a, b GenreTime) int {
		if c := cmp.Compare(b.Minutes, a.Minutes); c != 0 {
			return c
		}
		if c := cmp.Compare(b.Titles, a.Titles); c != 0 {
			return c
		}
		return cmp.Compare(a.Name, b.Name)
	})
}

// Days are each active local day's totals.
func Days(rows []Activity) []Bucket {
	per := map[LocalDay]*Bucket{}
	var order []LocalDay
	for _, row := range rows {
		b := per[row.Day]
		if b == nil {
			b = &Bucket{Start: row.Day}
			per[row.Day] = b
			order = append(order, row.Day)
		}
		b.Episodes += row.Episodes
		b.Minutes += row.Minutes
		if row.Finished {
			b.Finished++
		}
	}
	out := make([]Bucket, 0, len(order))
	for _, d := range order {
		out = append(out, *per[d])
	}
	return out
}

// BiggestDay is the day with the most time, then episodes; the earliest among equals. Nil with
// no time and no episodes (a day of finished books alone is not a big day).
func BiggestDay(days []Bucket) *Bucket {
	var best *Bucket
	for i := range days {
		b := days[i]
		if b.Minutes <= 0 && b.Episodes <= 0 {
			continue
		}
		if best == nil || b.Minutes > best.Minutes ||
			(b.Minutes == best.Minutes && (b.Episodes > best.Episodes ||
				(b.Episodes == best.Episodes && b.Start.Less(best.Start)))) {
			best = &b
		}
	}
	return best
}

// Persona is GAM-006e: the first persona whose rule holds; nil when nothing happened.
func (d Digest) Persona() *Persona {
	t := d.totals
	finished := t.MoviesFinished + t.ShowsFinished + t.AnimeFinished + t.BooksFinished + t.AlbumsFinished
	if t.ActiveDays == 0 {
		return nil
	}
	p := func(v Persona) *Persona { return &v }
	if (d.biggestDay != nil && d.biggestDay.Episodes >= 6) || (d.longestRun != nil && d.longestRun.Days >= 14) {
		return p(PersonaBinger)
	}
	if finished >= 2 && t.BooksFinished*2 > finished {
		return p(PersonaBookworm)
	}
	anime := d.byKind[kindIndex(core.MediaShow, true)].Minutes
	if t.MinutesWatched > 0 && anime*2 > t.MinutesWatched {
		return p(PersonaAnime)
	}
	if finished >= 24 {
		return p(PersonaCompletionist)
	}
	kinds := 0
	for _, k := range d.byKind {
		if k.Minutes > 0 || k.Finished > 0 {
			kinds++
		}
	}
	if kinds >= 3 {
		return p(PersonaExplorer)
	}
	return p(PersonaSteady)
}

// kind is the kind a type counts in: anime is anime whatever its type.
func kind(t core.MediaType, anime bool) Kind {
	switch {
	case anime:
		return KindAnime
	case t == core.MediaMovie:
		return KindMovie
	case t == core.MediaBook:
		return KindBook
	case t == core.MediaAlbum:
		return KindAlbum
	case t == core.MediaManga:
		return KindManga
	default:
		return KindShow
	}
}

func kindIndex(t core.MediaType, anime bool) int {
	return max(0, slices.Index(allKinds, kind(t, anime)))
}

// RatingBin is the histogram bin of a 1–10 rating: (n, n + 1] is bin n, so half stars round up.
func RatingBin(rating float64) int {
	return min(9, max(0, int(math.Ceil(rating))-1))
}

func countFinish(t core.MediaType, anime bool, totals *Totals) {
	switch kind(t, anime) {
	case KindAnime:
		totals.AnimeFinished++
	case KindMovie:
		totals.MoviesFinished++
	case KindShow:
		totals.ShowsFinished++
	case KindBook:
		totals.BooksFinished++
	case KindAlbum:
		totals.AlbumsFinished++
	case KindManga:
		totals.MangaFinished++
	}
}

// MostEpisodes is the one bucket with the most episodes. A shared top count names no winner.
func MostEpisodes(buckets []Bucket) *Bucket {
	var top *Bucket
	for i := range buckets {
		if top == nil || buckets[i].Episodes > top.Episodes {
			b := buckets[i]
			top = &b
		}
	}
	if top == nil || top.Episodes <= 0 {
		return nil
	}
	shared := 0
	for _, b := range buckets {
		if b.Episodes == top.Episodes {
			shared++
		}
	}
	if shared != 1 {
		return nil
	}
	return top
}

// LongestRun is the longest stretch of consecutive active days; the earliest among equals.
func LongestRun(days []LocalDay) *Run {
	sorted := slices.Clone(days)
	slices.SortFunc(sorted, func(a, b LocalDay) int {
		switch {
		case a.Less(b):
			return -1
		case b.Less(a):
			return 1
		default:
			return 0
		}
	})
	var best, current *Run
	for _, day := range sorted {
		if current != nil && current.End.Adding(1, 0) == day {
			current = &Run{Days: current.Days + 1, Start: current.Start, End: day}
		} else {
			current = &Run{Days: 1, Start: day, End: day}
		}
		if best == nil || current.Days > best.Days {
			r := *current
			best = &r
		}
	}
	return best
}

// TitleIDs are the titles the stats show: the top list, the highest rated, the first and the last.
func (d Digest) TitleIDs() []uuid.UUID {
	var ids []uuid.UUID
	for _, t := range d.topTitles {
		ids = append(ids, t.titleID)
	}
	if d.highest != nil {
		ids = append(ids, d.highest.titleID)
	}
	if d.first != nil {
		ids = append(ids, d.first.titleID)
	}
	if d.last != nil {
		ids = append(ids, d.last.titleID)
	}
	seen := map[uuid.UUID]bool{}
	out := ids[:0]
	for _, id := range ids {
		if !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}

// Totals are the digest's sums.
func (d Digest) Totals() Totals { return d.totals }

// Stats is the period's stats with the shown titles filled in.
func (d Digest) Stats(titles map[uuid.UUID]core.Title) PeriodStats {
	s := PeriodStats{
		Period: d.period, IsPartial: d.isPartial, Totals: d.totals, Buckets: d.buckets,
		MostEpisodes: MostEpisodes(d.buckets), LongestRun: d.longestRun, TopGenres: d.topGenres,
		BiggestDay: d.biggestDay, Persona: d.Persona(),
	}
	// Old clients know four kinds; an album or manga row appears only once there is one to show.
	for _, k := range d.byKind {
		if (k.Kind != KindAlbum && k.Kind != KindManga) || k.Finished > 0 {
			s.ByKind = append(s.ByKind, k)
		}
	}
	for i := range d.buckets {
		b := d.buckets[i]
		if b.isEmpty() {
			continue
		}
		if s.Busiest == nil || b.Minutes > s.Busiest.Minutes ||
			(b.Minutes == s.Busiest.Minutes && (b.Episodes > s.Busiest.Episodes ||
				(b.Episodes == s.Busiest.Episodes && b.Finished > s.Busiest.Finished))) {
			s.Busiest = &b
		}
	}
	for _, t := range d.topTitles {
		if title, ok := titles[t.titleID]; ok {
			s.TopTitles = append(s.TopTitles, TitleTime{Title: title, Episodes: t.episodes, Minutes: t.minutes})
		}
	}
	s.Ratings = Ratings{Count: d.ratingCount, Mean: d.ratingMean, Distribution: d.distribution}
	if d.highest != nil {
		if title, ok := titles[d.highest.titleID]; ok {
			s.Ratings.Highest = &title
		}
		r := d.highest.rating
		s.Ratings.HighestRating = &r
	}
	s.First = moment(d.first, titles)
	s.Last = moment(d.last, titles)
	return s
}

func moment(m *mark, titles map[uuid.UUID]core.Title) *Moment {
	if m == nil {
		return nil
	}
	title, ok := titles[m.titleID]
	if !ok {
		return nil
	}
	return &Moment{Title: title, At: m.at}
}
