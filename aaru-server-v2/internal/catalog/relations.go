package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/safe"
	"cmp"
	"context"
	"fmt"
	"slices"
	"sync"
)

// The relation graph's bounds (GRAPH-001, owner 2026-11-06: the direct chain and its adaptations,
// not the whole franchise). A prequel or sequel in the same medium costs nothing to walk, anything
// else costs one hop; nodes up to RelationReach hops are shown, nodes under it are asked about.
const (
	RelationReach         = 2
	RelationMaxNodes      = 40
	RelationMaxExpansions = 24
	// relationFanOut is how many provider calls one round runs at once; each provider's pacer
	// still decides how fast they go out.
	relationFanOut = 4
)

// RelationOrder is the order a graph's main chain reads in: release (the default) or story, where
// the data has it.
type RelationOrder string

// The relation orders.
const (
	OrderRelease RelationOrder = "release"
	OrderStory   RelationOrder = "story"
)

// RelatedNode is one title as a relation source knows it. Catalog data, never a library row.
type RelatedNode struct {
	Type    core.MediaType   `json:"type"`
	IsAnime bool             `json:"isAnime,omitempty"`
	IDs     core.ExternalIDs `json:"ids"`
	// Wikidata is the item's Q-id, once known.
	Wikidata    string  `json:"wikidata,omitempty"`
	Title       string  `json:"title"`
	Year        *int    `json:"year,omitempty"`
	ReleaseDate *string `json:"releaseDate,omitempty"`
	PosterURL   *string `json:"posterUrl,omitempty"`
	// Format is the provider's own word for what it is (AniList: tv, movie, ova, novel…); "" when unknown.
	Format string `json:"format,omitempty"`
	// Series are its numbered places in a series (Wikidata), the story order.
	Series []SeriesPlace `json:"series,omitempty"`
}

// SeriesPlace is one numbered place in a series.
type SeriesPlace struct {
	Series  string  `json:"series"`
	Ordinal float64 `json:"ordinal"`
}

// RelatedEdge says To is From's Relation. A nil From is the node the source was asked about.
type RelatedEdge struct {
	From     *RelatedNode  `json:"from,omitempty"`
	To       RelatedNode   `json:"to"`
	Relation core.Relation `json:"relation"`
}

// Relations is one source's answer for one node: its edges, and what it learned about the node
// itself (a Wikidata id, its places in a series).
type Relations struct {
	Self  *RelatedNode  `json:"self,omitempty"`
	Edges []RelatedEdge `json:"edges"`
}

// RelationSource is one provider of relations: AniList, TMDB collections, Wikidata.
type RelationSource interface {
	// RelationSourceName names the source in the cache.
	RelationSourceName() string
	// RelationKey is the node's cache key at this source; "" when the source cannot answer for it.
	RelationKey(n RelatedNode) string
	Relations(ctx context.Context, n RelatedNode) (Relations, error)
}

// ChainOnlySource is a source asked only about main-chain titles: AniList, whose rate limit cannot
// pay for every side story's own relations.
type ChainOnlySource interface {
	ChainOnly() bool
}

func chainOnly(source RelationSource) bool {
	c, ok := source.(ChainOnlySource)
	return ok && c.ChainOnly()
}

// GraphNode is one title in a built graph, placed for drawing: Rank is its column, Lane its row
// (0 is the main chain).
type GraphNode struct {
	RelatedNode
	Key       string
	Rank      int
	Lane      int
	MainChain bool
	Centre    bool
}

// GraphEdge says the node To is the node From's Relation, by key.
type GraphEdge struct {
	From, To string
	Relation core.Relation
}

// RelationGraph is a title's relations, placed. Partial is true when a source failed or ran out of
// time, so the graph may be missing some titles.
type RelationGraph struct {
	Nodes               []GraphNode
	Edges               []GraphEdge
	Order               RelationOrder
	StoryOrderAvailable bool
	Partial             bool
}

// StartHere is the key of the first main-chain title, in the graph's order, the user has not
// finished or dropped; nil when they are all done. status is the user's status by node key.
func (g RelationGraph) StartHere(status map[string]core.LibraryStatus) *string {
	chain := make([]GraphNode, 0, len(g.Nodes))
	for _, n := range g.Nodes {
		if n.MainChain {
			chain = append(chain, n)
		}
	}
	slices.SortStableFunc(chain, func(a, b GraphNode) int { return cmp.Compare(a.Rank, b.Rank) })
	for _, n := range chain {
		switch status[n.Key] {
		case core.StatusFinished, core.StatusDropped:
			continue
		}
		key := n.Key
		return &key
	}
	return nil
}

// NodeKeys are the ids that identify a node, most stable first. Two nodes sharing any key are the
// same title; a node is never matched by its name.
func NodeKeys(n RelatedNode) []string {
	var keys []string
	if n.Wikidata != "" {
		keys = append(keys, "wikidata:"+n.Wikidata)
	}
	if n.IDs.AniList != "" {
		keys = append(keys, "anilist:"+n.IDs.AniList)
	}
	if n.IDs.MAL != "" {
		keys = append(keys, "mal:"+malKind(n.Type)+":"+n.IDs.MAL)
	}
	if n.IDs.TMDB != "" && (n.Type == core.MediaMovie || n.Type == core.MediaShow) {
		keys = append(keys, "tmdb:"+string(n.Type)+":"+n.IDs.TMDB)
	}
	if n.IDs.IMDB != "" {
		keys = append(keys, "imdb:"+n.IDs.IMDB)
	}
	if n.IDs.OpenLibrary != "" {
		keys = append(keys, "openlibrary:"+n.IDs.OpenLibrary)
	}
	if n.IDs.MusicBrainz != "" {
		keys = append(keys, "musicbrainz:"+n.IDs.MusicBrainz)
	}
	return keys
}

// malKind is MyAnimeList's split: manga numbers apart from anime.
func malKind(t core.MediaType) string {
	if t == core.MediaManga {
		return "manga"
	}
	return "anime"
}

// BuildRelationGraph walks the sources out from centre, merges what they say by id, and places the
// result. A source that fails leaves the graph partial; it never fails the graph.
func BuildRelationGraph(ctx context.Context, centre RelatedNode, sources []RelationSource, order RelationOrder) RelationGraph {
	b := &graphBuilder{byKey: map[string]int{}, seen: map[[2]int]bool{}, asked: map[[2]int]bool{}}
	if _, ok := b.add(centre); !ok {
		return RelationGraph{Order: OrderRelease}
	}
	partial := false
	expansions := 0
	for expansions < RelationMaxExpansions {
		if ctx.Err() != nil {
			partial = true
			break
		}
		cost, _, _ := b.walk()
		var round []int
		for i := range b.nodes {
			if cost[i] < RelationReach && b.pending(i, cost[i], sources) {
				round = append(round, i)
			}
		}
		if len(round) == 0 {
			break
		}
		slices.SortStableFunc(round, func(x, y int) int { return cmp.Compare(cost[x], cost[y]) })
		round = round[:min(len(round), RelationMaxExpansions-expansions)]
		results, failed := b.ask(ctx, round, cost, sources)
		partial = partial || failed
		expansions += len(round)
		b.absorb(round, results)
	}
	return b.place(order, partial)
}

type graphEdge struct {
	from, to int
	relation core.Relation
}

type graphBuilder struct {
	nodes []*GraphNode
	byKey map[string]int
	edges []graphEdge
	seen  map[[2]int]bool
	// asked holds the (node, source) pairs already asked. A node is asked again by a source that
	// could not answer for it before: Wikidata naming a TMDB show's AniList id opens AniList's chain.
	asked map[[2]int]bool
}

// askable is true when the source can answer for the node and has not been asked yet.
func (b *graphBuilder) askable(i, si int, source RelationSource, cost int) bool {
	if b.asked[[2]int{i, si}] || (cost > 0 && chainOnly(source)) {
		return false
	}
	return source.RelationKey(b.nodes[i].RelatedNode) != ""
}

// pending is true while any source still has something to say about the node.
func (b *graphBuilder) pending(i, cost int, sources []RelationSource) bool {
	for si, source := range sources {
		if b.askable(i, si, source, cost) {
			return true
		}
	}
	return false
}

// add is the node's index, merging it into a node it shares an id with; false when it has no id
// or the graph is full.
func (b *graphBuilder) add(n RelatedNode) (int, bool) {
	keys := NodeKeys(n)
	for _, k := range keys {
		if i, ok := b.byKey[k]; ok {
			b.merge(i, n)
			return i, true
		}
	}
	if len(keys) == 0 || len(b.nodes) >= RelationMaxNodes {
		return -1, false
	}
	i := len(b.nodes)
	b.nodes = append(b.nodes, &GraphNode{RelatedNode: n, Key: keys[0], Centre: i == 0})
	for _, k := range keys {
		b.byKey[k] = i
	}
	return i, true
}

// merge fills the node's empty fields from another view of the same title; the first source to
// say something keeps it. A new id points at the node unless it already names another one.
func (b *graphBuilder) merge(i int, n RelatedNode) {
	node := &b.nodes[i].RelatedNode
	node.IDs = node.IDs.Filling(n.IDs)
	node.Wikidata = cmp.Or(node.Wikidata, n.Wikidata)
	node.Title = cmp.Or(node.Title, n.Title)
	node.Format = cmp.Or(node.Format, n.Format)
	node.IsAnime = node.IsAnime || n.IsAnime
	if node.Year == nil {
		node.Year = n.Year
	}
	if node.ReleaseDate == nil {
		node.ReleaseDate = n.ReleaseDate
	}
	if node.PosterURL == nil {
		node.PosterURL = n.PosterURL
	}
	for _, s := range n.Series {
		if !slices.ContainsFunc(node.Series, func(t SeriesPlace) bool { return t.Series == s.Series }) {
			node.Series = append(node.Series, s)
		}
	}
	for _, k := range NodeKeys(*node) {
		if _, taken := b.byKey[k]; !taken {
			b.byKey[k] = i
		}
	}
}

// link records "to is from's relation" once per pair, written forward.
func (b *graphBuilder) link(from, to int, relation core.Relation) {
	if from < 0 || to < 0 || from == to || !relation.Valid() {
		return
	}
	relation, flipped := relation.Canonical()
	if flipped {
		from, to = to, from
	}
	pair := [2]int{min(from, to), max(from, to)}
	if b.seen[pair] {
		return
	}
	b.seen[pair] = true
	b.edges = append(b.edges, graphEdge{from: from, to: to, relation: relation})
}

// weight is what an edge costs to walk: nothing along a same-medium main chain, one hop otherwise.
func (b *graphBuilder) weight(e graphEdge) int {
	if e.relation.MainChain() && core.SameMedium(b.nodes[e.from].Type, b.nodes[e.to].Type) {
		return 0
	}
	return 1
}

// walk is a 0-1 breadth-first walk from the centre: each node's cost, the node it was reached
// from (-1 for the centre and the unreached), and the order nodes were settled in.
func (b *graphBuilder) walk() (cost, parent, settled []int) {
	const unreached = 1 << 30
	cost = make([]int, len(b.nodes))
	parent = make([]int, len(b.nodes))
	for i := range cost {
		cost[i], parent[i] = unreached, -1
	}
	cost[0] = 0
	done := make([]bool, len(b.nodes))
	deque := []int{0}
	for len(deque) > 0 {
		u := deque[0]
		deque = deque[1:]
		if done[u] {
			continue
		}
		done[u] = true
		settled = append(settled, u)
		for _, e := range b.edges {
			v := -1
			switch u {
			case e.from:
				v = e.to
			case e.to:
				v = e.from
			}
			if v < 0 || done[v] {
				continue
			}
			w := b.weight(e)
			if cost[u]+w < cost[v] {
				cost[v], parent[v] = cost[u]+w, u
				if w == 0 {
					deque = append([]int{v}, deque...)
				} else {
					deque = append(deque, v)
				}
			}
		}
	}
	return cost, parent, settled
}

// ask runs every source that can answer for each node, a few at a time. failed is true when any
// call failed or panicked.
func (b *graphBuilder) ask(ctx context.Context, round, cost []int, sources []RelationSource) ([][]*Relations, bool) {
	results := make([][]*Relations, len(round))
	var mu sync.Mutex
	failed := false
	g, gctx := safe.WithContext(ctx)
	g.SetLimit(relationFanOut)
	for ri, i := range round {
		results[ri] = make([]*Relations, len(sources))
		node := b.nodes[i].RelatedNode
		for si, source := range sources {
			if !b.askable(i, si, source, cost[i]) {
				continue
			}
			b.asked[[2]int{i, si}] = true
			g.Go(func() error {
				r, err := source.Relations(gctx, node)
				mu.Lock()
				defer mu.Unlock()
				if err != nil {
					failed = true
					return nil
				}
				results[ri][si] = &r
				return nil
			})
		}
	}
	if err := g.Wait(); err != nil {
		failed = true
	}
	return results, failed
}

// absorb merges a round's answers: what each source learned about the node first, then main-chain
// edges before the rest, so a full graph keeps the chain.
func (b *graphBuilder) absorb(round []int, results [][]*Relations) {
	for ri, i := range round {
		for _, r := range results[ri] {
			if r != nil && r.Self != nil {
				b.merge(i, *r.Self)
			}
		}
	}
	for _, chain := range []bool{true, false} {
		for ri, i := range round {
			for _, r := range results[ri] {
				if r == nil {
					continue
				}
				for _, e := range r.Edges {
					if e.Relation.MainChain() != chain {
						continue
					}
					from := i
					if e.From != nil {
						var ok bool
						if from, ok = b.add(*e.From); !ok {
							continue
						}
					}
					if e.Relation.MainChain() && e.To.Type == core.MediaAlbum && b.nodes[from].Type == core.MediaAlbum {
						continue // an album's "follows" is the artist's discography, not a story
					}
					if to, ok := b.add(e.To); ok {
						b.link(from, to, e.Relation)
					}
				}
			}
		}
	}
}

// releaseKey sorts by first release: a full date, else the year's end, else last.
func releaseKey(n RelatedNode) string {
	if n.ReleaseDate != nil && len(*n.ReleaseDate) >= 4 {
		return *n.ReleaseDate
	}
	if n.Year != nil {
		return fmt.Sprintf("%04d-13", *n.Year)
	}
	return "9999"
}

// storySeries is the series that numbers the most main-chain nodes (at least two), or "".
func storySeries(nodes []*GraphNode, chain []int) string {
	counts := map[string]int{}
	for _, i := range chain {
		for _, s := range nodes[i].Series {
			counts[s.Series]++
		}
	}
	best, bestCount := "", 1
	for s, c := range counts {
		if c > bestCount || (c == bestCount && c > 1 && s < best) {
			best, bestCount = s, c
		}
	}
	return best
}

func ordinal(n *GraphNode, series string) (float64, bool) {
	for _, s := range n.Series {
		if s.Series == series {
			return s.Ordinal, true
		}
	}
	return 0, false
}

// place lays the graph out: the main chain on lane 0 in the chosen order, each other title under
// the chain title it hangs from (a step along when it continues another title), in the first free
// lane below.
func (b *graphBuilder) place(order RelationOrder, partial bool) RelationGraph {
	cost, parent, settled := b.walk()
	keep := func(i int) bool { return cost[i] <= RelationReach }
	var chain []int
	for _, i := range settled {
		if cost[i] == 0 {
			chain = append(chain, i)
		}
	}
	byRelease := func(x, y int) int {
		return cmp.Or(cmp.Compare(releaseKey(b.nodes[x].RelatedNode), releaseKey(b.nodes[y].RelatedNode)), cmp.Compare(x, y))
	}
	// Links give the order a source tells the story in; dates give release order, used whenever every
	// chain title has one (an undated title keeps its linked place). Story order is a numbered series where there is one, else the links.
	linked := b.chainOrder(chain, byRelease)
	release := slices.Clone(linked)
	var slots, dated []int
	for pos, i := range linked {
		if releaseKey(b.nodes[i].RelatedNode) != "9999" {
			slots, dated = append(slots, pos), append(dated, i)
		}
	}
	// Dated titles are sorted among their own places; an undated one keeps its place in the links.
	slices.SortStableFunc(dated, func(x, y int) int {
		return cmp.Compare(releaseKey(b.nodes[x].RelatedNode), releaseKey(b.nodes[y].RelatedNode))
	})
	for k, pos := range slots {
		release[pos] = dated[k]
	}
	story := slices.Clone(linked)
	if series := storySeries(b.nodes, linked); series != "" {
		slices.SortStableFunc(story, func(x, y int) int {
			ox, okx := ordinal(b.nodes[x], series)
			oy, oky := ordinal(b.nodes[y], series)
			switch {
			case okx && oky:
				return cmp.Compare(ox, oy)
			case okx:
				return -1
			case oky:
				return 1
			}
			return 0
		})
	}
	storyAvailable := !slices.Equal(story, release)
	chain = release
	if order == OrderStory && storyAvailable {
		chain = story
	} else {
		order = OrderRelease
	}

	rank := make([]int, len(b.nodes))
	lane := make([]int, len(b.nodes))
	placed := make([]bool, len(b.nodes))
	taken := map[[2]int]bool{}
	for r, i := range chain {
		rank[i], lane[i], placed[i] = r, 0, true
		taken[[2]int{0, r}] = true
	}
	for _, v := range settled {
		if placed[v] || !keep(v) {
			continue
		}
		rank[v] = b.anchorRank(v, parent[v], cost, rank, placed)
		preferred := 1
		if p := parent[v]; p >= 0 && lane[p] > 0 && b.chained(p, v) {
			preferred = lane[p]
		}
		l := preferred
		if taken[[2]int{l, rank[v]}] {
			l = 1
			for taken[[2]int{l, rank[v]}] {
				l++
			}
		}
		lane[v], placed[v] = l, true
		taken[[2]int{l, rank[v]}] = true
	}

	lowest := 0
	for i := range b.nodes {
		if placed[i] {
			lowest = min(lowest, rank[i])
		}
	}
	graph := RelationGraph{Order: order, StoryOrderAvailable: storyAvailable, Partial: partial, Nodes: []GraphNode{}, Edges: []GraphEdge{}}
	for i, n := range b.nodes {
		if !placed[i] {
			continue
		}
		node := *n
		node.Rank, node.Lane, node.MainChain = rank[i]-lowest, lane[i], cost[i] == 0
		graph.Nodes = append(graph.Nodes, node)
	}
	slices.SortStableFunc(graph.Nodes, func(x, y GraphNode) int {
		return cmp.Or(cmp.Compare(x.Rank, y.Rank), cmp.Compare(x.Lane, y.Lane))
	})
	for _, e := range b.edges {
		if placed[e.from] && placed[e.to] {
			graph.Edges = append(graph.Edges, GraphEdge{From: b.nodes[e.from].Key, To: b.nodes[e.to].Key, Relation: e.relation})
		}
	}
	return graph
}

// chained is true when p and v are a prequel/sequel pair.
func (b *graphBuilder) chained(p, v int) bool {
	for _, e := range b.edges {
		if ((e.from == p && e.to == v) || (e.from == v && e.to == p)) && e.relation.MainChain() {
			return true
		}
	}
	return false
}

// anchorRank is the column for an off-chain node: under the earliest chain title it relates to,
// else a step after (or before) the title it continues, else under the title it was reached from.
func (b *graphBuilder) anchorRank(v, p int, cost, rank []int, placed []bool) int {
	best, found := 0, false
	for _, e := range b.edges {
		other := -1
		switch v {
		case e.from:
			other = e.to
		case e.to:
			other = e.from
		}
		if other < 0 || !placed[other] || cost[other] != 0 {
			continue
		}
		if !found || rank[other] < best {
			best, found = rank[other], true
		}
	}
	if found {
		return best
	}
	if p < 0 || !placed[p] {
		return 0
	}
	for _, e := range b.edges {
		if !e.relation.MainChain() {
			continue
		}
		if e.from == p && e.to == v {
			return rank[p] + 1
		}
		if e.from == v && e.to == p {
			return rank[p] - 1
		}
	}
	return rank[p]
}

// chainOrder orders the main chain along its sequel links, earliest first; release dates only
// break ties (two sequels of one title) and order a chain whose links loop.
func (b *graphBuilder) chainOrder(chain []int, byRelease func(x, y int) int) []int {
	slices.SortStableFunc(chain, byRelease)
	in := map[int]bool{}
	for _, i := range chain {
		in[i] = true
	}
	before := map[int]int{}
	next := map[int][]int{}
	for _, e := range b.edges {
		if e.relation == core.RelationSequel && in[e.from] && in[e.to] {
			before[e.to]++
			next[e.from] = append(next[e.from], e.to)
		}
	}
	var ready, out []int
	for _, i := range chain {
		if before[i] == 0 {
			ready = append(ready, i)
		}
	}
	done := map[int]bool{}
	for len(out) < len(chain) {
		if len(ready) == 0 {
			// A loop: take the earliest title not placed yet and carry on from it.
			for _, i := range chain {
				if !done[i] {
					ready = append(ready, i)
					break
				}
			}
		}
		slices.SortStableFunc(ready, byRelease)
		u := ready[0]
		ready = ready[1:]
		if done[u] {
			continue
		}
		done[u] = true
		out = append(out, u)
		for _, v := range next[u] {
			before[v]--
			if before[v] == 0 && !done[v] {
				ready = append(ready, v)
			}
		}
	}
	return out
}
