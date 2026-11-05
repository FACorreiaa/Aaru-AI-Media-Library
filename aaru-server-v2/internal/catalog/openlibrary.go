package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"strconv"
	"strings"
	"time"
)

// OpenLibraryBaseURL is Open Library's API root.
const OpenLibraryBaseURL = "https://openlibrary.org"

const openLibraryFields = "key,title,first_publish_year,isbn,cover_i,author_name,number_of_pages_median"

// OpenLibrary is the Open Library adapter (CAT-003): book search and detail, ISBN
// normalized to ISBN-13, cover URLs referenced, never downloaded. Also Discover's
// trending books row.
type OpenLibrary struct {
	Client *provider.Client
	// UserAgent: Open Library asks API users to identify themselves.
	UserAgent string
	// BaseURL defaults to OpenLibraryBaseURL.
	BaseURL string
}

// Search finds books.
func (o *OpenLibrary) Search(ctx context.Context, query string, _ core.MediaType) ([]Hit, error) {
	var page openLibraryPage
	if err := o.get(ctx, "search.json", map[string]string{"q": query, "fields": openLibraryFields, "limit": "20"}, &page); err != nil {
		return nil, err
	}
	return page.hits(page.Docs), nil
}

// Hydrate is the book an Open Library work id or an ISBN identifies.
func (o *OpenLibrary) Hydrate(ctx context.Context, ids core.ExternalIDs, _ core.MediaType) (*Record, error) {
	var query map[string]string
	isbn := ""
	if ids.ISBN != "" {
		isbn = core.NormalizeISBN(ids.ISBN)
	}
	switch {
	case ids.OpenLibrary != "":
		query = map[string]string{"q": "key:/works/" + ids.OpenLibrary, "fields": openLibraryFields, "limit": "1"}
	case isbn != "":
		query = map[string]string{"isbn": isbn, "fields": openLibraryFields, "limit": "1"}
	default:
		return nil, nil // nil: not known
	}
	var page openLibraryPage
	if err := o.get(ctx, "search.json", query, &page); err != nil {
		return nil, err
	}
	if len(page.Docs) == 0 {
		return nil, nil // nil: not known
	}
	hit, ok := page.Docs[0].hit()
	if !ok {
		return nil, nil // nil: not known
	}
	// Keep the ISBN that resolved it: it is the key a later import will look up.
	if isbn != "" {
		hit.IDs.ISBN = isbn
	}
	hit.IDs = hit.IDs.Filling(ids)
	return &Record{Hit: hit, Genres: []string{}}, nil
}

// openLibrarySubjects are the subject each book row reads (BOOK-002). A subject comes in order of
// edition count, so the old and much-reprinted lead, and `published_in` changes nothing: `science`
// opens with Romeo and Juliet, where `popular_science` opens with Hawking and Bryson. History,
// biography and fantasy were no better than `science`, so they have no row.
var openLibrarySubjects = map[DiscoverList]string{
	ListBooksClassics: "classics",
	ListBooksSciFi:    "science_fiction",
	ListBooksScience:  "popular_science",
	ListBooksBusiness: "business",
}

// DiscoverLists are the rows Open Library serves.
func (o *OpenLibrary) DiscoverLists() []DiscoverList {
	return []DiscoverList{ListBooksTrending, ListBooksClassics, ListBooksSciFi, ListBooksScience, ListBooksBusiness}
}

// List is the weekly trending books, or a subject's books.
func (o *OpenLibrary) List(ctx context.Context, list DiscoverList, _ time.Time) ([]Hit, error) {
	if subject, ok := openLibrarySubjects[list]; ok {
		return o.subject(ctx, subject)
	}
	if list != ListBooksTrending {
		return nil, provider.NewError("openlibrary", provider.KindNotFound)
	}
	var page struct {
		Works []openLibraryDoc `json:"works"`
	}
	if err := o.get(ctx, "trending/weekly.json", map[string]string{"limit": "30"}, &page); err != nil {
		return nil, err
	}
	return openLibraryPage{}.hits(page.Works), nil
}

// subject is a subject's books that have a cover. Its works differ from a search's docs: `cover_id`
// and `authors[].name`. Some titles hold newlines, and some years are 0.
func (o *OpenLibrary) subject(ctx context.Context, subject string) ([]Hit, error) {
	var page struct {
		Works []struct {
			Key              string  `json:"key"`
			Title            *string `json:"title"`
			FirstPublishYear *int    `json:"first_publish_year"`
			CoverID          *int    `json:"cover_id"`
			Authors          []struct {
				Name string `json:"name"`
			} `json:"authors"`
		} `json:"works"`
	}
	if err := o.get(ctx, "subjects/"+subject+".json", map[string]string{"limit": "30"}, &page); err != nil {
		return nil, err
	}
	docs := make([]openLibraryDoc, 0, len(page.Works))
	for _, w := range page.Works {
		if w.CoverID == nil || w.Title == nil {
			continue
		}
		title := strings.Join(strings.Fields(*w.Title), " ")
		doc := openLibraryDoc{Key: w.Key, Title: &title, CoverI: w.CoverID}
		if w.FirstPublishYear != nil && *w.FirstPublishYear > 0 {
			doc.FirstPublishYear = w.FirstPublishYear
		}
		for _, a := range w.Authors {
			doc.AuthorName = append(doc.AuthorName, a.Name)
		}
		docs = append(docs, doc)
	}
	return openLibraryPage{}.hits(docs), nil
}

func (o *OpenLibrary) get(ctx context.Context, path string, query map[string]string, v any) error {
	headers := [][2]string{{"User-Agent", cmp.Or(o.UserAgent, config.DefaultProviderUserAgent)}, {"Accept", "application/json"}}
	return getJSON(ctx, o.Client, buildURL(cmp.Or(o.BaseURL, OpenLibraryBaseURL), path, query), headers, v)
}

type openLibraryPage struct {
	Docs []openLibraryDoc `json:"docs"`
}

func (openLibraryPage) hits(docs []openLibraryDoc) []Hit {
	hits := []Hit{}
	for _, d := range docs {
		if h, ok := d.hit(); ok {
			hits = append(hits, h)
		}
	}
	return hits
}

type openLibraryDoc struct {
	Key                 string   `json:"key"`
	Title               *string  `json:"title"`
	FirstPublishYear    *int     `json:"first_publish_year"`
	ISBN                []string `json:"isbn"`
	CoverI              *int     `json:"cover_i"`
	AuthorName          []string `json:"author_name"`
	NumberOfPagesMedian *int     `json:"number_of_pages_median"`
}

func (d openLibraryDoc) hit() (Hit, bool) {
	title := nilIfBlank(d.Title)
	if title == nil || !strings.HasPrefix(d.Key, "/works/") {
		return Hit{}, false
	}
	var poster *string
	if d.CoverI != nil {
		poster = strPtr("https://covers.openlibrary.org/b/id/" + strconv.Itoa(*d.CoverI) + "-L.jpg")
	}
	var byline *string
	if d.AuthorName != nil {
		byline = strPtr(strings.Join(d.AuthorName[:min(3, len(d.AuthorName))], ", "))
	}
	isbn := ""
	for _, raw := range d.ISBN {
		if n := core.NormalizeISBN(raw); n != "" {
			isbn = n
			break
		}
	}
	return Hit{
		Type: core.MediaBook, Title: *title, Year: d.FirstPublishYear, PosterURL: poster, Byline: byline,
		IDs:       core.ExternalIDs{ISBN: isbn, OpenLibrary: strings.TrimPrefix(d.Key, "/works/")},
		PageCount: positive(d.NumberOfPagesMedian),
	}, true
}
