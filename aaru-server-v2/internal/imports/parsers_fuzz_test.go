package imports

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/stremioapi"
	"errors"
	"strings"
	"testing"
)

// Fuzz targets for the parsers that read an uploaded file (HLT-002). They need no database. The
// seeds are the fixtures of parsers_test.go; testdata/fuzz holds any input that once crashed.
//
//	go test -run='^$' -fuzz=FuzzParseIMDb -fuzztime=45s ./internal/imports/
//
// The property is the same for every parser: it never panics, and when it refuses a file it says
// why with a FormatError, the 422 the person reads.

// TestCharactersKeepInvalidBytes is the crash fuzzing found (testdata/fuzz/FuzzParseCATList): an
// invalid UTF-8 byte is one byte wide, so it is one piece of one byte, and every byte of the input
// is in exactly one piece.
func TestCharactersKeepInvalidBytes(t *testing.T) {
	for text, want := range map[string][]string{
		"\xff":        {"\xff"},
		"a\x8f":       {"a", "\x8f"},
		"\xffab":      {"\xff", "a", "b"},
		"e\u0301\xbb": {"e\u0301", "\xbb"},
		"\u200d\xff":  {"\u200d\xff"},
	} {
		got := characters(text)
		if strings.Join(got, "") != text || len(got) != len(want) {
			t.Fatalf("characters(%q) = %q, want %q", text, got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("characters(%q) = %q, want %q", text, got, want)
			}
		}
	}
}

// FuzzCharacters: the pieces put back together are the input, and charPrefix is a prefix of it.
func FuzzCharacters(f *testing.F) {
	for _, s := range []string{"\xff", "a\x8f", "e\u0301", "🇵🇹🇧🇷", "👩\u200d💻", "a\r\nb", "\uFE0F"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, text string) {
		if got := strings.Join(characters(text), ""); got != text {
			t.Fatalf("characters(%q) joins to %q", text, got)
		}
		if p := charPrefix(text, 3); !strings.HasPrefix(text, p) {
			t.Fatalf("charPrefix(%q, 3) = %q", text, p)
		}
	})
}

func fuzzRequireFormatError(t *testing.T, err error) {
	t.Helper()
	if err == nil {
		return
	}
	var f *FormatError
	if !errors.As(err, &f) {
		t.Fatalf("a parser failed with %T (%v), not a FormatError", err, err)
	}
}

// fuzzSource fuzzes Parse for one source, with the file name as a second input.
func fuzzSource(f *testing.F, source core.ImportSource, seeds ...string) {
	f.Helper()
	for _, s := range seeds {
		f.Add(s, "")
		f.Add(s, "watchlist.csv")
	}
	f.Fuzz(func(t *testing.T, text, filename string) {
		var name *string
		if filename != "" {
			name = &filename
		}
		_, err := Parse(text, source, name)
		fuzzRequireFormatError(t, err)
	})
}

const (
	fzIMDbRatings = "Const,Your Rating,Date Rated,Title,Title Type,Year\n" +
		"tt0133093,9,2024-01-02,The Matrix,Movie,1999\n" +
		"tt0944947,10,2024-01-03,Game of Thrones,TV Series,2011\n" +
		"tt1480055,8,2024-01-04,Winter Is Coming,TV Episode,2011"
	fzIMDbWatchlist = "Position,Const,Title,Title Type,Year\n1,tt0133093,The Matrix,Movie,1999\n"
	fzLetterboxd    = "Date,Name,Year,Letterboxd URI,Rating,Watched Date\n" +
		"2024-02-01,Heat,1995,https://boxd.it/abc,4.5,2024-01-31\n" +
		"2024-02-02,Crash,2004,https://boxd.it/def,0.5,"
	fzGoodreads = "Book Id,Title,Author,ISBN,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Date Read,Original Publication Year\n" +
		"1,Dune,Frank Herbert,\"=\"\"0441172717\"\"\",\"=\"\"9780441172719\"\"\",4,read,\"favorites, read, sci-fi\",2024/03/01,1965\n" +
		"2,No ISBN Book,Some Author,\"=\"\"\"\"\",\"=\"\"\"\"\",0,to-read,to-read,,2001\n" +
		"3,Reading Now,An Author,,,0,currently-reading,currently-reading,,2010"
	fzGoodreadsMore = "Book Id,Title,Author,Exclusive Shelf,Bookshelves,My Review,Private Notes,Owned Copies\n" +
		"1,\"Leviathan Wakes (The Expanse, #1)\",James S.A. Corey,dnf,dnf,\"Slow.<br/>Gave up &amp; moved on.\",Hidden,1\n" +
		"2,\"Dune (Deluxe Edition)\",Frank Herbert,Did Not Finish,did-not-finish,,\"Private, only\",0\n" +
		"3,\"Small Gods (Discworld, #13; Omnieni #1)\",Terry Pratchett,abandoned,,<p> </p>,,\n" +
		"4,Plain,Someone,Dropped,,,,x"
	fzGeneric = "Title,Release Date,Media Type,IMDb ID,TMDB ID,Status,My Rating,Watched At\n" +
		"Arrival,2016-11-11,Movie,tt2543164,329865,Completed,4.5,2024-02-01\n" +
		"Severance,2022,TV Show,,95396,Watching,5,\n" +
		"Some Book,2001,,,,Want to Read,,\n" +
		",,,,,,,"
	fzGenericScores = "Title,Score\nA,85\nB,\"7,5\"\nC,3\n"
	fzGenericISBN   = "ISBN,Author\n9780441172719,Frank Herbert\n"
	fzNetflix       = "Title,Date\n" +
		"\"Breaking Bad: Season 1: Gray Matter\",3/2/21\n" +
		"\"Breaking Bad: Season 1: Pilot\",3/1/21\n" +
		"\"Roma\",6/5/23\n" +
		"\"Stranger Things: Stranger Things 4: Chapter One: The Hellfire Club\",23.01.2024\n" +
		"\"Money Heist: Part 5: Episode 1\",2024-01-23\n" +
		"\"Baby Reindeer: Limited Series: Episode 3\",03/02/2024"
	fzCATList     = "Severance\n- The Bear\n3. Brothers (2026)\n\n• severance\nSlow Horses\r\n"
	fzCATCalendar = "BEGIN:VCALENDAR\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY;LANGUAGE=en:Law & Order\\, Special Victims Unit: S27E\r\n 03 - Part One\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Doctor Who (2023) - 2x05\r\nDTSTART;VALUE=DATE:20261031\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nDTSTART:20261026T000000\r\nSUMMARY:The Simpsons S38E04 - \\nTreehouse of Horror XXXVII\r\nEND:VEVENT\r\n" +
		"BEGIN:VEVENT\r\nSUMMARY:Season premiere night\r\nEND:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
)

var fzTVTime = []string{
	pzSeriesEpisodesHeader + "\n" +
		"900001,,u-1,Glasshouse,1,2,7000002,true,2021-05-02 20:00:00,0,false\n" +
		"900001,,u-1,Glasshouse,1,1,7000001,true,2021-05-01 20:00:00,1,false\n" +
		"900002,tt0900002,u-2,Harbour Lights,1,1,7000010,false,,0,false\n" +
		",,u-3,,1,1,,true,2021-01-01 00:00:00,0,false",
	pzSeriesHeader + "\n" +
		"u-1,900011,,Northbound,continuing,2018-12-18T12:39:15Z\n" +
		"u-3,900013,-1,Quiet Hours,not_started_yet,2018-09-08T10:16:19Z\n" +
		"u-4,900014,,Red Tide,stopped,2019-01-01T00:00:00Z",
	pzMoviesHeader + "\n" +
		"u-1,130001,tt0130001,The Long Field,2020,2022-03-18T00:03:26Z,2022-03-18T00:03:26Z,true,0\n" +
		"u-2,130002,-1,Tin Lanterns,2017,2019-09-10T08:01:29Z,,false,0\n" +
		"u-3,130003,,Nameless,,2019-09-10T08:01:29Z,,false,0",
	pzV2Header + "\n" +
		"2024-11-02 11:53:58,0,watch-episode-aaa-111,2024-11-02 11:53:58,,,,900021,,2520,1,5,9000001,Treason Bay,,\n" +
		"2016-08-10 16:48:22,0,watch-episode-aaa-112,2016-08-10 16:48:22,,,,900021,,,,,9000002,Treason Bay,1,4\n" +
		"2020-01-01 10:00:00,0,user-series-900022,2020-01-01 10:00:00,u-2,false,false,900022,true,,,,,Umber,,\n" +
		"2020-01-01 10:00:00,0,user-series-900023,2020-01-01 10:00:00,u-3,true,true,900023,false,,,,,Vantage,,",
	pzV1Header + "\n" +
		"1,m-1,watch,,watch-m-1-0,,0,2022-04-10,,2017-10-12,watch-alpha-june,June,movie,,,,watch-date-1649590015\n" +
		",m-2,towatch,,towatch-m-2-0,,0,2022-04-11 11:26:55,,0001-01-01,towatch-alpha-sky-sailors,하늘 선원,movie,,,,\n" +
		"1,e-1,watch,Treason Bay,watch-e-1-0,,0,2021-10-10 11:49:11,,,,,episode,1,1,9000003,",
	pzFollowedHeader + "\n" +
		"1,900031,2,1440,2021-03-15 20:42:59,,0,,,0,Willow Creek\n" +
		"1,900032,2,1440,2021-03-15 20:42:59,,0,,,1,Xanadu Line",
	pzSeenHeader + "\n" +
		"1633866551,Yarrow,9000041,1,2,Second\n" +
		"1570160622,Yarrow,9000040,1,1,First",
}

func FuzzParseCSV(f *testing.F) {
	for _, s := range []string{
		"\uFEFFTitle,Note\r\n\"Dune, Part One\",\"He said \"\"hi\"\"\"\r\nPlain,x\r\n",
		fzIMDbRatings, fzGoodreads, fzNetflix, "\"unterminated,\n\"\"", "a\rb\r\n\n,,\n",
	} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, text string) {
		table := ParseCSV(text)
		for _, record := range table.Records {
			if len(record) > len(table.Headers) {
				t.Fatalf("a record has %d fields for %d headers", len(record), len(table.Headers))
			}
		}
	})
}

func FuzzParseIMDb(f *testing.F) {
	fuzzSource(f, core.SourceIMDbCSV, fzIMDbRatings, fzIMDbWatchlist)
}

func FuzzParseLetterboxd(f *testing.F) {
	fuzzSource(f, core.SourceLetterboxdCSV, fzLetterboxd,
		"Date,Name,Year,Letterboxd URI\n2024-02-01,Heat,1995,https://boxd.it/abc\n")
}

func FuzzParseGoodreads(f *testing.F) {
	fuzzSource(f, core.SourceGoodreadsCSV, fzGoodreads, fzGoodreadsMore)
}

func FuzzParseGenericCSV(f *testing.F) {
	fuzzSource(f, core.SourceGenericCSV, fzGeneric, fzGenericScores, fzGenericISBN)
}

func FuzzParseNetflix(f *testing.F) {
	fuzzSource(f, core.SourceNetflixCSV, fzNetflix, "Title,Date\nRoma,1/5/19\n")
}

func FuzzParseTVTime(f *testing.F) {
	fuzzSource(f, core.SourceTVTimeCSV, fzTVTime...)
}

func FuzzParseMALList(f *testing.F) {
	fuzzSource(f, core.SourceMALXML, pzMALExport, pzMALMangaExport,
		"<myanimelist><anime><series_title>&#x1F600;&#99999999;&amp</series_title></anime></myanimelist>")
}

func FuzzParseCATList(f *testing.F) {
	fuzzSource(f, core.SourceCATList, fzCATList, "Severance\n"+string(make([]byte, 300)))
}

func FuzzParseCATCalendar(f *testing.F) {
	fuzzSource(f, core.SourceCATICS, fzCATCalendar, pzRealExport, "\uFEFFBEGIN:VCALENDAR\r\nEND:VCALENDAR")
}

// FuzzStremioRow fuzzes one Stremio library item, as the export-file fallback decodes it, through
// the mapper the link-code import shares.
func FuzzStremioRow(f *testing.F) {
	for _, s := range []string{
		`{"_id":"tt1","type":"movie","name":"tt1","removed":false,"temp":false,"state":{"timesWatched":1,"lastWatched":"2024-05-01T20:00:00.000Z"}}`,
		`{"_id":"tt2","type":"movie","name":"tt2","removed":false,"temp":false,"state":{"timeOffset":1200.0}}`,
		`{"_id":"tt5","type":"series","name":"tt5","removed":true,"temp":true,"state":{"watched":"tt5:1:1:1:eJxjBQAABgAG"}}`,
		`{"_id":"kitsu:7","type":"series","name":"kitsu:7","removed":false,"temp":false,"state":{"timeOffset":10}}`,
		`{"_id":42,"type":"movie"}`,
	} {
		f.Add(s)
	}
	f.Fuzz(func(_ *testing.T, raw string) {
		if item, ok := stremioapi.DecodeLibraryItem([]byte(raw)); ok {
			_ = StremioRows([]stremioapi.LibraryItem{item})
		}
	})
}

// FuzzDetectAndParse is source=auto: detect the format, then parse with what was detected.
func FuzzDetectAndParse(f *testing.F) {
	seeds := []string{
		fzIMDbRatings, fzLetterboxd, fzGoodreads, fzGeneric, fzNetflix, fzCATCalendar, pzRealExport,
		pzMALExport, "PK\x03\x04\x14\x00", "  [{\"ts\": 1}]", "<rss><channel/></rss>",
	}
	seeds = append(seeds, fzTVTime...)
	for _, s := range seeds {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, text string) {
		source, err := DetectFormat(text)
		fuzzRequireFormatError(t, err)
		if err != nil {
			return
		}
		_, err = Parse(text, source, nil)
		fuzzRequireFormatError(t, err)
	})
}
