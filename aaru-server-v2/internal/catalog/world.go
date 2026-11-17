package catalog

import (
	"aaru-go-api/internal/core"
	"cmp"
	"context"
	"slices"
)

// A World (GRAPH-007, owner 2026-11-17) is one story universe across every kind: the titles the
// relation graph joins through sequels, side stories, spin-offs and adaptations, laid out with a
// lane per kind. Catalog data, the same for every user and joined by provider ids, never by name.
// It supersedes "never the whole franchise" for this one surface; the title room's graph keeps
// its own, smaller bounds.

// The World's bounds. A prequel or sequel in the same medium costs nothing to walk and anything
// else one hop, as in the relation graph. A universe larger than this is cut nearest its first
// title and says so (Marvel, Gundam, Fate).
const (
	WorldReach      = 4
	WorldMaxTitles  = 60
	WorldMaxLookups = 80
	// WorldMinTitles is the fewest titles that make a World: a title related to nothing has none.
	WorldMinTitles = 2
	// worldRootPasses is how often the walk starts over from an earlier first title before it
	// settles for the one it has.
	worldRootPasses = 3
)

// WorldLane is the kind a World's lane holds. Raw values are a wire contract and a column check.
type WorldLane string

// The lanes, in the order that breaks a tie between two lanes that start on the same day.
const (
	LaneBook  WorldLane = "book"
	LaneManga WorldLane = "manga"
	LaneFilm  WorldLane = "film"
	LaneShow  WorldLane = "show"
	LaneAnime WorldLane = "anime"
	LaneAlbum WorldLane = "album"
)

var worldLanes = []WorldLane{LaneBook, LaneManga, LaneFilm, LaneShow, LaneAnime, LaneAlbum}

// LaneOf is the lane a title sits in: anime is its own lane, whether a series or a film.
func LaneOf(n RelatedNode) WorldLane {
	switch n.Type {
	case core.MediaBook:
		return LaneBook
	case core.MediaManga:
		return LaneManga
	case core.MediaAlbum:
		return LaneAlbum
	case core.MediaMovie:
		if n.IsAnime {
			return LaneAnime
		}
		return LaneFilm
	default:
		if n.IsAnime {
			return LaneAnime
		}
		return LaneShow
	}
}

// WorldTitle is one title of a World, placed: its lane and its place in it.
type WorldTitle struct {
	RelatedNode
	// Key is the title's first id, the one links name it by. Keys are all of them: a title is in
	// the World when it carries any.
	Key  string
	Keys []string
	Lane WorldLane
	// LanePosition counts from 0 inside the lane.
	LanePosition int
	// Side is a side story or spin-off that leads nowhere further: drawn dimmer, still counted.
	Side bool
}

// World is a built World. Titles read lane by lane, each lane in order.
type World struct {
	// RootKey is the first-released title's key: the World's identity while its ids hold.
	RootKey string
	// Name is that title's name.
	Name   string
	Titles []WorldTitle
	Links  []GraphEdge
	// Truncated is true when the universe is larger than the bounds and was cut.
	Truncated bool
	// Partial is true when a source failed or ran out of time, so titles may be missing.
	Partial bool
}

// Has reports whether any of the keys names a title of the World.
func (w World) Has(keys []string) bool {
	for _, t := range w.Titles {
		for _, k := range t.Keys {
			if slices.Contains(keys, k) {
				return true
			}
		}
	}
	return false
}

// AllKeys is every id of every title, in title order.
func (w World) AllKeys() []string {
	var keys []string
	for _, t := range w.Titles {
		keys = append(keys, t.Keys...)
	}
	return keys
}

// worldFollows is the relations a World walks, written forward: the story going on, branching off
// and changing medium. Another version, a recap and "other" join titles that are not one story.
func worldFollows(r core.Relation) bool {
	switch r {
	case core.RelationSequel, core.RelationSideStory, core.RelationSpinOff, core.RelationAdaptation:
		return true
	}
	return false
}

// KnownRoots says which first titles Worlds already built around these ids start from, so a World
// reached from a new title keeps the start it had. Nil when nothing is stored.
type KnownRoots func(ctx context.Context, keys []string) []RelatedNode

// BuildWorld walks the sources out from anchor and lays out the World it belongs to. The walk
// starts over from the earliest-released title it finds, so the same World comes back whichever
// of its titles was asked about, bounded the same way. found is false when the anchor has no id
// or relates to nothing. A source that fails leaves the World partial; it never fails the build.
func BuildWorld(ctx context.Context, anchor RelatedNode, sources []RelationSource, known KnownRoots) (world World, found bool) {
	start := anchor
	var (
		b            *graphBuilder
		partial, cut bool
	)
	for pass := range worldRootPasses {
		b = newGraphBuilder(WorldMaxTitles)
		b.follow = worldFollows
		if _, ok := b.add(start); !ok {
			return World{}, false
		}
		failed, stopped := b.expand(ctx, sources, WorldReach, WorldMaxLookups)
		partial, cut = partial || failed, stopped
		root := b.earliest()
		if known != nil {
			for _, k := range known(ctx, b.keys()) {
				if releaseKey(k) < releaseKey(root) {
					root = k
				}
			}
		}
		if sameTitle(root, b.nodes[0].RelatedNode) || pass == worldRootPasses-1 {
			break
		}
		start = root
	}
	world = b.world(partial, cut || b.full)
	return world, len(world.Titles) >= WorldMinTitles
}

// sameTitle is true when the two nodes share an id.
func sameTitle(a, b RelatedNode) bool {
	keys := NodeKeys(b)
	return slices.ContainsFunc(NodeKeys(a), func(k string) bool { return slices.Contains(keys, k) })
}

// keys is every id of every node.
func (b *graphBuilder) keys() []string {
	var keys []string
	for _, n := range b.nodes {
		keys = append(keys, NodeKeys(n.RelatedNode)...)
	}
	return keys
}

// earliest is the first-released node; between two released on one day, the one found first.
func (b *graphBuilder) earliest() RelatedNode {
	best := 0
	for i := range b.nodes {
		if releaseKey(b.nodes[i].RelatedNode) < releaseKey(b.nodes[best].RelatedNode) {
			best = i
		}
	}
	return b.nodes[best].RelatedNode
}

// world lays the walked graph out, the first node as the root: every chain (prequels and sequels
// in one medium) in release order, chains in a lane by their first release, a side story after
// the title it hangs from, and lanes by the release of their first title.
func (b *graphBuilder) world(partial, truncated bool) World {
	cost, _, _ := b.walk()
	kept := make([]bool, len(b.nodes))
	for i := range b.nodes {
		kept[i] = cost[i] <= WorldReach
	}

	// Chains: titles joined by edges that cost nothing to walk.
	chainOf := make([]int, len(b.nodes))
	for i := range chainOf {
		chainOf[i] = i
	}
	var find func(int) int
	find = func(i int) int {
		if chainOf[i] != i {
			chainOf[i] = find(chainOf[i])
		}
		return chainOf[i]
	}
	for _, e := range b.edges {
		if kept[e.from] && kept[e.to] && b.weight(e) == 0 {
			chainOf[find(e.from)] = find(e.to)
		}
	}
	members := map[int][]int{}
	for i := range b.nodes {
		if kept[i] {
			members[find(i)] = append(members[find(i)], i)
		}
	}

	// A side title is a side story or spin-off that is a chain of one; it hangs from its parent.
	parent := make([]int, len(b.nodes))
	for i := range parent {
		parent[i] = -1
	}
	for _, e := range b.edges {
		side := e.relation == core.RelationSideStory || e.relation == core.RelationSpinOff
		if side && kept[e.from] && kept[e.to] && e.to != 0 && len(members[find(e.to)]) == 1 && parent[e.to] < 0 {
			parent[e.to] = e.from
		}
	}

	release := func(i int) string { return releaseKey(b.nodes[i].RelatedNode) }
	byRelease := func(x, y int) int { return cmp.Or(cmp.Compare(release(x), release(y)), cmp.Compare(x, y)) }

	// Each chain in its own order, chains by their first release.
	type chain struct {
		first string
		lead  int
		order []int
	}
	var chains []chain
	for _, m := range members {
		if len(m) == 1 && parent[m[0]] >= 0 {
			continue
		}
		_, order := b.releaseOrder(slices.Clone(m))
		c := chain{first: release(order[0]), lead: slices.Min(m), order: order}
		for _, i := range m {
			c.first = min(c.first, release(i))
		}
		chains = append(chains, c)
	}
	slices.SortFunc(chains, func(x, y chain) int { return cmp.Or(cmp.Compare(x.first, y.first), cmp.Compare(x.lead, y.lead)) })

	lanes := map[WorldLane][]int{}
	for _, c := range chains {
		for _, i := range c.order {
			lane := LaneOf(b.nodes[i].RelatedNode)
			lanes[lane] = append(lanes[lane], i)
		}
	}
	// Side titles nearest the root first, so a side story of a side story finds its parent placed.
	var sides []int
	for i := range b.nodes {
		if kept[i] && parent[i] >= 0 {
			sides = append(sides, i)
		}
	}
	slices.SortFunc(sides, func(x, y int) int { return cmp.Or(cmp.Compare(cost[x], cost[y]), byRelease(x, y)) })
	for _, i := range sides {
		lane := LaneOf(b.nodes[i].RelatedNode)
		at := slices.Index(lanes[lane], parent[i])
		if at < 0 {
			lanes[lane] = append(lanes[lane], i)
			continue
		}
		// After the parent and the side titles already under it that came out no later.
		at++
		for at < len(lanes[lane]) && parent[lanes[lane][at]] == parent[i] && byRelease(lanes[lane][at], i) < 0 {
			at++
		}
		lanes[lane] = slices.Insert(lanes[lane], at, i)
	}

	order := make([]WorldLane, 0, len(lanes))
	for _, lane := range worldLanes {
		if len(lanes[lane]) > 0 {
			order = append(order, lane)
		}
	}
	laneFirst := func(lane WorldLane) string {
		first := release(lanes[lane][0])
		for _, i := range lanes[lane] {
			first = min(first, release(i))
		}
		return first
	}
	slices.SortStableFunc(order, func(x, y WorldLane) int { return cmp.Compare(laneFirst(x), laneFirst(y)) })

	world := World{Truncated: truncated, Partial: partial, Titles: []WorldTitle{}, Links: []GraphEdge{}}
	if len(b.nodes) > 0 {
		world.RootKey, world.Name = b.nodes[0].Key, b.nodes[0].Title
	}
	for _, lane := range order {
		for position, i := range lanes[lane] {
			n := b.nodes[i]
			world.Titles = append(world.Titles, WorldTitle{
				RelatedNode: n.RelatedNode, Key: n.Key, Keys: NodeKeys(n.RelatedNode),
				Lane: lane, LanePosition: position, Side: parent[i] >= 0,
			})
			if world.Name == "" {
				world.Name = n.Title
			}
		}
	}
	for _, e := range b.edges {
		if kept[e.from] && kept[e.to] {
			world.Links = append(world.Links, GraphEdge{From: b.nodes[e.from].Key, To: b.nodes[e.to].Key, Relation: e.relation})
		}
	}
	return world
}
