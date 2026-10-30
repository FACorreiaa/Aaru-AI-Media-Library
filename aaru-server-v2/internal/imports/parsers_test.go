package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/export"
	"aaru-go-api/internal/library"
	"errors"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ports ImportParserTests, GenericImportTests' parser cases and the parser halves of
// GoodreadsImportTests, MangaImportTests and AnimeListImportTests. No database.

func isFormatError(err error) bool {
	var f *FormatError
	return errors.As(err, &f)
}

func pzStatus(s core.LibraryStatus) *core.LibraryStatus { return &s }

func pzTitles(rows []Row) []string {
	out := make([]string, len(rows))
	for i, r := range rows {
		out[i] = r.Title
	}
	return out
}

func pzStatuses(rows []Row) []*core.LibraryStatus {
	out := make([]*core.LibraryStatus, len(rows))
	for i, r := range rows {
		out[i] = r.Status
	}
	return out
}

func pzDay(t *time.Time) string {
	if t == nil {
		return ""
	}
	return t.UTC().Format("2006-01-02")
}

func pzKeys(t *testing.T, pairs ...int) []core.EpisodeKey {
	t.Helper()
	var out []core.EpisodeKey
	for i := 0; i+1 < len(pairs); i += 2 {
		k, err := core.NewEpisodeKey(pairs[i], pairs[i+1])
		require.NoError(t, err)
		out = append(out, k)
	}
	return out
}

func pzParse(t *testing.T, text string, source core.ImportSource, filename *string) []Row {
	t.Helper()
	rows, err := Parse(text, source, filename)
	require.NoError(t, err)
	return rows
}

// MARK: ImportParserTests

func TestCSVQuoting(t *testing.T) {
	table := ParseCSV("\uFEFFTitle,Note\r\n\"Dune, Part One\",\"He said \"\"hi\"\"\"\r\nPlain,x\r\n")
	assert.Equal(t, []string{"Title", "Note"}, table.Headers)
	require.Len(t, table.Records, 2)
	assert.Equal(t, "Dune, Part One", table.Records[0]["Title"])
	assert.Equal(t, "Plain", table.Records[1]["Title"])
	assert.Equal(t, `He said "hi"`, table.Records[0]["Note"])
}

func TestGoodreadsParser(t *testing.T) {
	csv := `Book Id,Title,Author,ISBN,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Date Read,Original Publication Year
1,Dune,Frank Herbert,"=""0441172717""","=""9780441172719""",4,read,"favorites, read, sci-fi",2024/03/01,1965
2,No ISBN Book,Some Author,"=""""","=""""",0,to-read,to-read,,2001
3,Reading Now,An Author,,,0,currently-reading,currently-reading,,2010`
	rows := pzParse(t, csv, core.SourceGoodreadsCSV, nil)
	require.Len(t, rows, 3)
	assert.Equal(t, "9780441172719", rows[0].IDs.ISBN)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[0].Status)
	assert.Equal(t, ptr(8.0), rows[0].Rating)
	assert.Equal(t, []string{"favorites", "sci-fi"}, rows[0].Lists, "read is the exclusive shelf, not a list")
	assert.Equal(t, "2024-03-01", pzDay(rows[0].FinishedAt))
	assert.Equal(t, 12, rows[0].FinishedAt.Hour(), "at noon UTC")
	assert.Empty(t, rows[1].IDs.ISBN, `an empty ="" ISBN is no ISBN`)
	assert.Equal(t, ptr("Some Author"), rows[1].Author, "title + author is the fallback")
	assert.Equal(t, pzStatus(core.StatusWishlist), rows[1].Status)
	assert.Nil(t, rows[1].Rating, "0 stars means not rated")
	assert.Equal(t, pzStatus(core.StatusInProgress), rows[2].Status)
}

func TestGoodreadsMore(t *testing.T) {
	csv := `Book Id,Title,Author,Exclusive Shelf,Bookshelves,My Review,Private Notes,Owned Copies
1,"Leviathan Wakes (The Expanse, #1)",James S.A. Corey,dnf,dnf,"Slow.<br/>Gave up &amp; moved on.",Hidden,1
2,"Dune (Deluxe Edition)",Frank Herbert,Did Not Finish,did-not-finish,,"Private, only",0
3,"Small Gods (Discworld, #13; Omnieni #1)",Terry Pratchett,abandoned,,<p> </p>,,
4,Plain,Someone,Dropped,,,,x
5,Shelved,Someone,favorites,favorites,,,`
	rows := pzParse(t, csv, core.SourceGoodreadsCSV, nil)
	assert.Equal(t, []string{"Leviathan Wakes", "Dune (Deluxe Edition)", "Small Gods", "Plain", "Shelved"}, pzTitles(rows))
	d := pzStatus(core.StatusDropped)
	assert.Equal(t, []*core.LibraryStatus{d, d, d, d, nil}, pzStatuses(rows))
	assert.Equal(t, []string{"dnf"}, rows[0].Lists, "a custom exclusive shelf is still a list")
	assert.Equal(t, ptr("Slow.\nGave up & moved on."), rows[0].Notes, "the review wins over private notes")
	assert.Equal(t, ptr("Private, only"), rows[1].Notes)
	assert.Nil(t, rows[2].Notes, "a review with nothing in it is no notes")
	owned := make([]*bool, len(rows))
	for i, r := range rows {
		owned[i] = r.IsOwned
	}
	assert.Equal(t, []*bool{ptr(true), nil, nil, nil, nil}, owned, "only a count above 0 says owned")
}

func TestGoodreadsSeriesSuffix(t *testing.T) {
	assert.Equal(t, "The Way of Kings", goodreadsWithoutSeries("The Way of Kings (The Stormlight Archive, #1)"))
	assert.Equal(t, "Mistborn", goodreadsWithoutSeries("Mistborn (Mistborn, #0.5)"))
	assert.Equal(t, "Omnibus", goodreadsWithoutSeries("Omnibus (Series #1-3)"))
	assert.Equal(t, "Catch-22 (50th Anniversary)", goodreadsWithoutSeries("Catch-22 (50th Anniversary)"))
	assert.Equal(t, "(#1)", goodreadsWithoutSeries("(#1)"), "a title that is only the bracket stays")
	assert.Equal(t, ptr("3 < 4 <b>"), goodreadsPlainText("3 < 4 &lt;b&gt;"), "only real tags go")
}

func TestIMDbParser(t *testing.T) {
	ratings := `Const,Your Rating,Date Rated,Title,Title Type,Year
tt0133093,9,2024-01-02,The Matrix,Movie,1999
tt0944947,10,2024-01-03,Game of Thrones,TV Series,2011
tt1480055,8,2024-01-04,Winter Is Coming,TV Episode,2011`
	rows := pzParse(t, ratings, core.SourceIMDbCSV, ptr("ratings.csv"))
	require.Len(t, rows, 3)
	assert.Equal(t, []core.MediaType{core.MediaMovie, core.MediaShow, core.MediaMovie},
		[]core.MediaType{rows[0].Type, rows[1].Type, rows[2].Type})
	assert.Equal(t, "tt0133093", rows[0].IDs.IMDB)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[0].Status)
	assert.Equal(t, ptr(9.0), rows[0].Rating)
	assert.NotNil(t, rows[2].Unsupported)
	watchlist := "Position,Const,Title,Title Type,Year\n1,tt0133093,The Matrix,Movie,1999\n"
	wish := pzParse(t, watchlist, core.SourceIMDbCSV, nil)
	assert.Equal(t, pzStatus(core.StatusWishlist), wish[0].Status)
}

func TestLetterboxdParser(t *testing.T) {
	diary := `Date,Name,Year,Letterboxd URI,Rating,Watched Date
2024-02-01,Heat,1995,https://boxd.it/abc,4.5,2024-01-31
2024-02-02,Crash,2004,https://boxd.it/def,0.5,`
	rows := pzParse(t, diary, core.SourceLetterboxdCSV, ptr("diary.csv"))
	assert.Equal(t, []*float64{ptr(9.0), ptr(1.0)}, []*float64{rows[0].Rating, rows[1].Rating})
	assert.Equal(t, pzStatus(core.StatusFinished), rows[0].Status)
	assert.True(t, rows[0].IDs.IsEmpty(), "no id: title + year resolution")
	assert.Equal(t, "2024-01-31", pzDay(rows[0].FinishedAt))
	assert.Nil(t, rows[1].FinishedAt, "an empty Watched Date does not fall back to Date")
	watchlist := "Date,Name,Year,Letterboxd URI\n2024-02-01,Heat,1995,https://boxd.it/abc\n"
	wish := pzParse(t, watchlist, core.SourceLetterboxdCSV, ptr("watchlist.csv"))
	assert.Equal(t, pzStatus(core.StatusWishlist), wish[0].Status)
	assert.Nil(t, wish[0].FinishedAt)
}

func TestWrongColumns(t *testing.T) {
	goodreads := "Title,Author,Exclusive Shelf\nDune,Frank Herbert,read\n"
	_, err := Parse(goodreads, core.SourceIMDbCSV, nil)
	assert.True(t, isFormatError(err))
	_, err = Parse(goodreads, core.SourceLetterboxdCSV, nil)
	require.True(t, isFormatError(err))
	assert.Equal(t, "This does not look like a Letterboxd export: it has no “Name”, “Year” column.", err.Error())
	_, err = Parse("x", core.SourceTrakt, nil)
	assert.EqualError(t, err, "trakt is not a CSV import.")
}

// MARK: GenericImportTests

func TestDetection(t *testing.T) {
	cases := map[string]core.ImportSource{
		"\uFEFF<?xml version=\"1.0\"?><myanimelist></myanimelist>": core.SourceMALXML,
		"Const,Your Rating,Title,Title Type\n":                     core.SourceIMDbCSV,
		"Date,Name,Year,Letterboxd URI\n":                          core.SourceLetterboxdCSV,
		"Book Id,Title,Exclusive Shelf\n":                          core.SourceGoodreadsCSV,
		"Name,Year,Watched\n":                                      core.SourceGenericCSV,
		"Title,Date\nRoma,1/5/19\n":                                core.SourceNetflixCSV,
		"Title,Year,IMDb ID\nDark,2017,tt5753856\n":                core.SourceGenericCSV,
		"\uFEFFBEGIN:VCALENDAR\r\nEND:VCALENDAR":                   core.SourceCATICS,
	}
	for text, want := range cases {
		got, err := DetectFormat(text)
		require.NoError(t, err, text)
		assert.Equal(t, want, got, text)
	}
	for text, message := range map[string]string{
		"<rss><channel/></rss>": "Aaru reads MyAnimeList-format XML (exported by MyAnimeList, Kitsu and AniList). For other sites, export a CSV.",
		"PK\x03\x04\x14\x00":    "This is a .zip file. Unzip it and upload the CSV files inside, one at a time.",
		"  [{\"ts\": 1}]":       "This is a JSON file. Spotify and YouTube history go in as listening history, not as a CSV.",
	} {
		_, err := DetectFormat(text)
		require.True(t, isFormatError(err), text)
		assert.Equal(t, message, err.Error())
	}
}

func TestGenericParse(t *testing.T) {
	rows, err := ParseGenericCSV(ParseCSV(`Title,Release Date,Media Type,IMDb ID,TMDB ID,Status,My Rating,Watched At
Arrival,2016-11-11,Movie,tt2543164,329865,Completed,4.5,2024-02-01
Severance,2022,TV Show,,95396,Watching,5,
Some Book,2001,,,,Want to Read,,
,,,,,,,`))
	require.NoError(t, err)
	require.Len(t, rows, 3, "a row with neither a title nor an id is skipped")
	assert.Equal(t, core.MediaMovie, rows[0].Type)
	assert.Equal(t, ptr(2016), rows[0].Year)
	assert.Equal(t, "tt2543164", rows[0].IDs.IMDB)
	assert.Equal(t, "329865", rows[0].IDs.TMDB)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[0].Status)
	assert.Equal(t, ptr(9.0), rows[0].Rating)
	assert.Equal(t, catalog.ParseDay(ptr("2024-02-01")), rows[0].FinishedAt)
	assert.Equal(t, ptr("row 2"), rows[0].SourceKey)
	assert.Equal(t, core.MediaShow, rows[1].Type)
	assert.Equal(t, pzStatus(core.StatusInProgress), rows[1].Status)
	assert.Equal(t, ptr(10.0), rows[1].Rating)
	assert.Equal(t, pzStatus(core.StatusWishlist), rows[2].Status)
	assert.Nil(t, rows[2].Rating)

	_, err = ParseGenericCSV(ParseCSV("Foo,Bar\n1,2"))
	require.True(t, isFormatError(err))

	idOnly, err := ParseGenericCSV(ParseCSV("ISBN,Author\n9780441172719,Frank Herbert\n"))
	require.NoError(t, err)
	assert.Equal(t, "Row 2", idOnly[0].Title, "an id with no title is named by its row")
	assert.Equal(t, core.MediaBook, idOnly[0].Type)
}

func TestGenericOnHoldWords(t *testing.T) {
	for _, word := range []string{"On hold", "on-hold", "Paused", export.StatusWord(core.StatusOnHold)} {
		assert.Equal(t, pzStatus(core.StatusOnHold), GenericStatus(word), word)
	}
	for _, status := range core.LibraryStatuses {
		assert.Equal(t, pzStatus(status), GenericStatus(export.StatusWord(status)), "%s round-trips", status)
	}
}

func TestGenericRatingScales(t *testing.T) {
	assert.InDelta(t, 2, GenericRatingScale([]float64{3, 4.5}), 0)
	assert.InDelta(t, 1, GenericRatingScale([]float64{7, 10}), 0)
	assert.InDelta(t, 0.1, GenericRatingScale([]float64{85, 60}), 0)
	assert.InDelta(t, 1, GenericRatingScale(nil), 0)
	rows, err := ParseGenericCSV(ParseCSV("Title,Score\nA,85\nB,\"7,5\"\nC,3\n"))
	require.NoError(t, err)
	assert.Equal(t, ptr(9.0), rows[0].Rating, "85% rounds onto 9")
	assert.Nil(t, rows[2].Rating, "0.3 rounds to nothing")
}

// MARK: CAT parsers (CATImportTests)

func TestCATList(t *testing.T) {
	rows, err := ParseCATList("Severance\n- The Bear\n3. Brothers (2026)\n\n• severance\nSlow Horses\r\n")
	require.NoError(t, err)
	assert.Equal(t, []string{"Severance", "The Bear", "Brothers", "Slow Horses"}, pzTitles(rows))
	assert.Equal(t, []*int{nil, nil, ptr(2026), nil}, []*int{rows[0].Year, rows[1].Year, rows[2].Year, rows[3].Year})
	assert.Equal(t, []*bool{ptr(true), ptr(true), nil, ptr(true)},
		[]*bool{rows[0].NameOnly, rows[1].NameOnly, rows[2].NameOnly, rows[3].NameOnly})
	for _, r := range rows {
		assert.Equal(t, core.MediaShow, r.Type)
		assert.Equal(t, pzStatus(core.StatusWishlist), r.Status)
		assert.Nil(t, r.Watched)
	}
	assert.Equal(t, ptr("cat:Brothers (2026)"), rows[2].SourceKey)
}

func TestCATListLimits(t *testing.T) {
	rows, err := ParseCATList("Severance\n" + strings.Repeat("x", 300))
	require.NoError(t, err)
	require.Len(t, rows, 2)
	assert.Equal(t, ptr("Too long to be a show name. Put one show on each line."), rows[1].Unsupported)
	assert.Equal(t, strings.Repeat("x", 80)+"…", rows[1].Title)
	lines := make([]string, CATMaxLines+1)
	for i := range lines {
		lines[i] = "Show " + strconv.Itoa(i)
	}
	_, err = ParseCATList(strings.Join(lines, "\n"))
	require.True(t, isFormatError(err))
	assert.Equal(t, "That is more than 2000 lines. Paste one show per line.", err.Error())
}

func pzCalendar(summaries []string) string {
	parts := []string{"BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CAT//EN"}
	for i, s := range summaries {
		parts = append(parts, "BEGIN:VEVENT\r\nUID:"+string(rune('0'+i%10))+"@pogdesign\r\nDTSTART;VALUE=DATE:20261021\r\nSUMMARY:"+s+"\r\nEND:VEVENT")
	}
	parts = append(parts, "END:VCALENDAR")
	return strings.Join(parts, "\r\n") + "\r\n"
}

func TestCATCalendarCollapses(t *testing.T) {
	var summaries []string
	for i := range 200 {
		summaries = append(summaries, "Show "+strconv.Itoa(i%15)+": S"+strconv.Itoa(i/15+1)+"E"+strconv.Itoa(i%9+1)+" - Episode "+strconv.Itoa(i))
	}
	rows, err := ParseCATCalendar(pzCalendar(summaries))
	require.NoError(t, err)
	require.Len(t, rows, 15)
	want := map[string]bool{}
	for i := range 15 {
		want["Show "+strconv.Itoa(i)] = true
	}
	for _, r := range rows {
		assert.True(t, want[r.Title], r.Title)
		assert.Equal(t, pzStatus(core.StatusWishlist), r.Status)
		assert.Nil(t, r.Unsupported)
	}
}

func TestCATCalendarFolding(t *testing.T) {
	text := "BEGIN:VCALENDAR\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY;LANGUAGE=en:Law & Order\\, Special Victims Unit: S27E\r\n 03 - Part One\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Doctor Who (2023) - 2x05\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Season premiere night\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Season premiere night\r\nEND:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
	rows, err := ParseCATCalendar(text)
	require.NoError(t, err)
	assert.Equal(t, []string{"Law & Order, Special Victims Unit", "Doctor Who", "Season premiere night"}, pzTitles(rows))
	assert.Equal(t, ptr(2023), rows[1].Year)
	assert.Equal(t, ptr("Couldn't read a show name from “Season premiere night”."), rows[2].Unsupported)
}

func TestCATCalendarAirings(t *testing.T) {
	text := "BEGIN:VCALENDAR\r\n" +
		"BEGIN:VEVENT\r\nDTSTART:20261026T000000\r\nSUMMARY:The Simpsons S38E04 - \\nTreehouse of Horror XXXVII\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nDTSTART:20261102T010000\r\nSUMMARY:The Simpsons S38E05 - \\nThe Kosmic Kruiser\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Doctor Who - 2x05\r\nDTSTART;VALUE=DATE:20261031\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Tracker S03E04\r\nEND:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
	rows, err := ParseCATCalendar(text)
	require.NoError(t, err)
	assert.Equal(t, []string{"The Simpsons", "Doctor Who", "Tracker"}, pzTitles(rows))
	assert.Equal(t, []*Airing{
		{Season: 38, Episode: 4, Day: "2026-10-26"},
		{Season: 2, Episode: 5, Day: "2026-10-31"},
		nil,
	}, []*Airing{rows[0].Airing, rows[1].Airing, rows[2].Airing})
}

func TestCATDetection(t *testing.T) {
	got, err := DetectFormat("\uFEFFBEGIN:VCALENDAR\r\nEND:VCALENDAR")
	require.NoError(t, err)
	assert.Equal(t, core.SourceCATICS, got)
	_, err = ParseCATCalendar("Severance\nThe Bear")
	require.True(t, isFormatError(err))
	assert.Equal(t, "That is not a calendar file. Export the iCal file from CAT.", err.Error())
	assert.True(t, IsCATCalendar("  \n begin:vcalendar"))
}

func TestCATLinks(t *testing.T) {
	got, err := CATCalendarURL(" https://www.pogdesign.co.uk/cat/download_ics/abc123DEF \n")
	require.NoError(t, err)
	assert.Equal(t, "https://www.pogdesign.co.uk/cat/generate_ics/abc123DEF", got)
	got, err = CATCalendarURL("https://pogdesign.co.uk/cat/generate_ics/k-1/")
	require.NoError(t, err)
	assert.Equal(t, "https://www.pogdesign.co.uk/cat/generate_ics/k-1", got)
	for _, bad := range []string{
		"http://www.pogdesign.co.uk/cat/download_ics/abc",
		"https://evil.example/cat/download_ics/abc",
		"https://www.pogdesign.co.uk.evil.example/cat/download_ics/abc",
		"https://www.pogdesign.co.uk/cat/show-select",
		"https://www.pogdesign.co.uk/cat/download_ics/abc/../../x",
		"https://www.pogdesign.co.uk:8443/cat/download_ics/abc",
		"https://user@www.pogdesign.co.uk/cat/download_ics/abc",
		"not a link",
	} {
		_, err := CATCalendarURL(bad)
		var appErr *apperr.Error
		require.ErrorAs(t, err, &appErr, bad)
		assert.Equal(t, 422, appErr.Status)
		assert.Equal(t, "Paste the iCal link from CAT: it starts with https://www.pogdesign.co.uk/cat/.", appErr.Message, bad)
		assert.Equal(t, map[string]string{"url": appErr.Message}, appErr.Details)
	}
}

// pzRealExport is trimmed from a real CAT export (2026-10-21). The header's PRODID, which carries
// the user's CAT key and email, is replaced.
const pzRealExport = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nX-WR-CALDESC:Calendar for TV from Pogdesign\r\n" +
	"X-WR-CALNAME:TV Shows\r\nX-WR-TIMEZONE:Europe/Lisbon\r\nPRODID:-//Pogdesign//TV//EN\r\nMETHOD:PUBLISH\r\n" +
	"BEGIN:VEVENT\r\nDTSTART:20261026T000000\r\nDTEND:20261026T003000\r\n" +
	"SUMMARY:The Simpsons S38E04 - \\nTreehouse of Horror XXXVII\r\n" +
	"URL:https://www.pogdesign.co.uk/cat/The-Simpsons-summary\r\nUID:THESIMPSONS_38_4\r\n" +
	"CATEGORIES: The Simpsons Episodes, TV Shows\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nDTSTART:20261026T010000\r\nDTEND:20261026T020000\r\nSUMMARY:Tracker S04E04 - \\nPurification\r\n" +
	"DESCRIPTION:When a woman disappears after helping a terrified teenage\r\n  runaway\\, Colter uncovers a disturbing case of abuse and\r\n" +
	"  embarks on a desperate search to save them both.\r\nURL:https://www.pogdesign.co.uk/cat/Tracker-summary\r\n" +
	"UID:TRACKER_4_4\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nDTSTART:20261102T020000\r\nSUMMARY:Tracker S04E05 - \\nNeed to Know\r\nUID:TRACKER_4_5\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nDTSTART:20261022T010000\r\nSUMMARY:Scrubs (2026) S02E05 - \\nMy Best Friend&#039\\;s Birthday\r\n" +
	"URL:https://www.pogdesign.co.uk/cat/Scrubs-2026-summary\r\nUID:SCRUBS2026_2_5\r\nEND:VEVENT\r\n" +
	"BEGIN:VEVENT\r\nDTSTART:20261022T045900\r\nSUMMARY:Brothers (2026) S01E06 - \\nThe Dance\r\nUID:BROTHERS2026_1_6\r\nEND:VEVENT\r\n" +
	"END:VCALENDAR\r\n"

func TestCATRealExport(t *testing.T) {
	rows, err := ParseCATCalendar(pzRealExport)
	require.NoError(t, err)
	assert.Equal(t, []string{"The Simpsons", "Tracker", "Scrubs", "Brothers"}, pzTitles(rows))
	assert.Equal(t, []*int{nil, nil, ptr(2026), ptr(2026)}, []*int{rows[0].Year, rows[1].Year, rows[2].Year, rows[3].Year})
	assert.Equal(t, []*bool{ptr(true), ptr(true), nil, nil},
		[]*bool{rows[0].NameOnly, rows[1].NameOnly, rows[2].NameOnly, rows[3].NameOnly})
	assert.Equal(t, []*Airing{
		{Season: 38, Episode: 4, Day: "2026-10-26"},
		{Season: 4, Episode: 4, Day: "2026-10-26"},
		{Season: 2, Episode: 5, Day: "2026-10-22"},
		{Season: 1, Episode: 6, Day: "2026-10-22"},
	}, []*Airing{rows[0].Airing, rows[1].Airing, rows[2].Airing, rows[3].Airing})
	got, err := DetectFormat(pzRealExport)
	require.NoError(t, err)
	assert.Equal(t, core.SourceCATICS, got)
}

// MARK: Netflix (NetflixImportTests)

func TestNetflixTitles(t *testing.T) {
	show := func(title string, season int, name string) NetflixEntry {
		return NetflixEntry{Type: core.MediaShow, Title: title, Episode: &NamedEpisode{Season: &season, Name: name}}
	}
	movie := func(title string) NetflixEntry { return NetflixEntry{Type: core.MediaMovie, Title: title} }
	cases := map[string]NetflixEntry{
		"Breaking Bad: Season 1: Pilot":                                      show("Breaking Bad", 1, "Pilot"),
		"Baby Reindeer: Limited Series: Episode 3":                           show("Baby Reindeer", 1, "Episode 3"),
		"Stranger Things: Stranger Things 4: Chapter One: The Hellfire Club": show("Stranger Things", 4, "Chapter One: The Hellfire Club"),
		"Money Heist: Part 5: Episode 1":                                     show("Money Heist", 5, "Episode 1"),
		"Star Wars: Andor: Season 2: One Year Later":                         show("Star Wars: Andor", 2, "One Year Later"),
		"La Casa de Papel: Temporada 2: Episodio 3":                          show("La Casa de Papel", 2, "Episodio 3"),
		"Mission: Impossible - Fallout":                                      movie("Mission: Impossible - Fallout"),
		"Glass Onion: A Knives Out Mystery":                                  movie("Glass Onion: A Knives Out Mystery"),
		"Roma":                                                               movie("Roma"),
	}
	for raw, want := range cases {
		assert.Equal(t, want, NetflixEntryOf(raw), raw)
	}
}

func TestNetflixDates(t *testing.T) {
	us := NetflixDateOrderOf([]string{"1/23/24", "2/3/24"})
	assert.Equal(t, NetflixMonthFirst, us)
	assert.Equal(t, "2024-01-23", pzDay(NetflixDay("1/23/24", us)))
	eu := NetflixDateOrderOf([]string{"03/02/2024", "23/01/2024"})
	assert.Equal(t, NetflixDayFirst, eu)
	assert.Equal(t, "2024-02-03", pzDay(NetflixDay("03/02/2024", eu)))
	assert.Equal(t, "2024-01-23", pzDay(NetflixDay("2024-01-23", us)))
	assert.Equal(t, "2024-01-23", pzDay(NetflixDay("23.01.2024", eu)))
	assert.Nil(t, NetflixDay("yesterday", us))
}

func TestNetflixRows(t *testing.T) {
	rows, err := ParseNetflix(ParseCSV(`Title,Date
"Breaking Bad: Season 1: Gray Matter",3/2/21
"Breaking Bad: Season 1: Pilot",3/1/21
"Roma",6/5/23
"Breaking Bad: Season 1: Pilot",12/30/20
"Roma",1/5/19`))
	require.NoError(t, err)
	assert.Equal(t, []string{"Breaking Bad", "Roma"}, pzTitles(rows))
	assert.Equal(t, core.MediaShow, rows[0].Type)
	assert.Equal(t, pzStatus(core.StatusInProgress), rows[0].Status)
	assert.Equal(t, ptr(true), rows[0].NameOnly)
	one := 1
	assert.Equal(t, []NamedEpisode{{Season: &one, Name: "Gray Matter"}, {Season: &one, Name: "Pilot"}}, rows[0].NamedEpisodes)
	assert.Equal(t, []*int{ptr(2020), ptr(2019)}, []*int{rows[0].NotAfter, rows[1].NotAfter})
	assert.Equal(t, core.MediaMovie, rows[1].Type)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[1].Status)
	assert.Equal(t, "2023-06-05", pzDay(rows[1].FinishedAt))
	assert.Nil(t, rows[0].FinishedAt)
	assert.Nil(t, rows[1].NamedEpisodes, "a film names no episodes")
}

func TestNetflixFormat(t *testing.T) {
	_, err := ParseNetflix(ParseCSV("Profile Name,Start Time,Title\nAna,2024-01-01,Roma\n"))
	require.True(t, isFormatError(err))
	assert.Contains(t, err.Error(), "full account download")
	_, err = ParseNetflix(ParseCSV("Name,Year\nRoma,2018\n"))
	require.True(t, isFormatError(err))
	assert.Equal(t, "This does not look like a Netflix viewing activity file: it has no “Title”, “Date” column.", err.Error())
}

func TestNetflixEpisodeNames(t *testing.T) {
	ep := func(season, episode int, name string) catalog.Episode {
		return catalog.Episode{Season: season, Episode: episode, Name: &name}
	}
	episodes := []catalog.Episode{
		ep(0, 1, "Pilot"), ep(1, 1, "Pilot"), ep(1, 2, "Cat's in the Bag..."), ep(2, 1, "Seven Thirty-Seven"),
		ep(3, 1, "Untitled"), ep(4, 1, "Untitled"),
	}
	match := func(season *int, name string) *core.EpisodeKey {
		key, ok := catalog.MatchEpisodeName(NamedEpisode{Season: season, Name: name}, episodes)
		if !ok {
			return nil
		}
		return &key
	}
	one, two := 1, 2
	assert.Equal(t, &core.EpisodeKey{Season: 1, Episode: 1}, match(&one, "Pilot"))
	assert.Equal(t, &core.EpisodeKey{Season: 1, Episode: 2}, match(&one, "Cat’s in the Bag…"))
	assert.Equal(t, &core.EpisodeKey{Season: 2, Episode: 1}, match(&one, "Seven Thirty-Seven"), "Netflix's season 1")
	assert.Equal(t, &core.EpisodeKey{Season: 1, Episode: 1}, match(nil, "Pilot"), "specials need season 0")
	assert.Nil(t, match(&two, "Untitled"))
	assert.Nil(t, match(&one, "Not an episode"))
}

// MARK: TV Time (TVTimeImportTests)

const (
	pzSeriesEpisodesHeader = "series_tvdb_id,series_imdb_id,series_uuid,title,season,episode,tvdb_id," +
		"is_watched,watched_at,rewatch_count,special"
	pzSeriesHeader = "uuid,tvdb_id,imdb_id,title,status,created_at"
	pzMoviesHeader = "uuid,tvdb_id,imdb_id,title,year,created_at,watched_at,is_watched,rewatch_count"
	pzV2Header     = "created_at,user_id,key,updated_at,uuid,is_archived,is_followed,s_id,is_for_later," +
		"runtime,s_no,ep_no,ep_id,series_name,season_number,episode_number"
	pzV1Header = "watch_count,uuid,type,series_name,type-uuid-n,updated_at,user_id,created_at,series_id," +
		"release_date,alpha_range_key,movie_name,entity_type,season_number,episode_number,episode_id," +
		"watch_date_range_key"
	pzFollowedHeader = "user_id,tv_show_id,notification_type,notification_offset,created_at,updated_at," +
		"active,diffusion,folder_id,archived,tv_show_name"
	pzSeenHeader = "ts,show_name,episode_id,episode_season_number,episode_number,episode_name"
)

func pzTVTime(t *testing.T, text string) []Row {
	t.Helper()
	rows, err := ParseTVTime(ParseCSV(text))
	require.NoError(t, err)
	return rows
}

func TestTVTimeLayouts(t *testing.T) {
	cases := map[string]TVTimeLayout{
		pzSeriesEpisodesHeader: TVTimeSeriesEpisodes,
		pzSeriesHeader:         TVTimeSeries,
		pzMoviesHeader:         TVTimeMovies,
		pzV2Header:             TVTimeTrackingV2,
		pzV1Header:             TVTimeTrackingV1,
		pzFollowedHeader:       TVTimeFollowedShows,
		pzSeenHeader:           TVTimeSeenEpisodes,
	}
	for header, layout := range cases {
		assert.Equal(t, layout, TVTimeLayoutOf(ParseCSV(header).headerSet()), header)
		got, err := DetectFormat(header + "\n")
		require.NoError(t, err)
		assert.Equal(t, core.SourceTVTimeCSV, got, header)
	}
	_, err := ParseTVTime(ParseCSV("list_id,list_name,item_type,tvdb_id,uuid,name,custom_order\n"))
	require.True(t, isFormatError(err))
	assert.Equal(t, "This is not a TV Time file Aaru reads. Unzip the export and upload "+
		"tvtime-series-episodes.csv, tvtime-series.csv or tvtime-movies.csv from Export my data, "+
		"or tracking-prod-records-v2.csv, tracking-prod-records.csv, followed_tv_show.csv or "+
		"seen_episode.csv from a GDPR export, one at a time.", err.Error())
}

func TestTVTimeDates(t *testing.T) {
	seconds := func(raw string) int64 {
		d := TVTimeDate(&raw)
		if d == nil {
			return -1
		}
		return d.Unix()
	}
	assert.Equal(t, int64(1_570_160_622), seconds("2019-10-04 03:43:42"))
	assert.Equal(t, int64(1_570_160_622), seconds("2019-10-04T03:43:42Z"))
	assert.Equal(t, int64(1_570_160_622), seconds("2019-10-04T03:43:42.067614Z"))
	assert.Equal(t, int64(1_570_190_400), seconds("2019-10-04"))
	assert.Nil(t, TVTimeDate(ptr("0001-01-01")))
	assert.Nil(t, TVTimeDate(ptr("")))
}

func TestTVTimeSeriesEpisodes(t *testing.T) {
	rows := pzTVTime(t, pzSeriesEpisodesHeader+`
900001,,u-1,Glasshouse,1,2,7000002,true,2021-05-02 20:00:00,0,false
900001,,u-1,Glasshouse,1,1,7000001,true,2021-05-01 20:00:00,1,false
900001,,u-1,Glasshouse,2,1,7000003,false,,0,false
900001,,u-1,Glasshouse,1,1,7000001,true,2022-01-01 20:00:00,1,false
900002,tt0900002,u-2,Harbour Lights,1,1,7000010,false,,0,false
,,u-3,,1,1,,true,2021-01-01 00:00:00,0,false`)
	assert.Equal(t, []string{"Glasshouse", "Harbour Lights"}, pzTitles(rows))
	assert.Equal(t, core.ExternalIDs{TVDB: "900001"}, rows[0].IDs)
	assert.Equal(t, pzKeys(t, 1, 1, 1, 2), rows[0].Watched)
	assert.Nil(t, rows[0].Status, "ticks make it in progress when planned")
	assert.Equal(t, ptr(2021), rows[0].NotAfter)
	assert.Equal(t, ptr(true), rows[0].NameOnly)
	assert.Equal(t, core.ExternalIDs{IMDB: "tt0900002", TVDB: "900002"}, rows[1].IDs)
	assert.Nil(t, rows[1].Watched)
	assert.Equal(t, pzStatus(core.StatusWishlist), rows[1].Status)
}

func TestTVTimeSeries(t *testing.T) {
	rows := pzTVTime(t, pzSeriesHeader+`
u-1,900011,,Northbound,continuing,2018-12-18T12:39:15Z
u-2,900012,,Paper Moons,up_to_date,2025-03-20T10:15:42.067614Z
u-3,900013,-1,Quiet Hours,not_started_yet,2018-09-08T10:16:19Z
u-4,900014,,Red Tide,stopped,2019-01-01T00:00:00Z
u-5,900015,,Salt Road,something_new,2019-01-01T00:00:00Z`)
	ip := pzStatus(core.StatusInProgress)
	assert.Equal(t, []*core.LibraryStatus{ip, ip, pzStatus(core.StatusWishlist), pzStatus(core.StatusDropped), nil}, pzStatuses(rows))
	assert.Equal(t, core.ExternalIDs{TVDB: "900013"}, rows[2].IDs, "-1 is no IMDb id")
}

func TestTVTimeMovies(t *testing.T) {
	rows := pzTVTime(t, pzMoviesHeader+`
u-1,130001,tt0130001,The Long Field,2020,2022-03-18T00:03:26Z,2022-03-18T00:03:26Z,true,0
u-2,130002,-1,Tin Lanterns,2017,2019-09-10T08:01:29Z,,false,0
u-3,130003,,Nameless,,2019-09-10T08:01:29Z,,false,0
u-4,130001,tt0130001,The Long Field,2020,2023-01-01T00:00:00Z,2023-01-01T00:00:00Z,true,1`)
	assert.Equal(t, []string{"The Long Field", "Tin Lanterns"}, pzTitles(rows))
	assert.Equal(t, core.ExternalIDs{IMDB: "tt0130001", TVDB: "130001"}, rows[0].IDs)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[0].Status)
	assert.Equal(t, TVTimeDate(ptr("2022-03-18T00:03:26Z")), rows[0].FinishedAt)
	assert.True(t, rows[1].IDs.IsEmpty())
	assert.Equal(t, ptr(2017), rows[1].Year)
	assert.Equal(t, pzStatus(core.StatusWishlist), rows[1].Status)
	assert.Nil(t, rows[1].FinishedAt)
	assert.Equal(t, ptr("tvdb:130002"), rows[1].SourceKey)
}

func TestTVTimeTrackingV2(t *testing.T) {
	rows := pzTVTime(t, pzV2Header+`
2021-11-12 17:11:33,0,tracking-stats,2026-06-04 14:04:56,,,,,,,,,,,,
2024-11-02 11:53:58,0,watch-episode-aaa-111,2024-11-02 11:53:58,,,,900021,,2520,1,5,9000001,Treason Bay,,
2016-08-10 16:48:22,0,watch-episode-aaa-112,2016-08-10 16:48:22,,,,900021,,,,,9000002,Treason Bay,1,4
2017-01-01 10:00:00,0,rewatch-episode-aaa-113,2017-01-01 10:00:00,,,,900021,,,1,5,9000001,Treason Bay,,
2020-01-01 10:00:00,0,user-series-900021,2020-01-01 10:00:00,u-1,false,true,900021,false,,,,,Treason Bay,,
2020-01-01 10:00:00,0,user-series-900022,2020-01-01 10:00:00,u-2,false,false,900022,true,,,,,Umber,,
2020-01-01 10:00:00,0,user-series-900023,2020-01-01 10:00:00,u-3,true,true,900023,false,,,,,Vantage,,
2020-01-01 10:00:00,0,user-series-900024,2020-01-01 10:00:00,u-4,false,false,900024,false,,,,,Unfollowed,,`)
	assert.Equal(t, []string{"Treason Bay", "Umber", "Vantage"}, pzTitles(rows))
	assert.Equal(t, pzKeys(t, 1, 4, 1, 5), rows[0].Watched)
	assert.Nil(t, rows[0].Status)
	assert.Equal(t, ptr(2016), rows[0].NotAfter)
	assert.Equal(t, pzStatus(core.StatusWishlist), rows[1].Status, "watch later")
	assert.Equal(t, pzStatus(core.StatusDropped), rows[2].Status, "archived")
}

func TestTVTimeTrackingV1(t *testing.T) {
	rows := pzTVTime(t, pzV1Header+`
1,m-1,watch,,watch-m-1-0,,0,2022-04-10,,2017-10-12,watch-alpha-june,June,movie,,,,watch-date-1649590015
,m-2,towatch,,towatch-m-2-0,,0,2022-04-11 11:26:55,,0001-01-01,towatch-alpha-sky-sailors,하늘 선원,movie,,,,
1,m-2,watch,,watch-m-2-0,,0,2023-02-01 11:26:55,,0001-01-01,watch-alpha-sky-sailors,하늘 선원,movie,,,,
1,e-1,watch,Treason Bay,watch-e-1-0,,0,2021-10-10 11:49:11,,,,,episode,1,1,9000003,`)
	assert.Equal(t, []string{"June", "sky sailors"}, pzTitles(rows))
	assert.Equal(t, ptr(2017), rows[0].Year)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[0].Status)
	assert.Nil(t, rows[0].NameOnly)
	assert.Equal(t, time.Unix(1_649_590_015, 0).UTC(), *rows[0].FinishedAt)
	assert.Nil(t, rows[1].Year)
	assert.Equal(t, ptr(true), rows[1].NameOnly)
	assert.Equal(t, ptr(2023), rows[1].NotAfter)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[1].Status, "watched after it was on the list")
}

func TestTVTimeFollowedAndSeen(t *testing.T) {
	followed := pzTVTime(t, pzFollowedHeader+`
1,900031,2,1440,2021-03-15 20:42:59,,0,,,0,Willow Creek
1,900032,2,1440,2021-03-15 20:42:59,,0,,,1,Xanadu Line`)
	assert.Equal(t, []*core.LibraryStatus{pzStatus(core.StatusWishlist), pzStatus(core.StatusDropped)}, pzStatuses(followed))
	assert.Equal(t, core.ExternalIDs{TVDB: "900031"}, followed[0].IDs)

	seen := pzTVTime(t, pzSeenHeader+`
1633866551,Yarrow,9000041,1,2,Second
1570160622,Yarrow,9000040,1,1,First`)
	require.Len(t, seen, 1)
	assert.True(t, seen[0].IDs.IsEmpty())
	assert.Equal(t, ptr(true), seen[0].NameOnly)
	assert.Equal(t, pzKeys(t, 1, 1, 1, 2), seen[0].Watched)
	assert.Equal(t, ptr(2019), seen[0].NotAfter)
}

// MARK: Anime and manga lists (AnimeListImportTests, MangaImportTests)

const pzMALExport = `<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
  <myinfo><user_name>someone</user_name></myinfo>
  <anime>
    <series_animedb_id>52991</series_animedb_id>
    <series_title><![CDATA[Sousou no Frieren]]></series_title>
    <series_type>TV</series_type>
    <series_episodes>28</series_episodes>
    <my_watched_episodes>12</my_watched_episodes>
    <my_score>9</my_score>
    <my_status>Watching</my_status>
    <my_finish_date>0000-00-00</my_finish_date>
  </anime>
  <anime>
    <series_animedb_id>5114</series_animedb_id>
    <series_title>Fullmetal Alchemist: Brotherhood &amp; More</series_title>
    <series_type>TV</series_type>
    <series_episodes>64</series_episodes>
    <my_watched_episodes>0</my_watched_episodes>
    <my_score>0</my_score>
    <my_status>Completed</my_status>
    <my_finish_date>2020-05-01</my_finish_date>
  </anime>
  <anime>
    <series_animedb_id>199</series_animedb_id>
    <series_title><![CDATA[Sen to Chihiro no Kamikakushi]]></series_title>
    <series_type>Movie</series_type>
    <series_episodes>1</series_episodes>
    <my_watched_episodes>0</my_watched_episodes>
    <my_score>10</my_score>
    <my_status>Plan to Watch</my_status>
  </anime>
</myanimelist>`

const pzMALMangaExport = `<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
  <myinfo><user_name>someone</user_name><user_export_type>2</user_export_type></myinfo>
  <manga>
    <manga_mangadb_id>2</manga_mangadb_id>
    <manga_title><![CDATA[Berserk]]></manga_title>
    <manga_volumes>0</manga_volumes>
    <manga_chapters>0</manga_chapters>
    <my_read_volumes>12</my_read_volumes>
    <my_read_chapters>112</my_read_chapters>
    <my_score>10</my_score>
    <my_status>Reading</my_status>
    <my_finish_date>0000-00-00</my_finish_date>
  </manga>
  <manga>
    <manga_mangadb_id>656</manga_mangadb_id>
    <manga_title><![CDATA[Vagabond]]></manga_title>
    <manga_volumes>37</manga_volumes>
    <manga_chapters>327</manga_chapters>
    <my_read_volumes>0</my_read_volumes>
    <my_read_chapters>0</my_read_chapters>
    <my_score>0</my_score>
    <my_status>Completed</my_status>
    <my_finish_date>2019-08-02</my_finish_date>
  </manga>
  <manga>
    <manga_mangadb_id>1706</manga_mangadb_id>
    <manga_title>JoJo no Kimyou na Bouken</manga_title>
    <manga_volumes>0</manga_volumes>
    <manga_chapters>0</manga_chapters>
    <my_read_volumes>0</my_read_volumes>
    <my_read_chapters>0</my_read_chapters>
    <my_score>0</my_score>
    <my_status>Plan to Read</my_status>
  </manga>
</myanimelist>`

func TestMALParser(t *testing.T) {
	rows, err := ParseMALList(pzMALExport)
	require.NoError(t, err)
	require.Len(t, rows, 3)
	assert.Equal(t, []string{"52991", "5114", "199"}, []string{rows[0].IDs.MAL, rows[1].IDs.MAL, rows[2].IDs.MAL})
	assert.Equal(t, []*core.LibraryStatus{pzStatus(core.StatusInProgress), pzStatus(core.StatusFinished), pzStatus(core.StatusWishlist)}, pzStatuses(rows))
	assert.Equal(t, []*float64{ptr(9.0), nil, ptr(10.0)}, []*float64{rows[0].Rating, rows[1].Rating, rows[2].Rating})
	assert.Len(t, rows[0].Watched, 12)
	assert.Len(t, rows[1].Watched, 64)
	assert.Equal(t, "Fullmetal Alchemist: Brotherhood & More", rows[1].Title)
	assert.Equal(t, catalog.ParseDay(ptr("2020-05-01")), rows[1].FinishedAt)
	assert.Equal(t, core.MediaMovie, rows[2].Type)
	assert.Nil(t, rows[2].Watched)
	assert.Equal(t, ptr("mal:52991"), rows[0].SourceKey)
	_, err = ParseMALList("Const,Title\ntt1,X")
	require.True(t, isFormatError(err))
	assert.Equal(t, "This does not look like a MyAnimeList export. Export your anime or manga list from "+
		"MAL and upload the .xml (or .xml.gz) file.", err.Error())
}

func TestAnimeOnHoldMapping(t *testing.T) {
	for _, word := range []string{"On-Hold", "onhold", "3", "PAUSED"} {
		assert.Equal(t, pzStatus(core.StatusOnHold), AnimeListStatus(word), word)
	}
	for _, word := range []string{"Watching", "CURRENT", "REPEATING", "1", "Reading"} {
		assert.Equal(t, pzStatus(core.StatusInProgress), AnimeListStatus(word), word)
	}
	for _, r := range malAnimeRows(pzMALExport) {
		assert.Equal(t, ptr(true), r.KnowsOnHold, "MAL has on hold, so its watching may resume one")
	}
}

func TestMALMangaParser(t *testing.T) {
	rows, err := ParseMALList(pzMALMangaExport)
	require.NoError(t, err)
	require.Len(t, rows, 3)
	for _, r := range rows {
		assert.Equal(t, core.MediaManga, r.Type)
		assert.Nil(t, r.Watched)
	}
	assert.Equal(t, []string{"2", "656", "1706"}, []string{rows[0].IDs.MAL, rows[1].IDs.MAL, rows[2].IDs.MAL})
	assert.Equal(t, []*string{ptr("mal-manga:2"), ptr("mal-manga:656"), ptr("mal-manga:1706")},
		[]*string{rows[0].SourceKey, rows[1].SourceKey, rows[2].SourceKey})
	assert.Equal(t, []*core.LibraryStatus{pzStatus(core.StatusInProgress), pzStatus(core.StatusFinished), pzStatus(core.StatusWishlist)}, pzStatuses(rows))
	assert.Equal(t, ptr(112), rows[0].MangaChapter)
	assert.Equal(t, ptr(12), rows[0].MangaVolume)
	assert.Equal(t, ptr(10.0), rows[0].Rating)
	assert.Equal(t, ptr(327), rows[1].MangaChapter)
	assert.Equal(t, ptr(37), rows[1].MangaVolume)
	assert.Equal(t, catalog.ParseDay(ptr("2019-08-02")), rows[1].FinishedAt)
	assert.Nil(t, rows[2].MangaChapter)
	assert.Nil(t, rows[2].MangaVolume)

	both := strings.Replace(pzMALExport, "</myanimelist>",
		"<manga><manga_mangadb_id>2</manga_mangadb_id><manga_title>Berserk</manga_title></manga></myanimelist>", 1)
	mixed, err := ParseMALList(both)
	require.NoError(t, err)
	types := make([]core.MediaType, len(mixed))
	for i, r := range mixed {
		types[i] = r.Type
	}
	assert.Equal(t, []core.MediaType{core.MediaShow, core.MediaShow, core.MediaMovie, core.MediaManga}, types,
		"one file may hold both lists")
}

// MARK: Merge decisions the parsers' rows lean on (GoodreadsImportTests, MangaImportTests)

func TestOwnedIsNeverCleared(t *testing.T) {
	row := Row{Type: core.MediaBook, Title: "Owned", Status: pzStatus(core.StatusFinished), Lists: []string{}}
	state := &library.ImportItemState{
		ItemID: uuid.New(), Fields: library.ItemFields{Status: core.StatusFinished, IsOwned: true},
		Watched: map[core.EpisodeKey]bool{},
	}
	decision := Decide(row, state)
	assert.Equal(t, OutcomeSkip, decision.Outcome)
	assert.Nil(t, decision.Fields)
}

func TestMangaProgressOnlyMovesForward(t *testing.T) {
	row := Row{
		Type: core.MediaManga, Title: "Berserk", IDs: core.ExternalIDs{MAL: "2"}, Status: pzStatus(core.StatusInProgress),
		Lists: []string{}, MangaChapter: ptr(100), MangaVolume: ptr(15),
	}
	state := &library.ImportItemState{
		ItemID:  uuid.New(),
		Fields:  library.ItemFields{Status: core.StatusInProgress, MangaChapter: ptr(120), MangaVolume: ptr(12)},
		Watched: map[core.EpisodeKey]bool{},
	}
	decision := Decide(row, state)
	require.NotNil(t, decision.Fields)
	assert.Equal(t, ptr(120), decision.Fields.MangaChapter, "chapter 100 is behind 120")
	assert.Equal(t, ptr(15), decision.Fields.MangaVolume)
	assert.Equal(t, ptr("Adds the volume 15."), decision.Reason)
}
