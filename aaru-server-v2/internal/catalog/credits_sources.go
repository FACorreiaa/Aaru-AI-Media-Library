package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"
)

// MARK: - TMDB (GRAPH-005, GRAPH-006): a film's director, a show's creator, and the first two billed

// tmdbCredit is one entry of a person's credits: the film or show, their job on it (crew) or
// their part in it (cast), and TMDB's vote count.
type tmdbCredit struct {
	tmdbDetail
	Job       string `json:"job"`
	VoteCount int    `json:"vote_count"`
	// Video is true for a direct-to-video extra (a making-of, a concert film).
	Video bool `json:"video"`
	// Order is the person's billing in a film's cast, from 0; absent on crew and on shows.
	Order     *int   `json:"order"`
	Character string `json:"character"`
	// EpisodeCount is how many episodes of a show they were in; 0 when TMDB does not say.
	EpisodeCount int `json:"episode_count"`
}

// tmdbBilled is one entry of a title's cast, with its billing.
type tmdbBilled struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Order int    `json:"order"`
}

// An actor's branch leaves out cameos and appearances as themselves: a film counts when they are
// billed in its first tmdbCastMaxOrder+1, a show when they were in tmdbCastMinEpisodes episodes
// and it is not a talk or news show.
const (
	tmdbCastMaxOrder    = 4
	tmdbCastMinEpisodes = 3
	tmdbGenreNews       = 10763
	tmdbGenreTalk       = 10767
)

// tmdbCastKinds are the cast a tree branches on, in billing order.
var tmdbCastKinds = []core.TreeBranchKind{core.BranchLeadActor, core.BranchSecondActor}

// tmdbSelfWords are the characters of someone appearing as themselves.
var tmdbSelfWords = map[string]bool{"self": true, "himself": true, "herself": true, "themselves": true, "themself": true}

// CreditSourceName names TMDB in the credit cache.
func (t *TMDB) CreditSourceName() string { return "tmdb" }

// CreditKey is a film's or show's TMDB id.
func (t *TMDB) CreditKey(n RelatedNode) string {
	if n.IDs.TMDB == "" {
		return ""
	}
	switch n.Type {
	case core.MediaMovie:
		return "movie:" + n.IDs.TMDB
	case core.MediaShow:
		return "tv:" + n.IDs.TMDB
	}
	return ""
}

// People is a film's first credited director or a show's first creator, then the title's first
// two billed actors. A show's billing is over all its seasons (`aggregate_credits`), read in the
// same request as its creator.
func (t *TMDB) People(ctx context.Context, n RelatedNode) ([]Credit, error) {
	people := []Credit{}
	if n.Type == core.MediaMovie {
		var body struct {
			Crew []struct {
				ID   int    `json:"id"`
				Name string `json:"name"`
				Job  string `json:"job"`
			} `json:"crew"`
			Cast []tmdbBilled `json:"cast"`
		}
		err := t.get(ctx, "movie/"+n.IDs.TMDB+"/credits", nil, &body)
		if provider.IsNotFound(err) {
			return people, nil
		}
		if err != nil {
			return nil, err
		}
		for _, c := range body.Crew {
			if c.Job == "Director" && c.Name != "" {
				people = append(people, Credit{Kind: core.BranchDirector, ID: strconv.Itoa(c.ID), Name: c.Name})
				break
			}
		}
		return append(people, tmdbCast(body.Cast, core.MediaMovie)...), nil
	}
	var body struct {
		CreatedBy []struct {
			ID   int    `json:"id"`
			Name string `json:"name"`
		} `json:"created_by"`
		AggregateCredits struct {
			Cast []tmdbBilled `json:"cast"`
		} `json:"aggregate_credits"`
	}
	err := t.get(ctx, "tv/"+n.IDs.TMDB, map[string]string{"append_to_response": "aggregate_credits"}, &body)
	if provider.IsNotFound(err) {
		return people, nil
	}
	if err != nil {
		return nil, err
	}
	for _, c := range body.CreatedBy {
		if c.Name != "" {
			people = append(people, Credit{Kind: core.BranchCreator, ID: strconv.Itoa(c.ID), Name: c.Name})
			break
		}
	}
	return append(people, tmdbCast(body.AggregateCredits.Cast, core.MediaShow)...), nil
}

// tmdbCast is the first two billed of a cast, as the lead and the second actor.
func tmdbCast(cast []tmdbBilled, media core.MediaType) []Credit {
	billed := slices.Clone(cast)
	slices.SortStableFunc(billed, func(a, b tmdbBilled) int { return cmp.Compare(a.Order, b.Order) })
	var out []Credit
	seen := map[int]bool{}
	for _, c := range billed {
		if len(out) == len(tmdbCastKinds) {
			break
		}
		if c.Name == "" || seen[c.ID] {
			continue
		}
		seen[c.ID] = true
		out = append(out, Credit{Kind: tmdbCastKinds[len(out)], ID: strconv.Itoa(c.ID), Name: c.Name, Media: media})
	}
	return out
}

// Works are the films a director directed, the shows a creator created, or the films or shows an
// actor had a part in. Adult titles and direct-to-video extras are left out.
func (t *TMDB) Works(ctx context.Context, credit Credit) ([]CreditedWork, error) {
	path, job, mediaType := "person/"+credit.ID+"/movie_credits", "Director", core.MediaMovie
	if credit.Kind == core.BranchCreator || credit.Media == core.MediaShow {
		path, job, mediaType = "person/"+credit.ID+"/tv_credits", "Creator", core.MediaShow
	}
	var body struct {
		Crew []tmdbCredit `json:"crew"`
		Cast []tmdbCredit `json:"cast"`
	}
	err := t.get(ctx, path, nil, &body)
	if provider.IsNotFound(err) {
		return []CreditedWork{}, nil
	}
	if err != nil {
		return nil, err
	}
	entries, keep := body.Crew, func(c tmdbCredit) bool { return c.Job == job }
	if credit.Kind.IsCast() {
		entries, keep = body.Cast, func(c tmdbCredit) bool { return c.billedPart(mediaType) }
	}
	works := []CreditedWork{}
	seen := map[int]bool{}
	for _, c := range entries {
		if !keep(c) || c.Video || seen[c.ID] || (c.Adult != nil && *c.Adult) {
			continue
		}
		hit, ok := c.hit(mediaType)
		if !ok {
			continue
		}
		seen[c.ID] = true
		works = append(works, CreditedWork{Score: c.VoteCount, RelatedNode: RelatedNode{
			Type: mediaType, IsAnime: hit.IsAnime, IDs: hit.IDs, Title: hit.Title, Year: hit.Year,
			ReleaseDate: hit.ReleaseDate, PosterURL: hit.PosterURL,
		}})
	}
	return works, nil
}

// billedPart is true when a cast credit is a part worth a place in the actor's branch: not a
// cameo, not a guest spot, not an appearance as themselves.
func (c tmdbCredit) billedPart(mediaType core.MediaType) bool {
	words := strings.FieldsFunc(strings.ToLower(c.Character), func(r rune) bool { return !unicode.IsLetter(r) })
	if slices.ContainsFunc(words, func(w string) bool { return tmdbSelfWords[w] }) {
		return false
	}
	if mediaType == core.MediaMovie {
		return c.Order == nil || *c.Order <= tmdbCastMaxOrder
	}
	if slices.Contains(c.GenreIDs, tmdbGenreTalk) || slices.Contains(c.GenreIDs, tmdbGenreNews) {
		return false
	}
	return c.EpisodeCount == 0 || c.EpisodeCount >= tmdbCastMinEpisodes
}

// MARK: - AniList (GRAPH-005): an anime's main studio, a manga's author

// aniListCreditPage is how many of a studio's or author's works are read: their most popular.
// AniList cannot list a studio's works from a date on, so a studio with more than this many is
// known by its best-known titles only.
const aniListCreditPage = 50

// aniListStudioFormats are the anime a studio's branch holds: series and films, not OVAs,
// specials, shorts or music videos.
var aniListStudioFormats = map[string]bool{"TV": true, "MOVIE": true, "ONA": true}

// storyRole is a manga credit that wrote it: "Story", "Story & Art", "Original Story".
var storyRole = regexp.MustCompile(`(?i)(story)`)

// aniListCreditedMedia is an entry with AniList's popularity: how many members list it.
type aniListCreditedMedia struct {
	aniListMedia
	Popularity int  `json:"popularity"`
	IsAdult    bool `json:"isAdult"`
}

func (m aniListCreditedMedia) work() CreditedWork {
	return CreditedWork{RelatedNode: m.relatedNode(), Score: m.Popularity}
}

// CreditSourceName names AniList in the credit cache.
func (a *AniList) CreditSourceName() string { return "anilist" }

// CreditKey is the AniList id; AniList knows nothing without one.
func (a *AniList) CreditKey(n RelatedNode) string {
	if n.IDs.AniList == "" {
		return ""
	}
	return "media:" + n.IDs.AniList
}

// People is a manga's author (who wrote it, else who drew it) or an anime's main studio.
func (a *AniList) People(ctx context.Context, n RelatedNode) ([]Credit, error) {
	id, err := strconv.Atoi(n.IDs.AniList)
	if err != nil {
		return []Credit{}, nil //nolint:nilerr // not an AniList id: nothing to ask
	}
	var body struct {
		Media *struct {
			Type    *string `json:"type"`
			Studios *struct {
				Nodes []struct {
					ID   int    `json:"id"`
					Name string `json:"name"`
				} `json:"nodes"`
			} `json:"studios"`
			Staff *struct {
				Edges []struct {
					Role *string `json:"role"`
					Node struct {
						ID   int `json:"id"`
						Name struct {
							Full *string `json:"full"`
						} `json:"name"`
					} `json:"node"`
				} `json:"edges"`
			} `json:"staff"`
		} `json:"Media"`
	}
	err = a.post(ctx, `query ($id: Int) {
  Media(id: $id) { type studios(isMain: true) { nodes { id name } }
    staff(perPage: 10, sort: [RELEVANCE, ROLE]) { edges { role node { id name { full } } } } }
}`, map[string]any{"id": id}, &body)
	if provider.IsNotFound(err) || (err == nil && body.Media == nil) {
		return []Credit{}, nil
	}
	if err != nil {
		return nil, err
	}
	if sval(body.Media.Type) != "MANGA" {
		if body.Media.Studios != nil {
			for _, s := range body.Media.Studios.Nodes {
				if s.Name != "" {
					return []Credit{{Kind: core.BranchStudio, ID: strconv.Itoa(s.ID), Name: s.Name}}, nil
				}
			}
		}
		return []Credit{}, nil
	}
	if body.Media.Staff == nil {
		return []Credit{}, nil
	}
	for _, role := range []*regexp.Regexp{storyRole, storyOrArt} {
		for _, e := range body.Media.Staff.Edges {
			name := nilIfBlank(e.Node.Name.Full)
			if e.Role == nil || name == nil || !core.MatchWordBounded(role, *e.Role) {
				continue
			}
			return []Credit{{Kind: core.BranchAuthor, ID: strconv.Itoa(e.Node.ID), Name: *name}}, nil
		}
	}
	return []Credit{}, nil
}

// Works are a studio's own series and films, or the manga an author wrote or drew: the most
// popular aniListCreditPage of them. Adult works are left out.
func (a *AniList) Works(ctx context.Context, credit Credit) ([]CreditedWork, error) {
	id, err := strconv.Atoi(credit.ID)
	if err != nil {
		return []CreditedWork{}, nil //nolint:nilerr // not an AniList id: nothing to ask
	}
	fields := aniListRelationFields + " popularity isAdult"
	works := []CreditedWork{}
	seen := map[int]bool{}
	if credit.Kind == core.BranchStudio {
		var body struct {
			Studio *struct {
				Media *struct {
					Nodes []aniListCreditedMedia `json:"nodes"`
				} `json:"media"`
			} `json:"Studio"`
		}
		err = a.post(ctx, fmt.Sprintf(`query ($id: Int) {
  Studio(id: $id) { media(isMain: true, sort: [POPULARITY_DESC], perPage: %d) { nodes { %s } } }
}`, aniListCreditPage, fields), map[string]any{"id": id}, &body)
		if provider.IsNotFound(err) || (err == nil && (body.Studio == nil || body.Studio.Media == nil)) {
			return works, nil
		}
		if err != nil {
			return nil, err
		}
		for _, m := range body.Studio.Media.Nodes {
			if m.IsAdult || seen[m.ID] || !aniListStudioFormats[sval(m.Format)] {
				continue
			}
			seen[m.ID] = true
			works = append(works, m.work())
		}
		return works, nil
	}
	var body struct {
		Staff *struct {
			StaffMedia *struct {
				Edges []struct {
					StaffRole *string              `json:"staffRole"`
					Node      aniListCreditedMedia `json:"node"`
				} `json:"edges"`
			} `json:"staffMedia"`
		} `json:"Staff"`
	}
	err = a.post(ctx, fmt.Sprintf(`query ($id: Int) {
  Staff(id: $id) { staffMedia(type: MANGA, sort: [POPULARITY_DESC], perPage: %d) { edges { staffRole node { %s } } } }
}`, aniListCreditPage, fields), map[string]any{"id": id}, &body)
	if provider.IsNotFound(err) || (err == nil && (body.Staff == nil || body.Staff.StaffMedia == nil)) {
		return works, nil
	}
	if err != nil {
		return nil, err
	}
	for _, e := range body.Staff.StaffMedia.Edges {
		// Their own manga only: not the ones they assisted on, translated or supervised.
		if e.StaffRole == nil || !core.MatchWordBounded(storyOrArt, *e.StaffRole) {
			continue
		}
		if e.Node.IsAdult || seen[e.Node.ID] {
			continue
		}
		seen[e.Node.ID] = true
		works = append(works, e.Node.work())
	}
	return works, nil
}

// MARK: - Open Library (GRAPH-005): a book's author

// openLibraryAuthorPage is how many of an author's books are read: the ones most readers logged.
const openLibraryAuthorPage = "50"

// CreditSourceName names Open Library in the credit cache.
func (o *OpenLibrary) CreditSourceName() string { return "openlibrary" }

// CreditKey is a book's Open Library work id.
func (o *OpenLibrary) CreditKey(n RelatedNode) string {
	if n.Type != core.MediaBook || n.IDs.OpenLibrary == "" {
		return ""
	}
	return "work:" + n.IDs.OpenLibrary
}

// People is the book's first author, by Open Library's author key.
func (o *OpenLibrary) People(ctx context.Context, n RelatedNode) ([]Credit, error) {
	var page struct {
		Docs []struct {
			AuthorKey  []string `json:"author_key"`
			AuthorName []string `json:"author_name"`
		} `json:"docs"`
	}
	query := map[string]string{"q": "key:/works/" + n.IDs.OpenLibrary, "fields": "key,author_key,author_name", "limit": "1"}
	if err := o.get(ctx, "search.json", query, &page); err != nil {
		return nil, err
	}
	if len(page.Docs) == 0 || len(page.Docs[0].AuthorKey) == 0 || len(page.Docs[0].AuthorName) == 0 {
		return []Credit{}, nil
	}
	doc := page.Docs[0]
	if doc.AuthorKey[0] == "" || strings.TrimSpace(doc.AuthorName[0]) == "" {
		return []Credit{}, nil
	}
	return []Credit{{Kind: core.BranchAuthor, ID: doc.AuthorKey[0], Name: doc.AuthorName[0]}}, nil
}

// Works are the author's books that have a cover, the ones most readers logged first. Open
// Library dates a book by its year only.
func (o *OpenLibrary) Works(ctx context.Context, credit Credit) ([]CreditedWork, error) {
	var page struct {
		Docs []struct {
			openLibraryDoc
			ReadingLogCount int `json:"readinglog_count"`
		} `json:"docs"`
	}
	query := map[string]string{
		"q":      "author_key:" + credit.ID,
		"fields": "key,title,subtitle,first_publish_year,cover_i,author_name,readinglog_count",
		"sort":   "readinglog", "limit": openLibraryAuthorPage,
	}
	if err := o.get(ctx, "search.json", query, &page); err != nil {
		return nil, err
	}
	works := []CreditedWork{}
	for _, d := range page.Docs {
		hit, ok := d.hit()
		if !ok || d.CoverI == nil {
			continue
		}
		works = append(works, CreditedWork{Score: d.ReadingLogCount, RelatedNode: RelatedNode{
			Type: core.MediaBook, IDs: hit.IDs, Title: hit.Title, Year: hit.Year, PosterURL: hit.PosterURL,
		}})
	}
	return works, nil
}

// MARK: - MusicBrainz (GRAPH-005): an album's artist

// musicBrainzVariousArtists is MusicBrainz's stand-in artist for compilations: not a person.
const musicBrainzVariousArtists = "89ad4ac3-39f7-470e-963a-56509c546377"

// CreditSourceName names MusicBrainz in the credit cache.
func (m *MusicBrainz) CreditSourceName() string { return "musicbrainz" }

// CreditKey is an album's release-group id.
func (m *MusicBrainz) CreditKey(n RelatedNode) string {
	if n.Type != core.MediaAlbum || n.IDs.MusicBrainz == "" {
		return ""
	}
	return "release-group:" + n.IDs.MusicBrainz
}

// People is the album's first credited artist.
func (m *MusicBrainz) People(ctx context.Context, n RelatedNode) ([]Credit, error) {
	artists, err := m.Artists(ctx, n.IDs.MusicBrainz)
	if err != nil {
		return nil, err
	}
	for _, a := range artists {
		if a.MusicBrainzID != musicBrainzVariousArtists && a.Name != "" {
			return []Credit{{Kind: core.BranchArtist, ID: a.MusicBrainzID, Name: a.Name}}, nil
		}
	}
	return []Credit{}, nil
}

// Works are the artist's official studio albums and EPs: no live albums, compilations or
// bootlegs. MusicBrainz has no count of how well known an album is, so Score stays 0.
func (m *MusicBrainz) Works(ctx context.Context, credit Credit) ([]CreditedWork, error) {
	lucene := "arid:" + LuceneEscaped(credit.ID) +
		" AND (primarytype:album OR primarytype:ep) AND NOT secondarytype:* AND status:official"
	var page struct {
		ReleaseGroups []mbReleaseGroup `json:"release-groups"`
	}
	if err := m.get(ctx, "release-group", map[string]string{"query": lucene, "limit": "100"}, &page); err != nil {
		return nil, err
	}
	works := []CreditedWork{}
	for _, g := range page.ReleaseGroups {
		if !g.isTracked() {
			continue
		}
		hit := g.hit()
		works = append(works, CreditedWork{RelatedNode: RelatedNode{
			Type: core.MediaAlbum, IDs: hit.IDs, Title: hit.Title, Year: hit.Year,
			ReleaseDate: hit.ReleaseDate, PosterURL: hit.PosterURL,
		}})
	}
	return works, nil
}
