package imports

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"
	"unicode"
)

// Any other site's CSV (Simkl, Serializd, StoryGraph, a spreadsheet; GenericCSVParser): columns
// are found by common names, so a file needs only a title (and ideally a year) or an id. Rows
// match by id first, then title + year through the catalog, exactly like the named sources.

type genericField int

const (
	gfTitle genericField = iota
	gfYear
	gfType
	gfIMDb
	gfTMDB
	gfTVDB
	gfISBN
	gfMAL
	gfAniList
	gfAuthor
	gfStatus
	gfRating
	gfFinished
	genericFieldCount
)

// genericAliases are the accepted column names, compared without case, spaces, `_` or `-`.
var genericAliases = map[genericField][]string{
	gfTitle: {"title", "name", "seriestitle", "showtitle", "movietitle", "booktitle", "show", "movie", "book"},
	gfYear: {
		"year", "releaseyear", "released", "releasedate", "firstairdate", "airdate", "publicationyear",
		"originalpublicationyear", "yearpublished",
	},
	gfType:    {"type", "mediatype", "kind", "category", "format", "titletype"},
	gfIMDb:    {"imdb", "imdbid", "const", "tconst"},
	gfTMDB:    {"tmdb", "tmdbid"},
	gfTVDB:    {"tvdb", "tvdbid", "thetvdb"},
	gfISBN:    {"isbn", "isbn13", "isbn10"},
	gfMAL:     {"mal", "malid", "myanimelistid", "animedbid", "seriesanimedbid"},
	gfAniList: {"anilist", "anilistid"},
	gfAuthor:  {"author", "authors"},
	gfStatus:  {"status", "state", "list", "shelf", "readstatus", "watchstatus", "exclusiveshelf"},
	gfRating:  {"rating", "score", "myrating", "yourrating", "userrating", "stars", "myscore"},
	gfFinished: {
		"watchedat", "watcheddate", "datewatched", "finished", "finishedat", "datefinished", "completedat",
		"dateread", "lastwatched",
	},
}

// genericKey is a header or word without case, spaces or punctuation.
func genericKey(header string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(header) {
		if unicode.IsLetter(r) || unicode.IsNumber(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ParseGenericCSV reads any CSV by its column names.
func ParseGenericCSV(table CSVTable) ([]Row, error) {
	columns := map[genericField]string{}
	for field := range genericFieldCount {
		for _, h := range table.Headers {
			if slices.Contains(genericAliases[field], genericKey(h)) {
				columns[field] = h
				break
			}
		}
	}
	identifying := false
	for _, f := range []genericField{gfTitle, gfIMDb, gfTMDB, gfTVDB, gfISBN, gfMAL, gfAniList} {
		if _, ok := columns[f]; ok {
			identifying = true
		}
	}
	if !identifying {
		return nil, formatError("This CSV has no column Aaru can match on. It needs a “Title” column (with a “Year” " +
			"if possible) or an id column such as “IMDb ID”, “TMDB ID” or “ISBN”.")
	}
	var ratings []float64
	if column, ok := columns[gfRating]; ok {
		for _, record := range table.Records {
			if v, ok := record[column]; ok {
				if n, ok := genericNumber(v); ok {
					ratings = append(ratings, n)
				}
			}
		}
	}
	scale := GenericRatingScale(ratings)
	var rows []Row
	for index, record := range table.Records {
		value := func(f genericField) *string {
			column, ok := columns[f]
			if !ok {
				return nil
			}
			v, ok := record[column]
			if !ok {
				return nil
			}
			v = trimWSNL(v)
			if v == "" {
				return nil
			}
			return &v
		}
		intID := func(f genericField) string {
			if v := value(f); v != nil {
				if n, ok := swiftInt(*v); ok {
					return strconv.Itoa(n)
				}
			}
			return ""
		}
		ids := core.ExternalIDs{TMDB: intID(gfTMDB), TVDB: intID(gfTVDB), AniList: intID(gfAniList), MAL: intID(gfMAL)}
		if v := value(gfIMDb); v != nil && strings.HasPrefix(*v, "tt") {
			ids.IMDB = *v
		}
		if v := value(gfISBN); v != nil {
			ids.ISBN = core.NormalizeISBN(*v)
		}
		title := value(gfTitle)
		if title == nil {
			if ids.IsEmpty() {
				continue
			}
			title = ptr(fmt.Sprintf("Row %d", index+2))
		}
		author := value(gfAuthor)
		row := Row{
			SourceKey: ptr(fmt.Sprintf("row %d", index+2)),
			Type:      genericMediaType(value(gfType), ids, author),
			Title:     *title,
			Author:    author,
			IDs:       ids,
			Lists:     []string{},
		}
		if v := value(gfYear); v != nil {
			row.Year = genericYear(*v)
		}
		if v := value(gfStatus); v != nil {
			row.Status = GenericStatus(*v)
		}
		if v := value(gfRating); v != nil {
			if n, ok := genericNumber(*v); ok {
				if r := math.Round(n * scale); r >= 1 && r <= 10 {
					row.Rating = &r
				}
			}
		}
		row.FinishedAt = catalog.ParseDay(value(gfFinished))
		rows = append(rows, row)
	}
	return rows, nil
}

// GenericRatingScale is what multiplies a rating onto 1–10: stars (≤ 5) double, percentages
// (> 10) divide by 10.
func GenericRatingScale(values []float64) float64 {
	if len(values) == 0 {
		return 1
	}
	top := slices.Max(values)
	if top <= 5 {
		return 2
	}
	if top > 10 {
		return 0.1
	}
	return 1
}

func genericNumber(text string) (float64, bool) {
	return swiftDouble(strings.ReplaceAll(text, ",", "."))
}

// genericYear is the first four-digit year in "2019", "2019-05-01" or "May 1, 2019".
func genericYear(text string) *int {
	for _, piece := range splitFunc(text, func(r rune) bool { return !unicode.IsNumber(r) }) {
		if charCount(piece) != 4 {
			continue
		}
		if n, ok := swiftInt(piece); ok && core.ValidYear(n) {
			return &n
		}
		return nil
	}
	return nil
}

func genericMediaType(text *string, ids core.ExternalIDs, author *string) core.MediaType {
	kind := ""
	if text != nil {
		kind = genericKey(*text)
	}
	if strings.Contains(kind, "book") || strings.Contains(kind, "novel") || ids.ISBN != "" || author != nil {
		return core.MediaBook
	}
	if strings.Contains(kind, "movie") || strings.Contains(kind, "film") {
		return core.MediaMovie
	}
	for _, word := range []string{"tv", "show", "series", "tvshow", "tvseries", "anime", "episode", "miniseries"} {
		if strings.Contains(kind, word) {
			return core.MediaShow
		}
	}
	if ids.TVDB != "" || ids.MAL != "" || ids.AniList != "" {
		return core.MediaShow
	}
	return core.MediaMovie
}

// GenericStatus is a status word any site writes, on Aaru's five.
func GenericStatus(text string) *core.LibraryStatus {
	switch genericKey(text) {
	case "watched", "completed", "complete", "finished", "read", "seen", "done":
		return ptr(core.StatusFinished)
	case "watching", "reading", "inprogress", "current", "currentlyreading", "currentlywatching", "rewatching":
		return ptr(core.StatusInProgress)
	case "onhold", "paused":
		return ptr(core.StatusOnHold)
	case "dropped", "abandoned", "didnotfinish", "dnf", "stopped":
		return ptr(core.StatusDropped)
	case "plantowatch", "plantoread", "planned", "planning", "watchlist", "wanttowatch", "wanttoread", "toread",
		"towatch", "wishlist", "backlog":
		return ptr(core.StatusWishlist)
	}
	return nil
}

// MARK: Format detection

// DetectFormat picks the parser for an uploaded file when the person did not say which site it
// came from (ImportFormatDetector).
func DetectFormat(text string) (core.ImportSource, error) {
	start := strings.TrimLeftFunc(text, func(r rune) bool { return unicode.IsSpace(r) || r == '\uFEFF' })
	switch {
	case strings.HasPrefix(start, "PK\x03\x04"):
		return "", formatError("This is a .zip file. Unzip it and upload the CSV files inside, one at a time.")
	case strings.HasPrefix(start, "[") || strings.HasPrefix(start, "{"):
		return "", formatError("This is a JSON file. Spotify and YouTube history go in as listening history, not as a CSV.")
	case strings.HasPrefix(start, "<"):
		if !strings.Contains(text, "<myanimelist") {
			return "", formatError("Aaru reads MyAnimeList-format XML (exported by MyAnimeList, Kitsu and AniList). " +
				"For other sites, export a CSV.")
		}
		return core.SourceMALXML, nil
	}
	if IsCATCalendar(text) {
		return core.SourceCATICS, nil
	}
	headers := ParseCSV(charPrefix(text, 4096)).headerSet()
	has := func(names ...string) bool {
		for _, n := range names {
			if !headers[n] {
				return false
			}
		}
		return true
	}
	switch {
	case has("Const", "Title Type"):
		return core.SourceIMDbCSV, nil
	case has("Letterboxd URI"):
		return core.SourceLetterboxdCSV, nil
	case has("Book Id", "Exclusive Shelf"):
		return core.SourceGoodreadsCSV, nil
	case len(headers) == 2 && has("Title", "Date"):
		return core.SourceNetflixCSV, nil
	case TVTimeLayoutOf(headers) != 0:
		return core.SourceTVTimeCSV, nil
	}
	return core.SourceGenericCSV, nil
}
