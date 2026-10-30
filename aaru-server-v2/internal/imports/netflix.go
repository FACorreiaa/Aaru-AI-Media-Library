package imports

import (
	"aaru-go-api/internal/core"
	"regexp"
	"strings"
	"time"

	"golang.org/x/text/unicode/norm"
)

// IMP-018: Netflix's viewing activity (Account → Profile → Viewing activity → Download all),
// `NetflixViewingHistory.csv` (NetflixCSVParser). Two columns, `Title` and `Date`, one profile per
// file. A title is `Show: Season 1: Episode name` (or `Limited Series`, `Part 2`, `Stranger Things
// 4`, …) or a film's name. No ids and no release year, so rows are `nameOnly`: they match only
// when exactly one catalog entry has the name and came out by the year it was first watched.
// Episodes come by name and are numbered once the show's episode list is known.

// ParseNetflix reads a viewing activity file.
func ParseNetflix(table CSVTable) ([]Row, error) {
	if table.hasHeader("Profile Name") {
		return nil, formatError("This is Netflix's full account download, with every profile in it. " +
			"Use Account → Profile → Viewing activity → Download all instead, one profile per file.")
	}
	var missing []string
	for _, c := range []string{"Title", "Date"} {
		if !table.hasHeader(c) {
			missing = append(missing, "“"+c+"”")
		}
	}
	if len(missing) > 0 {
		return nil, formatError("This does not look like a Netflix viewing activity file: it has no " +
			strings.Join(missing, ", ") + " column.")
	}
	var dates []string
	for _, r := range table.Records {
		if d, ok := r["Date"]; ok {
			dates = append(dates, d)
		}
	}
	order := NetflixDateOrderOf(dates)
	index := map[string]int{}
	var rows []Row
	var firstYears []*int
	for _, record := range table.Records {
		raw := record["Title"]
		if raw == "" {
			continue
		}
		var watched *time.Time
		if d, ok := record["Date"]; ok {
			watched = NetflixDay(d, order)
		}
		entry := NetflixEntryOf(raw)
		normalized := core.NormalizeTitle(entry.Title)
		key := string(entry.Type) + ":" + normalized
		if normalized == "" {
			continue
		}
		slot, seen := index[key]
		if !seen {
			slot = len(rows)
			index[key] = slot
			status := core.StatusInProgress
			if entry.Type == core.MediaMovie {
				status = core.StatusFinished
			}
			rows = append(rows, Row{
				SourceKey: ptr("netflix:" + entry.Title), Type: entry.Type, Title: entry.Title, Status: &status,
				Lists: []string{}, NameOnly: ptr(true),
			})
			firstYears = append(firstYears, nil)
		}
		if entry.Episode != nil && !containsNamed(rows[slot].NamedEpisodes, *entry.Episode) {
			rows[slot].NamedEpisodes = append(rows[slot].NamedEpisodes, *entry.Episode)
		}
		if watched != nil {
			year := watched.Year()
			if firstYears[slot] == nil || year < *firstYears[slot] {
				firstYears[slot] = &year
			}
			if entry.Type == core.MediaMovie && (rows[slot].FinishedAt == nil || watched.After(*rows[slot].FinishedAt)) {
				rows[slot].FinishedAt = watched
			}
		}
	}
	for slot := range rows {
		rows[slot].NotAfter = firstYears[slot]
	}
	return rows, nil
}

func containsNamed(list []NamedEpisode, e NamedEpisode) bool {
	for _, x := range list {
		if x.Name == e.Name && ((x.Season == nil) == (e.Season == nil)) && (x.Season == nil || *x.Season == *e.Season) {
			return true
		}
	}
	return false
}

// NetflixEntry is one title line read: a film, or a show with one named episode.
type NetflixEntry struct {
	Type    core.MediaType
	Title   string
	Episode *NamedEpisode
}

// NetflixEntryOf reads a title: `Show: Season 2: Name` → the show, season 2, episode "Name". The first segment
// that reads as a season splits it; a title with none is a film (`Mission: Impossible - Fallout`).
func NetflixEntryOf(raw string) NetflixEntry {
	parts := strings.Split(raw, ": ")
	for i := range parts {
		parts[i] = trimWS(parts[i])
	}
	if len(parts) >= 3 {
		for split := 1; split < len(parts)-1; split++ {
			show := strings.Join(parts[:split], ": ")
			if season, ok := netflixSeason(parts[split], show); ok {
				name := strings.Join(parts[split+1:], ": ")
				return NetflixEntry{Type: core.MediaShow, Title: show, Episode: &NamedEpisode{Season: &season, Name: name}}
			}
		}
	}
	return NetflixEntry{Type: core.MediaMovie, Title: trimWS(raw)}
}

// Season words in the languages Netflix writes its export in.
var (
	netflixSeasonWords = map[string]bool{
		"season": true, "series": true, "part": true, "volume": true, "vol": true, "book": true, "chapter": true,
		"collection": true, "temporada": true, "saison": true, "staffel": true, "stagione": true, "seizoen": true,
		"sezon": true, "säsong": true, "sæson": true, "sesong": true,
	}
	netflixLimitedSeries = map[string]bool{
		"limited series": true, "miniseries": true, "mini series": true, "miniserie": true, "minisérie": true,
		"série limitée": true,
	}
	// swiftSpace is Swift Regex's `\s`: Unicode White_Space.
	netflixOwnName = regexp.MustCompile(`^(.+)` + swiftSpace + `+(\d{1,2})$`)
)

// swiftSpace is a character class for Unicode White_Space, Swift Regex's `\s`.
const swiftSpace = `[\t\n\v\f\r \x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}]`

// netflixSeason: `Season 2` → 2, `Limited Series` → 1, `Stranger Things 4` (the show's own name) → 4.
func netflixSeason(segment, show string) (int, bool) {
	// Swift compares strings by canonical equivalence; NFC makes Go's comparison agree.
	lowered := norm.NFC.String(strings.ToLower(segment))
	if netflixLimitedSeries[lowered] {
		return 1, true
	}
	words := strings.FieldsFunc(strings.ReplaceAll(lowered, ".", " "), func(r rune) bool { return r == ' ' })
	if len(words) == 2 && netflixSeasonWords[words[0]] {
		if n, ok := swiftInt(words[1]); ok && n >= 0 && n <= 200 {
			return n, true
		}
	}
	if m := netflixOwnName.FindStringSubmatch(segment); m != nil {
		if n, ok := swiftInt(m[2]); ok && core.NormalizeTitle(m[1]) == core.NormalizeTitle(show) {
			return n, true
		}
	}
	return 0, false
}

// NetflixDateOrder is how a file writes its dates. The account's locale decides the layout.
type NetflixDateOrder int

// The two orders.
const (
	NetflixMonthFirst NetflixDateOrder = iota
	NetflixDayFirst
)

// NetflixDateOrderOf is the order a file is read in, one way throughout: day first when any date's first number
// passes 12, else month first (Netflix's US layout).
func NetflixDateOrderOf(dates []string) NetflixDateOrder {
	for _, raw := range dates {
		parts := netflixNumbers(raw)
		if len(parts) == 3 && parts[0] <= 31 && parts[0] > 12 {
			return NetflixDayFirst
		}
	}
	return NetflixMonthFirst
}

// NetflixDay reads `1/23/24`, `23/01/2024`, `23.01.2024` or `2024-01-23`, at noon UTC.
func NetflixDay(raw string, order NetflixDateOrder) *time.Time {
	parts := netflixNumbers(raw)
	if len(parts) != 3 {
		return nil
	}
	isoOrder := parts[0] > 31
	var year, month, day int
	switch {
	case isoOrder:
		year, month, day = parts[0], parts[1], parts[2]
	case order == NetflixMonthFirst:
		year, month, day = parts[2], parts[0], parts[1]
	default:
		year, month, day = parts[2], parts[1], parts[0]
	}
	if !isoOrder && year < 100 {
		year += 2000
	}
	if year < 1990 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31 {
		return nil
	}
	return ptr(noonUTC(year, month, day))
}

func netflixNumbers(raw string) []int {
	var out []int
	for _, p := range splitFunc(raw, func(r rune) bool { return r == '-' || r == '/' || r == '.' }) {
		if n, ok := swiftInt(trimWS(p)); ok {
			out = append(out, n)
		}
	}
	return out
}
