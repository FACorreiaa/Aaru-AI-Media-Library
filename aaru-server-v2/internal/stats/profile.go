package stats

import (
	"aaru-go-api/internal/core"
	"time"

	"github.com/google/uuid"
)

// The profile's list lengths.
const (
	ProfileGenreCount       = 8
	ProfileNetworkCount     = 5
	ProfileMostWatchedCount = 3
)

// ProfileRow is GAM-006b: one library item as the profile counts it. Unlike Activity it is the
// library's state, not dated activity: every tick counts, imported and undated ones included.
type ProfileRow struct {
	TitleID uuid.UUID
	Type    core.MediaType
	IsAnime bool
	Status  core.LibraryStatus
	Rating  *float64
	// Episodes is every episode ticked.
	Episodes int
	// Minutes is the ticked episodes' runtime, plus the runtime of a finished film.
	Minutes int
	// Pages is a finished book's page count; 0 when unknown or not finished.
	Pages   int
	Genres  []string
	Network *string
}

// Counts are items per status for one kind.
type Counts struct {
	Wishlist, InProgress, OnHold, Finished, Dropped int
}

func (c *Counts) add(status core.LibraryStatus) {
	switch status {
	case core.StatusWishlist:
		c.Wishlist++
	case core.StatusInProgress:
		c.InProgress++
	case core.StatusOnHold:
		c.OnHold++
	case core.StatusFinished:
		c.Finished++
	case core.StatusDropped:
		c.Dropped++
	}
}

// ProfileStats is GAM-006b: all-time numbers for the profile, from the user's own library.
type ProfileStats struct {
	MemberSince                             *time.Time
	EpisodesWatched, MinutesWatched, PagesRead int
	Shows, Anime, Movies, Books             Counts
	// ByKind is movie, show, anime and book; Finished is the finished count.
	ByKind      []KindTotals
	TopGenres   []GenreTime
	TopNetworks []GenreTime
	MostWatched []TitleTime
	Ratings     Ratings
}

var profileKinds = []Kind{KindMovie, KindShow, KindAnime, KindBook}

// ProfileDigest is the profile's numbers, worked out from rows alone.
type ProfileDigest struct {
	stats       ProfileStats
	mostWatched []titleMinutes
	highest     *uuid.UUID
}

// NewProfileDigest digests the library rows.
func NewProfileDigest(rows []ProfileRow) ProfileDigest {
	d := ProfileDigest{}
	d.stats.Ratings.Distribution = make([]int, 10)
	for _, k := range profileKinds {
		d.stats.ByKind = append(d.stats.ByKind, KindTotals{Kind: k})
	}
	type ratedRow struct {
		titleID uuid.UUID
		rating  float64
	}
	var ratedRows []ratedRow
	// Albums and manga have no place in the profile's watch-and-read stats yet.
	for _, row := range rows {
		if row.Type == core.MediaAlbum || row.Type == core.MediaManga {
			continue
		}
		d.add(row)
		if row.Rating != nil {
			ratedRows = append(ratedRows, ratedRow{row.TitleID, *row.Rating})
			d.stats.Ratings.Distribution[RatingBin(*row.Rating)]++
		}
	}
	d.stats.Ratings.Count = len(ratedRows)
	if len(ratedRows) > 0 {
		sum := 0.0
		for _, r := range ratedRows {
			sum += r.rating
		}
		mean := sum / float64(len(ratedRows))
		d.stats.Ratings.Mean = &mean
		top := ratedRows[0]
		for _, r := range ratedRows[1:] {
			if r.rating > top.rating {
				top = r
			}
		}
		d.highest = &top.titleID
		d.stats.Ratings.HighestRating = &top.rating
	}
	var timed []ProfileRow
	for _, row := range rows {
		if row.Minutes > 0 && row.Type != core.MediaBook && row.Type != core.MediaAlbum {
			timed = append(timed, row)
		}
	}
	d.stats.TopGenres = profileShares(timed, func(row ProfileRow) []string { return row.Genres }, ProfileGenreCount)
	d.stats.TopNetworks = profileShares(timed, func(row ProfileRow) []string {
		if row.Network == nil {
			return nil
		}
		return []string{*row.Network}
	}, ProfileNetworkCount)
	most := make([]titleMinutes, 0, len(timed))
	for _, row := range timed {
		most = append(most, titleMinutes{titleID: row.TitleID, episodes: row.Episodes, minutes: row.Minutes})
	}
	sortByTime(most)
	d.mostWatched = most[:min(ProfileMostWatchedCount, len(most))]
	return d
}

// add counts one item's totals, its status under its kind, and its kind's time.
func (d *ProfileDigest) add(row ProfileRow) {
	d.stats.EpisodesWatched += row.Episodes
	d.stats.MinutesWatched += row.Minutes
	d.stats.PagesRead += row.Pages
	k := kind(row.Type, row.IsAnime)
	switch k {
	case KindAnime:
		d.stats.Anime.add(row.Status)
	case KindMovie:
		d.stats.Movies.add(row.Status)
	case KindBook:
		d.stats.Books.add(row.Status)
	default:
		k = KindShow
		d.stats.Shows.add(row.Status)
	}
	for i := range d.stats.ByKind {
		if d.stats.ByKind[i].Kind == k {
			d.stats.ByKind[i].Episodes += row.Episodes
			d.stats.ByKind[i].Minutes += row.Minutes
			if row.Status == core.StatusFinished {
				d.stats.ByKind[i].Finished++
			}
		}
	}
}

// TitleIDs are the titles shown: the most watched and the highest rated.
func (d ProfileDigest) TitleIDs() []uuid.UUID {
	var ids []uuid.UUID
	for _, t := range d.mostWatched {
		ids = append(ids, t.titleID)
	}
	if d.highest != nil {
		ids = append(ids, *d.highest)
	}
	return ids
}

// Stats is the profile with the shown titles filled in.
func (d ProfileDigest) Stats(titles map[uuid.UUID]core.Title, memberSince *time.Time) ProfileStats {
	s := d.stats
	s.MemberSince = memberSince
	s.MostWatched = nil
	for _, t := range d.mostWatched {
		if title, ok := titles[t.titleID]; ok {
			s.MostWatched = append(s.MostWatched, TitleTime{Title: title, Episodes: t.episodes, Minutes: t.minutes})
		}
	}
	if d.highest != nil {
		if title, ok := titles[*d.highest]; ok {
			s.Ratings.Highest = &title
		}
	}
	return s
}

// profileShares is time per name, most first, then by titles, then name.
func profileShares(rows []ProfileRow, names func(ProfileRow) []string, limit int) []GenreTime {
	type acc struct {
		minutes int
		titles  map[uuid.UUID]bool
	}
	per := map[string]*acc{}
	for _, row := range rows {
		seen := map[string]bool{}
		for _, name := range names(row) {
			if seen[name] {
				continue
			}
			seen[name] = true
			a := per[name]
			if a == nil {
				a = &acc{titles: map[uuid.UUID]bool{}}
				per[name] = a
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
	return out[:min(limit, len(out))]
}
