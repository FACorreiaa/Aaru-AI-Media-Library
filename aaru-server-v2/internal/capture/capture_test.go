package capture

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// CaptureTests.links
func TestCatalogLinksNameTheirTitleByIDAndExportSitesPointAtTheirCSV(t *testing.T) {
	title := func(raw string) Title {
		t.Helper()
		link := ParseLink(raw)
		require.Equal(t, LinkTitle, link.Kind, raw)
		return *link.Title
	}
	movie := title("https://www.themoviedb.org/movie/603-the-matrix")
	assert.Equal(t, core.MediaMovie, movie.Type)
	assert.Equal(t, "603", movie.IDs.TMDB)
	assert.Equal(t, "https://www.themoviedb.org/movie/603-the-matrix", *movie.SourceKey)
	assert.Equal(t, "www.themoviedb.org/movie/603-the-matrix", movie.Title)
	show := title("https://www.themoviedb.org/tv/1396?language=en")
	assert.Equal(t, core.MediaShow, show.Type)
	assert.Equal(t, "1396", show.IDs.TMDB)
	anime := title("https://anilist.co/anime/21/One-Piece/")
	assert.Equal(t, core.MediaShow, anime.Type)
	assert.Equal(t, "21", anime.IDs.AniList)
	assert.Equal(t, "anilist.co/anime/21/One-Piece", anime.Title, "no trailing slash, as URL.path")
	book := title("https://openlibrary.org/works/OL45804W/Fantastic_Mr_Fox")
	assert.Equal(t, core.MediaBook, book.Type)
	assert.Equal(t, "OL45804W", book.IDs.OpenLibrary)
	manga := title("https://anilist.co/manga/30013/One-Piece")
	assert.Equal(t, core.MediaManga, manga.Type)
	assert.Equal(t, "30013", manga.IDs.AniList)

	assert.Equal(t, Link{Kind: LinkUseCSV, Site: "Letterboxd"}, ParseLink("https://letterboxd.com/someone/list/films/"))
	assert.Equal(t, Link{Kind: LinkUseCSV, Site: "Letterboxd"}, ParseLink("https://boxd.it/abc"))
	assert.Equal(t, Link{Kind: LinkUseCSV, Site: "IMDb"}, ParseLink("https://m.imdb.com/title/tt0133093/"))
	for _, other := range []string{
		"https://www.themoviedb.org/person/6384", "https://openlibrary.org/authors/OL34184A",
		"https://example.com/movie/603", "ftp://themoviedb.org/movie/1", "not a link",
	} {
		assert.Equal(t, LinkUnsupported, ParseLink(other).Kind, other)
	}
}

// CaptureTests.reportedRows
func TestReportedTitlesAreDeduplicatedAndAnimeIsAShow(t *testing.T) {
	titles := Rows(json.RawMessage(`{"titles":[
		{"title":" Arrival ","year":2016,"type":"movie"},
		{"title":"arrival","year":2016,"type":"movie"},
		{"title":"Frieren","type":"anime"},
		{"title":"Dune","type":"book","year":12},
		{"title":"","type":"movie"},
		{"type":"movie"}]}`))
	var names []string
	var types []core.MediaType
	var years []*int
	for _, title := range titles {
		names, types, years = append(names, title.Title), append(types, title.Type), append(years, title.Year)
		assert.True(t, title.IDs.IsEmpty())
	}
	assert.Equal(t, []string{"Arrival", "Frieren", "Dune"}, names)
	assert.Equal(t, []core.MediaType{core.MediaMovie, core.MediaShow, core.MediaBook}, types)
	assert.Equal(t, []*int{new(2016), nil, nil}, years)

	items := make([]string, 80)
	for i := range items {
		items[i] = fmt.Sprintf(`{"title":"Film %d","type":"movie"}`, i)
	}
	assert.Len(t, Rows(json.RawMessage(`{"titles":[`+strings.Join(items, ",")+`]}`)), MaxTitles)
	assert.Empty(t, Rows(json.RawMessage(`{}`)))
}

// CaptureTests.toolChoiceAndCost: the forced tool goes out as tool_choice, nothing else is sampled.
func TestTheRequestForcesTheToolAndSendsNoSamplingParameters(t *testing.T) {
	req := Request(Content{Text: "Heat"})
	assert.Equal(t, ToolName, req.ToolChoice)
	body := model.AnthropicBody(req, "claude-haiku-5-5", "low")
	assert.Equal(t, map[string]any{"type": "tool", "name": "report_titles"}, toMap(t, body["tool_choice"]))
	for _, banned := range []string{"temperature", "top_p", "top_k"} {
		assert.NotContains(t, body, banned)
	}
	var schema map[string]any
	require.NoError(t, json.Unmarshal(Tool.InputSchema, &schema))
	assert.Equal(t, []any{"titles"}, schema["required"])
	image := Request(Content{Image: []byte{1}, MediaType: "image/png"})
	assert.Len(t, image.Turns[0].Content, 2)
}

func toMap(t *testing.T, v any) map[string]any {
	t.Helper()
	data, err := json.Marshal(v)
	require.NoError(t, err)
	var out map[string]any
	require.NoError(t, json.Unmarshal(data, &out))
	return out
}
