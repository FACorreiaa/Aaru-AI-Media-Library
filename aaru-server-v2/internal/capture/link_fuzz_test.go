package capture

import (
	"encoding/json"
	"testing"
)

// FuzzParseLink fuzzes the catalog link a person sends as a capture (HLT-002). It must never
// panic, and only a LinkTitle carries a title.
func FuzzParseLink(f *testing.F) {
	for _, s := range []string{
		"https://www.themoviedb.org/movie/603-the-matrix", "https://www.themoviedb.org/tv/1396?language=en",
		"https://anilist.co/anime/21/One-Piece/", "https://openlibrary.org/works/OL45804W/Fantastic_Mr_Fox",
		"https://anilist.co/manga/30013/One-Piece", "https://letterboxd.com/someone/list/films/",
		"https://boxd.it/abc", "https://m.imdb.com/title/tt0133093/", "https://www.themoviedb.org/person/6384",
		"ftp://themoviedb.org/movie/1", "not a link", "https://anilist.co/anime/",
	} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, raw string) {
		link := ParseLink(raw)
		if (link.Kind == LinkTitle) != (link.Title != nil) {
			t.Fatalf("kind %v with title %v", link.Kind, link.Title)
		}
	})
}

// FuzzRows fuzzes the titles the model reports from a capture: its tool input is JSON the server
// did not write. It must never panic and never return more than MaxTitles.
func FuzzRows(f *testing.F) {
	for _, s := range []string{
		`{"titles":[{"title":"Dune","type":"movie","year":2021}]}`,
		`{"titles":[{"title":"One Piece","type":"anime"},{"title":"One Piece","type":"anime"}]}`,
		`{"titles":[{"title":"Berserk","type":"manga","year":1e300,"ids":{"anilist":"30002"}}]}`,
		`{"titles":null}`, `[]`, `{`,
	} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, raw string) {
		if titles := Rows(json.RawMessage(raw)); len(titles) > MaxTitles {
			t.Fatalf("%d titles, more than %d", len(titles), MaxTitles)
		}
	})
}
