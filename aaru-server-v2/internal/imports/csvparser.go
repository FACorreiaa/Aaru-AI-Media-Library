package imports

import (
	"aaru-go-api/internal/core"
	"regexp"
	"strings"
	"time"
	"unicode"
)

// Parse is the uploaded file's rows: MyAnimeList XML, a CAT list or calendar, or one of the CSV
// layouts (ImportService.parse).
func Parse(text string, source core.ImportSource, filename *string) ([]Row, error) {
	switch source {
	case core.SourceMALXML:
		return ParseMALList(text)
	case core.SourceCATList:
		return ParseCATList(text)
	case core.SourceCATICS:
		return ParseCATCalendar(text)
	}
	return ParseCSVImport(text, source, filename)
}

// ParseCSVImport reads one of the known CSV export layouts (IMP-006/007/008, CSVImportParser). Each
// parser checks its columns first, so a file uploaded as the wrong source fails with a readable
// message instead of importing nonsense.
func ParseCSVImport(text string, source core.ImportSource, filename *string) ([]Row, error) {
	table := ParseCSV(text)
	switch source {
	case core.SourceIMDbCSV:
		return parseIMDb(table)
	case core.SourceLetterboxdCSV:
		return parseLetterboxd(table, filename)
	case core.SourceGoodreadsCSV:
		return parseGoodreads(table)
	case core.SourceNetflixCSV:
		return ParseNetflix(table)
	case core.SourceTVTimeCSV:
		return ParseTVTime(table)
	case core.SourceGenericCSV:
		return ParseGenericCSV(table)
	}
	return nil, formatError(string(source) + " is not a CSV import.")
}

// requireColumns refuses a table missing any of columns.
func requireColumns(columns []string, table CSVTable, source string) error {
	var missing []string
	for _, c := range columns {
		if !table.hasHeader(c) {
			missing = append(missing, "“"+c+"”")
		}
	}
	if len(missing) == 0 {
		return nil
	}
	return formatError("This does not look like a " + source + " export: it has no " +
		strings.Join(missing, ", ") + " column.")
}

// MARK: IMDb (ratings or watchlist export)

// parseIMDb: `tconst` is a hard id, so these rows match exactly. Episode rows are not imported:
// they are listed as unmatched with a reason, so the person adds the show instead (IMP-006). A
// `Position` column means the watchlist export.
func parseIMDb(table CSVTable) ([]Row, error) {
	if err := requireColumns([]string{"Const", "Title", "Title Type"}, table, "IMDb"); err != nil {
		return nil, err
	}
	isWatchlist := table.hasHeader("Position")
	var rows []Row
	for _, record := range table.Records {
		tconst, ok := record["Const"]
		title, hasTitle := record["Title"]
		if !ok || !strings.HasPrefix(tconst, "tt") || !hasTitle {
			continue
		}
		kind := strings.ToLower(record["Title Type"])
		mediaType := core.MediaMovie
		switch kind {
		case "tvseries", "tv series", "tvminiseries", "tv mini series":
			mediaType = core.MediaShow
		}
		var rating *float64
		if r := optDouble(record.opt("Your Rating")); r != nil && *r >= 1 && *r <= 10 {
			rating = r
		}
		status := core.StatusFinished
		if isWatchlist {
			status = core.StatusWishlist
		}
		row := Row{
			SourceKey: ptr(tconst), Type: mediaType, Title: title, Year: optInt(record.opt("Year")),
			IDs: core.ExternalIDs{IMDB: tconst}, Status: &status, Rating: rating, Lists: []string{},
		}
		if !isWatchlist {
			row.FinishedAt = optDay(record.opt("Date Rated"))
		}
		if strings.Contains(kind, "episode") {
			row.Unsupported = ptr("An episode row. Episodes are not imported; add the show instead.")
		}
		rows = append(rows, row)
	}
	return rows, nil
}

// MARK: Letterboxd (diary, ratings, watched or watchlist export)

// parseLetterboxd: no external id, so title + year through a catalog search, never guessed
// (IMP-007). The 0.5–5 star scale doubles onto 1–10. The watchlist export has the same columns as
// the watched one, so its file name decides.
func parseLetterboxd(table CSVTable, filename *string) ([]Row, error) {
	if err := requireColumns([]string{"Name", "Year"}, table, "Letterboxd"); err != nil {
		return nil, err
	}
	isWatchlist := filename != nil && strings.Contains(strings.ToLower(*filename), "watchlist")
	var rows []Row
	for _, record := range table.Records {
		name := record["Name"]
		if name == "" {
			continue
		}
		var rating *float64
		if stars := optDouble(record.opt("Rating")); stars != nil {
			rating = ptr(*stars * 2)
		}
		status := core.StatusFinished
		if isWatchlist {
			status = core.StatusWishlist
		}
		date := record.opt("Watched Date")
		if date == nil {
			date = record.opt("Date")
		}
		row := Row{
			SourceKey: record.opt("Letterboxd URI"), Type: core.MediaMovie, Title: name,
			Year: optInt(record.opt("Year")), Status: &status, Rating: rating, Lists: []string{},
		}
		if !isWatchlist {
			row.FinishedAt = optDay(date)
		}
		rows = append(rows, row)
	}
	return rows, nil
}

// MARK: Goodreads

// parseGoodreads: Exclusive Shelf → status; custom shelves → lists; ISBNs arrive as
// `="0441172717"`. IMP-020: the series suffix leaves the title, a "did not finish" shelf is
// dropped, the review (else the private notes) is the notes, and an owned copy marks it owned.
func parseGoodreads(table CSVTable) ([]Row, error) {
	if err := requireColumns([]string{"Title", "Author", "Exclusive Shelf"}, table, "Goodreads"); err != nil {
		return nil, err
	}
	exclusive := map[string]bool{"to-read": true, "currently-reading": true, "read": true}
	var rows []Row
	for _, record := range table.Records {
		raw := record["Title"]
		if raw == "" {
			continue
		}
		var isbn *string
		for _, field := range []string{"ISBN13", "ISBN"} {
			if v := record.opt(field); v != nil {
				if cleaned := cleanISBN(*v); cleaned != nil {
					isbn = cleaned
					break
				}
			}
		}
		var ids core.ExternalIDs
		if isbn != nil {
			ids.ISBN = core.NormalizeISBN(*isbn)
		}
		stars := 0.0
		if s := optDouble(record.opt("My Rating")); s != nil {
			stars = *s
		}
		var rating *float64
		if stars > 0 {
			rating = ptr(stars * 2)
		}
		lists := []string{}
		for _, shelf := range strings.Split(record["Bookshelves"], ",") {
			shelf = trimWS(shelf)
			if shelf != "" && !exclusive[shelf] {
				lists = append(lists, shelf)
			}
		}
		owned := 0
		if v, ok := record["Owned Copies"]; ok {
			if n, ok := swiftInt(trimWS(v)); ok {
				owned = n
			}
		}
		yearField := record.opt("Original Publication Year")
		if yearField == nil {
			yearField = record.opt("Year Published")
		}
		var notes *string
		if v := record.opt("My Review"); v != nil {
			notes = goodreadsPlainText(*v)
		}
		if notes == nil {
			if v := record.opt("Private Notes"); v != nil {
				notes = goodreadsPlainText(*v)
			}
		}
		row := Row{
			SourceKey: record.opt("Book Id"), Type: core.MediaBook, Title: goodreadsWithoutSeries(raw),
			Year: optInt(yearField), Author: record.opt("Author"), IDs: ids,
			Status: GoodreadsStatus(record["Exclusive Shelf"]), Rating: rating,
			FinishedAt: optDay(record.opt("Date Read")), Lists: lists, Notes: notes,
		}
		if owned > 0 {
			row.IsOwned = ptr(true)
		}
		rows = append(rows, row)
	}
	return rows, nil
}

// GoodreadsStatus is the three built-in shelves, plus the shelves people make for books they gave
// up on. Any other shelf says nothing about status.
func GoodreadsStatus(shelf string) *core.LibraryStatus {
	key := strings.Join(splitFunc(strings.ToLower(shelf), func(r rune) bool {
		return r == ' ' || r == '-' || r == '_'
	}), "-")
	switch key {
	case "to-read":
		return ptr(core.StatusWishlist)
	case "currently-reading":
		return ptr(core.StatusInProgress)
	case "read":
		return ptr(core.StatusFinished)
	case "dnf", "did-not-finish", "abandoned", "dropped":
		return ptr(core.StatusDropped)
	}
	return nil
}

// goodreadsWithoutSeries: Goodreads puts the series after the title, "Leviathan Wakes (The
// Expanse, #1)". The catalog does not, so a trailing bracket that numbers the book in a series is
// dropped. Any other bracket ("Dune (Deluxe Edition)") stays.
func goodreadsWithoutSeries(title string) string {
	trimmed := trimWS(title)
	open := strings.LastIndex(trimmed, "(")
	if !strings.HasSuffix(trimmed, ")") || open < 0 {
		return trimmed
	}
	inner := []rune(trimmed[open+1 : len(trimmed)-1])
	numbered := false
	for i := 0; i+1 < len(inner); i++ {
		if inner[i] == '#' && unicode.IsNumber(inner[i+1]) {
			numbered = true
			break
		}
	}
	rest := trimWS(trimmed[:open])
	if numbered && rest != "" {
		return rest
	}
	return trimmed
}

var (
	goodreadsBreaks = func() []*regexp.Regexp {
		var out []*regexp.Regexp
		for _, tag := range []string{"<br/>", "<br />", "<br>", "</p>"} {
			out = append(out, regexp.MustCompile("(?i)"+regexp.QuoteMeta(tag)))
		}
		return out
	}()
	// Only real tags: a "<" that no letter follows ("3 < 4") is text.
	goodreadsTag = regexp.MustCompile(`</?[A-Za-z][^>]*>`)
)

// goodreadsPlainText: Goodreads reviews are HTML (`<br/>` for a line break, `&amp;`). Plain text,
// or nil when nothing is left.
func goodreadsPlainText(html string) *string {
	text := html
	for _, re := range goodreadsBreaks {
		text = re.ReplaceAllLiteralString(text, "\n")
	}
	plain := goodreadsTag.ReplaceAllLiteralString(text, "")
	for _, e := range [][2]string{
		{"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&#39;", "'"}, {"&nbsp;", " "}, {"&amp;", "&"},
	} {
		plain = strings.ReplaceAll(plain, e[0], e[1])
	}
	lines := splitLF(plain)
	for i := range lines {
		lines[i] = trimWS(lines[i])
	}
	out := trimWSNL(strings.Join(lines, "\n"))
	if out == "" {
		return nil
	}
	return &out
}

// splitLF splits on the Character "\n", keeping empty pieces. "\r\n" is one Character in Swift,
// so it does not split there.
func splitLF(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' && (i == 0 || s[i-1] != '\r') {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	return append(out, s[start:])
}

// cleanISBN: Goodreads wraps ISBNs as `="0441172717"` and leaves `=""` when there is none.
func cleanISBN(raw string) *string {
	var b strings.Builder
	for _, r := range raw {
		if unicode.IsNumber(r) || r == 'X' || r == 'x' {
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return nil
	}
	return ptr(b.String())
}

// csvDay is `2024-03-01` or `2024/03/01`, at noon UTC so no time zone moves it to another day.
func csvDay(raw string) *time.Time {
	var parts []int
	for _, p := range splitFunc(raw, func(r rune) bool { return r == '-' || r == '/' }) {
		if n, ok := swiftInt(p); ok {
			parts = append(parts, n)
		}
	}
	if len(parts) != 3 || parts[0] <= 1800 {
		return nil
	}
	return ptr(noonUTC(parts[0], parts[1], parts[2]))
}

func optDay(raw *string) *time.Time {
	if raw == nil {
		return nil
	}
	return csvDay(*raw)
}
