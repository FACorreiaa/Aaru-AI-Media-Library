package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/safe"
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

// RelationsTTL is how long one source's cached answer is fresh: sequels and adaptations change
// rarely, and a graph that is a month behind still reads right.
const RelationsTTL = 30 * 24 * time.Hour

// RelationGraphDeadline bounds building one graph for a page; whatever arrived by then is drawn,
// marked partial, and the walk goes on in the background for up to RelationWarmDeadline so the next
// read finds every answer cached.
const (
	RelationGraphDeadline = 8 * time.Second
	RelationWarmDeadline  = time.Minute
)

// cachedRelationSource keeps a source's answers in `catalog_relations`. A failed fetch serves the
// old answer when there is one.
type cachedRelationSource struct {
	inner RelationSource
	q     *sqlc.Queries
	now   func() time.Time
	log   *slog.Logger
}

func (c cachedRelationSource) RelationSourceName() string { return c.inner.RelationSourceName() }

func (c cachedRelationSource) RelationKey(n RelatedNode) string { return c.inner.RelationKey(n) }

func (c cachedRelationSource) Relations(ctx context.Context, n RelatedNode) (Relations, error) {
	source, key := c.inner.RelationSourceName(), c.inner.RelationKey(n)
	var stale *Relations
	row, err := c.q.CatalogRelations(ctx, sqlc.CatalogRelationsParams{Source: source, NodeKey: key})
	switch {
	case err == nil:
		var cached Relations
		if json.Unmarshal(row.Relations, &cached) == nil {
			if c.now().Sub(row.FetchedAt.Time) < RelationsTTL {
				return cached, nil
			}
			stale = &cached
		}
	case !db.IsNoRows(err):
		c.log.Warn("Relation cache read failed", "source", source, "key", key, "error", err.Error())
	}
	fresh, err := c.inner.Relations(ctx, n)
	if err != nil {
		if stale != nil {
			return *stale, nil
		}
		return Relations{}, fmt.Errorf("%s relations: %w", source, err)
	}
	if fresh.Edges == nil {
		fresh.Edges = []RelatedEdge{}
	}
	payload, err := json.Marshal(fresh)
	if err != nil {
		return fresh, nil
	}
	// Written past the caller: a closed page must not throw away an answer already paid for.
	err = c.q.PutCatalogRelations(context.WithoutCancel(ctx), sqlc.PutCatalogRelationsParams{
		Source: source, NodeKey: key, Relations: payload,
		FetchedAt: pgtype.Timestamptz{Time: c.now(), Valid: true},
	})
	if err != nil {
		c.log.Warn("Relation cache write failed", "source", source, "key", key, "error", err.Error())
	}
	return fresh, nil
}

// RelationService builds a title's relation graph (GRAPH-001) and marks it with the user's library.
type RelationService struct {
	Store   *Store
	Sources []RelationSource
	log     *slog.Logger
	// OnboardingDeadline bounds one onboarding related call's graphs (OnboardingRelatedDeadline
	// when zero); tests shorten it.
	OnboardingDeadline time.Duration
	// warming holds the centres being walked in the background, so one title warms once.
	warming sync.Map
}

// NewRelationService wraps each source in the shared cache. Sources may be empty: the graph is
// then the title alone.
func NewRelationService(store *Store, sources []RelationSource, log *slog.Logger) *RelationService {
	if log == nil {
		log = slog.Default()
	}
	cached := make([]RelationSource, 0, len(sources))
	for _, s := range sources {
		cached = append(cached, cachedRelationSource{inner: s, q: store.q, now: time.Now, log: log})
	}
	return &RelationService{Store: store, Sources: cached, log: log}
}

// Graph is the title's relations in the given order.
func (s *RelationService) Graph(ctx context.Context, titleID uuid.UUID, order RelationOrder) (RelationGraph, error) {
	return s.graphBy(ctx, titleID, order, time.Now().Add(RelationGraphDeadline))
}

// graphBy is Graph drawn with whatever arrived by deadline; a graph cut short keeps warming past
// it, as long as ctx itself is alive.
func (s *RelationService) graphBy(ctx context.Context, titleID uuid.UUID, order RelationOrder, deadline time.Time) (RelationGraph, error) {
	title, err := s.Store.Title(ctx, titleID)
	if err != nil {
		return RelationGraph{}, err
	}
	if title == nil {
		return RelationGraph{}, apperr.NotFound()
	}
	centre := RelatedNode{
		Type: title.Type, IsAnime: title.IsAnime, IDs: title.IDs, Title: title.Title, Year: title.Year,
		PosterURL: title.PosterURL,
	}
	// An anime kept as one TMDB show starts from its first AniList season, so AniList's chain of
	// seasons, films and OVAs hangs from it.
	if title.IsAnime && title.Type == core.MediaShow && centre.IDs.AniList == "" && centre.IDs.TMDB != "" {
		mappings, err := s.Store.MappingsByTMDB(ctx, []string{centre.IDs.TMDB})
		if err != nil {
			return RelationGraph{}, err
		}
		slices.SortFunc(mappings, func(a, b AnimeMapping) int {
			return cmp.Compare(seasonOrLast(a.TMDBSeason), seasonOrLast(b.TMDBSeason))
		})
		if len(mappings) > 0 {
			centre.IDs.AniList = mappings[0].AniList
		}
	}
	pageCtx, cancel := context.WithDeadline(ctx, deadline)
	defer cancel()
	graph := BuildRelationGraph(pageCtx, centre, s.Sources, order)
	if graph.Partial && errors.Is(pageCtx.Err(), context.DeadlineExceeded) && ctx.Err() == nil {
		s.warm(ctx, centre, order)
	}
	return graph, nil
}

// warm walks the graph again past the page, detached from it, so its answers land in the cache.
func (s *RelationService) warm(ctx context.Context, centre RelatedNode, order RelationOrder) {
	keys := NodeKeys(centre)
	if len(keys) == 0 {
		return
	}
	if _, busy := s.warming.LoadOrStore(keys[0], true); busy {
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), RelationWarmDeadline)
	go func() {
		defer cancel()
		defer s.warming.Delete(keys[0])
		defer func() { _ = recovered(s.log, "relation warm", recover()) }()
		BuildRelationGraph(ctx, centre, s.Sources, order)
	}()
}

func seasonOrLast(season *int) int {
	if season == nil || *season < 1 {
		return 1 << 20
	}
	return *season
}

// RelationMark is the user's item for a graph node.
type RelationMark struct {
	LibraryItemID uuid.UUID
	Status        core.LibraryStatus
}

// Marks are the user's items among the graph's nodes, by node key. An anime season AniList lists
// on its own is marked with the TMDB show Aaru keeps it in.
func (s *RelationService) Marks(ctx context.Context, userID uuid.UUID, graph RelationGraph) (map[string]RelationMark, error) {
	marks := map[string]RelationMark{}
	var anilist []string
	for _, n := range graph.Nodes {
		if n.IDs.AniList != "" {
			anilist = append(anilist, n.IDs.AniList)
		}
	}
	mappings, err := s.Store.MappingsByAniList(ctx, anilist)
	if err != nil {
		return nil, err
	}
	showOf := map[string]string{}
	for _, m := range mappings {
		if m.TMDB != nil {
			showOf[m.AniList] = *m.TMDB
		}
	}
	params := sqlc.LibraryEntriesMatchingCatalogParams{
		UserID: userID, Tmdb: []string{}, Anilist: []string{}, OpenLibrary: []string{}, Musicbrainz: []string{},
	}
	for _, n := range graph.Nodes {
		if n.IDs.TMDB != "" {
			params.Tmdb = append(params.Tmdb, n.IDs.TMDB)
		}
		if show := showOf[n.IDs.AniList]; show != "" {
			params.Tmdb = append(params.Tmdb, show)
		}
		if n.IDs.AniList != "" {
			params.Anilist = append(params.Anilist, n.IDs.AniList)
		}
		if n.IDs.OpenLibrary != "" {
			params.OpenLibrary = append(params.OpenLibrary, n.IDs.OpenLibrary)
		}
		if n.IDs.MusicBrainz != "" {
			params.Musicbrainz = append(params.Musicbrainz, n.IDs.MusicBrainz)
		}
	}
	if len(params.Tmdb)+len(params.Anilist)+len(params.OpenLibrary)+len(params.Musicbrainz) == 0 {
		return marks, nil
	}
	rows, err := s.Store.q.LibraryEntriesMatchingCatalog(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("library entries matching catalog: %w", err)
	}
	for _, n := range graph.Nodes {
		for _, r := range rows {
			if relationRowMatches(n, r, showOf[n.IDs.AniList]) {
				marks[n.Key] = RelationMark{LibraryItemID: r.ID, Status: core.LibraryStatus(r.Status)}
				break
			}
		}
	}
	return marks, nil
}

// relationRowMatches is true when a library row's title carries one of the node's ids. TMDB ids
// are per kind; an AniList season also matches the TMDB show it maps to.
func relationRowMatches(n GraphNode, r sqlc.LibraryEntriesMatchingCatalogRow, show string) bool {
	eq := func(p *string, v string) bool { return p != nil && v != "" && *p == v }
	rowType := core.MediaType(r.Type)
	switch {
	case eq(r.Tmdb, n.IDs.TMDB) && rowType == n.Type:
		return true
	case eq(r.Tmdb, show) && rowType == core.MediaShow:
		return true
	case eq(r.Anilist, n.IDs.AniList):
		return true
	case eq(r.OpenLibrary, n.IDs.OpenLibrary) && rowType == core.MediaBook:
		return true
	case eq(r.Musicbrainz, n.IDs.MusicBrainz) && rowType == core.MediaAlbum:
		return true
	}
	return false
}

// TMDBRelatedEnricher fills Wikidata's films and shows from TMDB: the English title, the poster and
// the release date. A film TMDB does not answer for keeps what Wikidata said.
func TMDBRelatedEnricher(tmdb Searcher) func(context.Context, []RelatedNode) []RelatedNode {
	return func(ctx context.Context, nodes []RelatedNode) []RelatedNode {
		out := slices.Clone(nodes)
		g, gctx := safe.WithContext(ctx)
		g.SetLimit(relationFanOut)
		for i, n := range nodes {
			if n.IDs.TMDB == "" || (n.Type != core.MediaMovie && n.Type != core.MediaShow) {
				continue
			}
			g.Go(func() error {
				record, err := tmdb.Hydrate(gctx, core.ExternalIDs{TMDB: n.IDs.TMDB}, n.Type)
				if err != nil || record == nil {
					return nil //nolint:nilerr // a film TMDB cannot answer for keeps Wikidata's label
				}
				hit := record.Hit
				out[i].Title = cmp.Or(hit.Title, n.Title)
				out[i].PosterURL = hit.PosterURL
				out[i].ReleaseDate = cmp.Or(hit.ReleaseDate, n.ReleaseDate)
				if hit.Year != nil {
					out[i].Year = hit.Year
				}
				out[i].IDs = n.IDs.Filling(hit.IDs)
				out[i].IsAnime = n.IsAnime || hit.IsAnime
				return nil
			})
		}
		_ = g.Wait()
		return out
	}
}
