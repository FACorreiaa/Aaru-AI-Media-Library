package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"encoding/json"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
)

// WikidataEndpoint is Wikidata's Action API. No key; CC0 data.
const WikidataEndpoint = "https://www.wikidata.org/w/api.php"

// wikidataBatch is how many items one entity read asks for: film items carry hundreds of claims,
// so a small batch keeps each answer far under the provider client's body limit.
const wikidataBatch = 10

// wikidataMaxNeighbours bounds the related items read for one title: a novel can list dozens of
// derivative works, most of them games, plays and radio dramas Aaru does not track.
const wikidataMaxNeighbours = 40

// wikidataMaxParts bounds the parts read for a series a title is based on: "A Song of Ice and
// Fire" stands for its novels, and a long-running series is not listed whole.
const wikidataMaxParts = 12

// The Wikidata properties Aaru reads (checked against Wikidata 2026-11-06).
const (
	wdFollows          = "P155"
	wdFollowedBy       = "P156"
	wdBasedOn          = "P144"
	wdDerivativeWork   = "P4969"
	wdPartOfTheSeries  = "P179"
	wdHasParts         = "P527"
	wdSeriesOrdinal    = "P1545"
	wdPublicationDate  = "P577"
	wdStartTime        = "P580"
	wdTMDBMovie        = "P4947"
	wdTMDBShow         = "P4983"
	wdIMDb             = "P345"
	wdAniListAnime     = "P8729"
	wdAniListManga     = "P8731"
	wdMALAnime         = "P4086"
	wdMALManga         = "P4087"
	wdOpenLibrary      = "P648"
	wdMusicBrainzGroup = "P436"
)

// Wikidata is the relation source across kinds (GRAPH-001): a film's book, a book's sequel, a
// show's spin-off, and story order from numbered series. It is asked only with catalog ids; no user
// data reaches it. Titles and posters for its films and shows come from Enrich (TMDB) when set.
type Wikidata struct {
	Client    *provider.Client
	UserAgent string
	// Endpoint defaults to WikidataEndpoint; tests point it at a stub server.
	Endpoint string
	// Enrich, when set, fills titles and posters for related films and shows.
	Enrich func(ctx context.Context, nodes []RelatedNode) []RelatedNode

	// memory holds items already read, in their compact form, so walking from one title to the next
	// reads each item once. order is insertion order, for eviction.
	mu     sync.Mutex
	memory map[string]wikidataCached
	order  []string
}

// wikidataMemorySize and wikidataMemoryTTL bound the items kept in memory: compact, so a few thousand
// cost little; a day old is fresh enough, the database cache holds the answers for a month.
const (
	wikidataMemorySize = 5000
	wikidataMemoryTTL  = 24 * time.Hour
)

type wikidataCached struct {
	item wikidataItem
	at   time.Time
}

// wikidataItem is one item as Aaru reads it: the title it is (when Aaru can track it) and the
// items it relates to.
type wikidataItem struct {
	node      RelatedNode
	trackable bool
	links     []wikidataLink
	// parts are what an item Aaru cannot track is made of (a book series' novels), so a title
	// based on the series is related to the books themselves.
	parts []string
}

type wikidataLink struct {
	qid      string
	relation core.Relation
}

var (
	wikidataQID     = regexp.MustCompile(`^Q[1-9][0-9]*$`)
	wikidataIDValue = regexp.MustCompile(`^[A-Za-z0-9._:-]+$`)
)

// wikidataLookups are the (property, value) pairs that find a node's item, best first.
func wikidataLookups(n RelatedNode) [][2]string {
	var out [][2]string
	add := func(property, value string) {
		if value != "" && wikidataIDValue.MatchString(value) {
			out = append(out, [2]string{property, value})
		}
	}
	switch n.Type {
	case core.MediaMovie:
		add(wdTMDBMovie, n.IDs.TMDB)
	case core.MediaShow:
		add(wdTMDBShow, n.IDs.TMDB)
	}
	if n.Type == core.MediaManga {
		add(wdAniListManga, n.IDs.AniList)
		add(wdMALManga, n.IDs.MAL)
	} else {
		add(wdAniListAnime, n.IDs.AniList)
		add(wdMALAnime, n.IDs.MAL)
	}
	add(wdOpenLibrary, n.IDs.OpenLibrary)
	add(wdIMDb, n.IDs.IMDB)
	add(wdMusicBrainzGroup, n.IDs.MusicBrainz)
	return out
}

// RelationSourceName names Wikidata in the relation cache.
func (w *Wikidata) RelationSourceName() string { return "wikidata" }

// RelationKey is the item, or the first id that can find it; "" when the node has neither.
func (w *Wikidata) RelationKey(n RelatedNode) string {
	if wikidataQID.MatchString(n.Wikidata) {
		return "wikidata:" + n.Wikidata
	}
	lookups := wikidataLookups(n)
	if len(lookups) == 0 {
		return ""
	}
	return "wikidata:" + lookups[0][0] + "=" + lookups[0][1]
}

// Relations are the item's sequels, prequels, sources and adaptations that Aaru can track, and the
// item's own places in numbered series.
func (w *Wikidata) Relations(ctx context.Context, n RelatedNode) (Relations, error) {
	empty := Relations{Edges: []RelatedEdge{}}
	qid := n.Wikidata
	if !wikidataQID.MatchString(qid) {
		found, err := w.find(ctx, wikidataLookups(n))
		if err != nil || found == "" {
			return empty, err
		}
		qid = found
	}
	items, err := w.items(ctx, []string{qid})
	if err != nil {
		return Relations{}, err
	}
	item, ok := items[qid]
	if !ok {
		return empty, nil
	}
	// What Wikidata knows about the title itself goes back too: its other ids let a TMDB show be
	// asked about at AniList, and keep it one node with the same title reached another way.
	self := RelatedNode{Wikidata: qid, Series: item.node.Series}
	if item.trackable && item.node.Type == n.Type {
		self.IDs, self.IsAnime = item.node.IDs, item.node.IsAnime
	}
	out := Relations{Self: &self, Edges: []RelatedEdge{}}
	if len(item.links) == 0 {
		return out, nil
	}
	qids := make([]string, len(item.links))
	for i, l := range item.links {
		qids[i] = l.qid
	}
	related, err := w.items(ctx, qids)
	if err != nil {
		return Relations{}, err
	}
	// A source or adaptation Aaru cannot track (a book series, a film series) stands for its parts.
	var partIDs []string
	for _, l := range item.links {
		if r, ok := related[l.qid]; ok && !r.trackable && !l.relation.MainChain() {
			partIDs = append(partIDs, r.parts...)
		}
	}
	parts := map[string]wikidataItem{}
	if len(partIDs) > 0 {
		if parts, err = w.items(ctx, partIDs); err != nil {
			return Relations{}, err
		}
	}
	var nodes []RelatedNode
	var relations []core.Relation
	seen := map[string]bool{qid: true}
	add := func(r wikidataItem, relation core.Relation) {
		if r.trackable && !seen[r.node.Wikidata] {
			seen[r.node.Wikidata] = true
			nodes = append(nodes, r.node)
			relations = append(relations, relation)
		}
	}
	for _, l := range item.links {
		r, ok := related[l.qid]
		switch {
		case !ok:
		case r.trackable:
			add(r, l.relation)
		case !l.relation.MainChain():
			for _, p := range r.parts {
				if part, ok := parts[p]; ok {
					add(part, l.relation)
				}
			}
		}
	}
	if w.Enrich != nil && len(nodes) > 0 {
		nodes = w.Enrich(ctx, nodes)
	}
	for i, node := range nodes {
		out.Edges = append(out.Edges, RelatedEdge{To: node, Relation: relations[i]})
	}
	return out, nil
}

// find is the item holding any of these ids, in one search; "" when none does.
func (w *Wikidata) find(ctx context.Context, lookups [][2]string) (string, error) {
	if len(lookups) == 0 {
		return "", nil
	}
	terms := make([]string, len(lookups))
	for i, l := range lookups {
		terms[i] = l[0] + "=" + l[1]
	}
	var body struct {
		wikidataFailure
		Query struct {
			Search []struct {
				Title string `json:"title"`
			} `json:"search"`
		} `json:"query"`
	}
	err := w.get(ctx, map[string]string{
		"action": "query", "list": "search", "srsearch": "haswbstatement:" + strings.Join(terms, "|"),
		"srlimit": "1", "srnamespace": "0",
	}, &body)
	if err = cmp.Or(err, body.failed()); err != nil {
		return "", err
	}
	for _, s := range body.Query.Search {
		if wikidataQID.MatchString(s.Title) {
			return s.Title, nil
		}
	}
	return "", nil
}

// items are the items as Aaru reads them, from memory when an earlier lookup already read them,
// else a few at a time from Wikidata. An item Wikidata does not have is missing from the map.
func (w *Wikidata) items(ctx context.Context, qids []string) (map[string]wikidataItem, error) {
	out := map[string]wikidataItem{}
	var missing []string
	w.mu.Lock()
	now := time.Now()
	for _, q := range qids {
		if c, ok := w.memory[q]; ok && now.Sub(c.at) < wikidataMemoryTTL {
			out[q] = c.item
		} else if !slices.Contains(missing, q) {
			missing = append(missing, q)
		}
	}
	w.mu.Unlock()
	for start := 0; start < len(missing); start += wikidataBatch {
		batch := missing[start:min(start+wikidataBatch, len(missing))]
		var body struct {
			wikidataFailure
			Entities map[string]wikidataEntity `json:"entities"`
		}
		err := w.get(ctx, map[string]string{
			"action": "wbgetentities", "ids": strings.Join(batch, "|"), "props": "labels|claims",
			"languages": "en|mul",
		}, &body)
		if err = cmp.Or(err, body.failed()); err != nil {
			return nil, err
		}
		w.mu.Lock()
		if w.memory == nil {
			w.memory = map[string]wikidataCached{}
		}
		for id, e := range body.Entities {
			if e.Missing != nil {
				continue
			}
			item := e.item(id)
			out[id] = item
			w.memory[id] = wikidataCached{item: item, at: now}
			w.order = append(w.order, id)
		}
		for len(w.order) > wikidataMemorySize {
			delete(w.memory, w.order[0])
			w.order = w.order[1:]
		}
		w.mu.Unlock()
	}
	return out, nil
}

func (w *Wikidata) get(ctx context.Context, query map[string]string, v any) error {
	values := url.Values{"format": {"json"}}
	for k, value := range query {
		values.Set(k, value)
	}
	userAgent := cmp.Or(w.UserAgent, config.DefaultProviderUserAgent)
	return getJSON(ctx, w.Client, cmp.Or(w.Endpoint, WikidataEndpoint)+"?"+values.Encode(),
		[][2]string{{"Accept", "application/json"}, {"User-Agent", userAgent}}, v)
}

// MARK: - Wikidata wire shapes

// wikidataFailure is the Action API's way of failing: HTTP 200 with an `error` object. Read as a
// failure, never as "nothing found", so it is not cached as an empty answer.
type wikidataFailure struct {
	Error *struct {
		Code string `json:"code"`
	} `json:"error"`
}

func (f wikidataFailure) failed() error {
	if f.Error == nil {
		return nil
	}
	return provider.NewError("wikidata", provider.KindUnavailable)
}

type wikidataEntity struct {
	Missing *string `json:"missing"`
	Labels  map[string]struct {
		Value string `json:"value"`
	} `json:"labels"`
	Claims map[string][]wikidataClaim `json:"claims"`
}

type wikidataClaim struct {
	Rank       string                    `json:"rank"`
	Mainsnak   wikidataSnak              `json:"mainsnak"`
	Qualifiers map[string][]wikidataSnak `json:"qualifiers"`
}

type wikidataSnak struct {
	DataValue *struct {
		Value json.RawMessage `json:"value"`
	} `json:"datavalue"`
}

// claims are the property's statements, deprecated ones left out.
func (e wikidataEntity) claims(property string) []wikidataClaim {
	var out []wikidataClaim
	for _, c := range e.Claims[property] {
		if c.Rank != "deprecated" {
			out = append(out, c)
		}
	}
	return out
}

func (s wikidataSnak) item() string {
	if s.DataValue == nil {
		return ""
	}
	var v struct {
		ID string `json:"id"`
	}
	if json.Unmarshal(s.DataValue.Value, &v) != nil || !wikidataQID.MatchString(v.ID) {
		return ""
	}
	return v.ID
}

func (s wikidataSnak) text() string {
	if s.DataValue == nil {
		return ""
	}
	var v string
	if json.Unmarshal(s.DataValue.Value, &v) != nil {
		return ""
	}
	return strings.TrimSpace(v)
}

// time is a date snak as `YYYY-MM-DD` (day precision) or a bare year.
func (s wikidataSnak) time() (date *string, year *int) {
	if s.DataValue == nil {
		return nil, nil
	}
	var v struct {
		Time      string `json:"time"`
		Precision int    `json:"precision"`
	}
	if json.Unmarshal(s.DataValue.Value, &v) != nil || len(v.Time) < 11 || v.Time[0] != '+' || v.Precision < 9 {
		return nil, nil
	}
	y, err := strconv.Atoi(v.Time[1:5])
	if err != nil || y <= 0 {
		return nil, nil
	}
	if v.Precision >= 11 {
		d := v.Time[1:11]
		return &d, &y
	}
	return nil, &y
}

func (e wikidataEntity) items(property string) []string {
	var out []string
	for _, c := range e.claims(property) {
		if q := c.Mainsnak.item(); q != "" {
			out = append(out, q)
		}
	}
	return out
}

func (e wikidataEntity) qualifierItems(property, qualifier string) []string {
	var out []string
	for _, c := range e.claims(property) {
		for _, s := range c.Qualifiers[qualifier] {
			if q := s.item(); q != "" {
				out = append(out, q)
			}
		}
	}
	return out
}

func (e wikidataEntity) text(property string) string {
	for _, c := range e.claims(property) {
		if v := c.Mainsnak.text(); v != "" {
			return v
		}
	}
	return ""
}

// series are the item's numbered places in series: the story order.
func (e wikidataEntity) series() []SeriesPlace {
	var out []SeriesPlace
	for _, c := range e.claims(wdPartOfTheSeries) {
		series := c.Mainsnak.item()
		if series == "" {
			continue
		}
		for _, s := range c.Qualifiers[wdSeriesOrdinal] {
			n, err := strconv.ParseFloat(s.text(), 64)
			if err == nil && !slices.ContainsFunc(out, func(p SeriesPlace) bool { return p.Series == series }) {
				out = append(out, SeriesPlace{Series: series, Ordinal: n})
			}
		}
	}
	return out
}

// openLibraryWork is the item's Open Library work id: a work, never an edition.
func (e wikidataEntity) openLibraryWork() string {
	for _, c := range e.claims(wdOpenLibrary) {
		if v := c.Mainsnak.text(); strings.HasSuffix(v, "W") {
			return v
		}
	}
	return ""
}

// node is the item as a title Aaru can track, its kind read from the catalog ids it carries; false
// for anything else (a game, a play, a single comic issue).
func (e wikidataEntity) node(qid string) (RelatedNode, bool) {
	ids := core.ExternalIDs{IMDB: e.text(wdIMDb), MusicBrainz: e.text(wdMusicBrainzGroup)}
	var mediaType core.MediaType
	anime := false
	switch {
	case e.text(wdTMDBMovie) != "":
		mediaType, ids.TMDB = core.MediaMovie, e.text(wdTMDBMovie)
		ids.AniList, ids.MAL = e.text(wdAniListAnime), e.text(wdMALAnime)
		anime = ids.AniList != "" || ids.MAL != ""
	case e.text(wdTMDBShow) != "":
		mediaType, ids.TMDB = core.MediaShow, e.text(wdTMDBShow)
		ids.AniList, ids.MAL = e.text(wdAniListAnime), e.text(wdMALAnime)
		anime = ids.AniList != "" || ids.MAL != ""
	case e.text(wdAniListAnime) != "" || e.text(wdMALAnime) != "":
		mediaType, anime = core.MediaShow, true
		ids.AniList, ids.MAL = e.text(wdAniListAnime), e.text(wdMALAnime)
	case e.text(wdAniListManga) != "" || e.text(wdMALManga) != "":
		mediaType = core.MediaManga
		ids.AniList, ids.MAL = e.text(wdAniListManga), e.text(wdMALManga)
	case e.openLibraryWork() != "":
		// A novel with an audiobook carries a MusicBrainz id too; it is still the book.
		mediaType, ids.OpenLibrary, ids.MusicBrainz = core.MediaBook, e.openLibraryWork(), ""
	case ids.MusicBrainz != "":
		mediaType = core.MediaAlbum
	default:
		return RelatedNode{}, false
	}
	var date *string
	var year *int
	dates := e.claims(wdPublicationDate)
	if len(dates) == 0 {
		dates = e.claims(wdStartTime) // a series is dated by when it started
	}
	for _, c := range dates {
		d, y := c.Mainsnak.time()
		if y != nil && (year == nil || *y < *year || (*y == *year && d != nil && (date == nil || *d < *date))) {
			date, year = d, y
		}
	}
	title := ""
	for _, lang := range []string{"en", "mul"} {
		if l, ok := e.Labels[lang]; ok && strings.TrimSpace(l.Value) != "" {
			title = strings.TrimSpace(l.Value)
			break
		}
	}
	return RelatedNode{
		Type: mediaType, IsAnime: anime, IDs: ids, Wikidata: qid, Title: title, Year: year, ReleaseDate: date,
		Series: e.series(),
	}, true
}

// item is the entity in its compact form: the title, and its links in the order they matter
// (prequels, sequels, sources, then adaptations), at most wikidataMaxNeighbours.
func (e wikidataEntity) item(qid string) wikidataItem {
	node, trackable := e.node(qid)
	if !trackable {
		node = RelatedNode{Wikidata: qid, Series: e.series()}
	}
	out := wikidataItem{node: node, trackable: trackable}
	if !trackable {
		parts := e.items(wdHasParts)
		out.parts = parts[:min(len(parts), wikidataMaxParts)]
	}
	seen := map[string]bool{qid: true}
	add := func(qids []string, relation core.Relation) {
		for _, q := range qids {
			if !seen[q] && len(out.links) < wikidataMaxNeighbours {
				seen[q] = true
				out.links = append(out.links, wikidataLink{q, relation})
			}
		}
	}
	add(e.items(wdFollows), core.RelationPrequel)
	add(e.items(wdFollowedBy), core.RelationSequel)
	add(e.qualifierItems(wdPartOfTheSeries, wdFollows), core.RelationPrequel)
	add(e.qualifierItems(wdPartOfTheSeries, wdFollowedBy), core.RelationSequel)
	add(e.items(wdBasedOn), core.RelationSource)
	add(e.items(wdDerivativeWork), core.RelationAdaptation)
	return out
}
