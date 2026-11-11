package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/safe"
	"cmp"
	"context"
	"errors"
	"log/slog"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
)

// TreeDeadline bounds building one title tree for a page; what arrived by then is drawn, marked
// partial, and the person's works are read in the background for up to TreeWarmDeadline so the
// next read finds them cached.
const (
	TreeDeadline     = 4 * time.Second
	TreeWarmDeadline = time.Minute
)

// TreeNode is one title in a title tree. Key is stable within one tree.
type TreeNode struct {
	RelatedNode
	Key  string
	Pick core.TreePick
}

// TreeBranch is one row of a title tree. Label is the person's name; "" for the series and the
// adaptations, which the clients name themselves.
type TreeBranch struct {
	Kind  core.TreeBranchKind
	Label string
	Nodes []TreeNode
}

// Tree is where one title leads (GRAPH-005): the title and its branches, the people first (one,
// or three for a film or show read with its cast, GRAPH-006), then the series and the
// adaptations. Catalog data, the same for every user. Partial is true when a source failed or ran out of time.
type Tree struct {
	Root     TreeNode
	Branches []TreeBranch
	Partial  bool
}

// TreeService builds title trees over the relation graph and the credit sources.
type TreeService struct {
	Relations *RelationService
	Sources   []CreditSource
	// Deadline is how long a page waits (TreeDeadline when zero); tests shorten it.
	Deadline time.Duration
	cache    creditCache
	log      *slog.Logger
	// warming holds the titles whose credits are being read in the background.
	warming sync.Map
}

// NewTreeService builds the service. Sources may be empty: a tree then has the series only.
func NewTreeService(relations *RelationService, sources []CreditSource, log *slog.Logger) *TreeService {
	if log == nil {
		log = slog.Default()
	}
	return &TreeService{
		Relations: relations, Sources: sources, log: log,
		cache: creditCache{q: relations.Store.q, now: time.Now, log: log},
	}
}

// credited is who a title's tree branches on, and their works.
type credited struct {
	credit Credit
	works  []CreditedWork
}

// Tree is the title's tree. With cast, a film's or show's first two billed actors get a branch
// each after the person who made it (GRAPH-006). A source that fails leaves the tree partial; it
// never fails the tree.
func (s *TreeService) Tree(ctx context.Context, titleID uuid.UUID, cast bool) (Tree, error) {
	centre, err := s.Relations.centre(ctx, titleID)
	if err != nil {
		return Tree{}, err
	}
	deadline := time.Now().Add(cmp.Or(s.Deadline, TreeDeadline))
	pageCtx, cancel := context.WithDeadline(ctx, deadline)
	defer cancel()

	var (
		graph             RelationGraph
		people            []credited
		graphErr, credErr error
	)
	g, _ := safe.WithContext(pageCtx)
	g.Go(func() error {
		// The graph keeps its own deadline and warms itself when cut short.
		graph, graphErr = s.Relations.graphBy(ctx, titleID, OrderRelease, deadline)
		return nil
	})
	g.Go(func() error {
		people, credErr = s.people(pageCtx, centre, cast)
		return nil
	})
	_ = g.Wait()

	tree := Tree{Root: TreeNode{RelatedNode: centre, Key: "root", Pick: core.PickRoot}}
	tree.Partial = graphErr != nil || graph.Partial || credErr != nil
	if credErr != nil {
		if errors.Is(pageCtx.Err(), context.DeadlineExceeded) && ctx.Err() == nil {
			s.warm(ctx, centre, cast)
		} else {
			s.log.Warn("Title tree credits failed", "title", titleID.String(), "error", credErr.Error())
		}
	}
	// A title one person's branch shows is not shown again in the next person's.
	taken := map[string]bool{}
	for _, p := range people {
		branch, ok := s.personBranch(ctx, centre, graph, p, taken)
		if !ok {
			continue
		}
		tree.Branches = append(tree.Branches, branch)
		for _, n := range branch.Nodes {
			for _, k := range NodeKeys(n.RelatedNode) {
				taken[k] = true
			}
		}
	}
	tree.Branches = append(tree.Branches, graphBranches(graph)...)
	return tree, nil
}

// people asks the first source that knows the title who made it, and with cast who is billed
// first in it, then for each one's works, together. One person's works failing leaves the others:
// the error says the answer is short.
func (s *TreeService) people(ctx context.Context, centre RelatedNode, cast bool) ([]credited, error) {
	for _, source := range s.Sources {
		key := source.CreditKey(centre)
		if key == "" {
			continue
		}
		name := source.CreditSourceName()
		// v2: an answer cached before GRAPH-006 has no cast in it.
		all, err := cachedCredits(ctx, s.cache, name, "title:v2:"+key, func(ctx context.Context) ([]Credit, error) {
			return source.People(ctx, centre)
		})
		if err != nil {
			return nil, err
		}
		var credits []Credit
		made := false
		for _, c := range all {
			switch {
			case c.Kind.IsCast() && cast:
				credits = append(credits, c)
			case !c.Kind.IsCast() && !made:
				credits, made = append(credits, c), true
			}
		}
		if len(credits) == 0 {
			continue
		}
		found := make([]*credited, len(credits))
		errs := make([]error, len(credits))
		g, _ := safe.WithContext(ctx)
		for i, credit := range credits {
			g.Go(func() error {
				works, err := cachedCredits(ctx, s.cache, name, credit.cacheKey(),
					func(ctx context.Context) ([]CreditedWork, error) { return source.Works(ctx, credit) })
				if err != nil {
					errs[i] = err
					return nil
				}
				found[i] = &credited{credit: credit, works: works}
				return nil
			})
		}
		_ = g.Wait()
		out := make([]credited, 0, len(found))
		for _, p := range found {
			if p != nil {
				out = append(out, *p)
			}
		}
		return out, errors.Join(errs...)
	}
	return nil, nil
}

// warm reads the title's credits again past the page, detached from it, so they land in the cache.
func (s *TreeService) warm(ctx context.Context, centre RelatedNode, cast bool) {
	keys := NodeKeys(centre)
	if len(keys) == 0 {
		return
	}
	if _, busy := s.warming.LoadOrStore(keys[0], true); busy {
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), TreeWarmDeadline)
	go func() {
		defer cancel()
		defer s.warming.Delete(keys[0])
		defer func() { _ = recovered(s.log, "title tree warm", recover()) }()
		if _, err := s.people(ctx, centre, cast); err != nil {
			s.log.Warn("Title tree warm failed", "key", keys[0], "error", err.Error())
		}
	}()
}

// personBranch picks the person's branch: their works without the root, without what the relation
// graph or an earlier person's branch (taken) already shows, and with an anime's seasons folded
// into one title.
func (s *TreeService) personBranch(
	ctx context.Context, centre RelatedNode, graph RelationGraph, p credited, taken map[string]bool,
) (TreeBranch, bool) {
	rootKeys := map[string]bool{}
	for _, k := range NodeKeys(centre) {
		rootKeys[k] = true
	}
	shown := map[string]bool{}
	for _, n := range graph.Nodes {
		for _, k := range NodeKeys(n.RelatedNode) {
			shown[k] = true
		}
	}
	rootDate := treeDate(centre)
	for _, n := range graph.Nodes {
		if n.Centre && n.ReleaseDate != nil {
			rootDate = *n.ReleaseDate
		}
	}
	works := make([]CreditedWork, 0, len(p.works))
	for _, w := range p.works {
		keys := NodeKeys(w.RelatedNode)
		if slices.ContainsFunc(keys, func(k string) bool { return rootKeys[k] }) {
			// The provider's own date for the root is the one its other works compare against.
			if d := treeDate(w.RelatedNode); len(d) > len(rootDate) || rootDate == "" {
				rootDate = d
			}
			continue
		}
		if slices.ContainsFunc(keys, func(k string) bool { return shown[k] || taken[k] }) {
			continue
		}
		works = append(works, w)
	}
	works = s.foldSeasons(ctx, centre, works)

	candidates := make([]core.TreeCandidate, len(works))
	ranked := false
	for i, w := range works {
		candidates[i] = core.TreeCandidate{Date: treeDate(w.RelatedNode), Score: w.Score}
		ranked = ranked || w.Score > 0
	}
	branch := TreeBranch{Kind: p.credit.Kind, Label: p.credit.Name}
	for i, choice := range core.PickTreeBranch(candidates, rootDate, ranked) {
		branch.Nodes = append(branch.Nodes, TreeNode{
			RelatedNode: works[choice.Index].RelatedNode, Key: "p" + strconv.Itoa(i), Pick: choice.Pick,
		})
	}
	return branch, len(branch.Nodes) > 0
}

// foldSeasons keeps one entry per anime show: AniList lists each season on its own, and a
// studio's three most popular works must not be three seasons of one show. Seasons are joined by
// the TMDB show they map to (`anime_mappings`), the earliest kept with the highest count; the
// root's own seasons are dropped. A failed read leaves the works as they are.
func (s *TreeService) foldSeasons(ctx context.Context, centre RelatedNode, works []CreditedWork) []CreditedWork {
	var ids []string
	for _, w := range works {
		if w.IDs.AniList != "" && w.Type != core.MediaManga {
			ids = append(ids, w.IDs.AniList)
		}
	}
	if len(ids) == 0 {
		return works
	}
	if centre.IDs.AniList != "" {
		ids = append(ids, centre.IDs.AniList)
	}
	mappings, err := s.Relations.Store.MappingsByAniList(ctx, ids)
	if err != nil {
		s.log.Warn("Title tree could not read anime mappings", "error", err.Error())
		return works
	}
	showOf := map[string]string{}
	for _, m := range mappings {
		if m.TMDB != nil && *m.TMDB != "" {
			showOf[m.AniList] = *m.TMDB
		}
	}
	rootShow := cmp.Or(showOf[centre.IDs.AniList], centre.IDs.TMDB)
	out := make([]CreditedWork, 0, len(works))
	at := map[string]int{}
	for _, w := range works {
		show := showOf[w.IDs.AniList]
		if show == "" || w.Type != core.MediaShow {
			out = append(out, w)
			continue
		}
		if show == rootShow && centre.Type == core.MediaShow {
			continue
		}
		i, seen := at[show]
		if !seen {
			at[show] = len(out)
			out = append(out, w)
			continue
		}
		score := max(out[i].Score, w.Score)
		if d := treeDate(w.RelatedNode); d != "" && (treeDate(out[i].RelatedNode) == "" || d < treeDate(out[i].RelatedNode)) {
			out[i] = w
		}
		out[i].Score = score
	}
	return out
}

// graphBranches cuts the series and the adaptations out of the relation graph: the main chain
// after the centre, in the graph's order, and the titles the centre is based on or adapted into.
func graphBranches(graph RelationGraph) []TreeBranch {
	var centre *GraphNode
	byKey := map[string]GraphNode{}
	for i, n := range graph.Nodes {
		byKey[n.Key] = n
		if n.Centre {
			centre = &graph.Nodes[i]
		}
	}
	if centre == nil {
		return nil
	}
	var branches []TreeBranch
	chain := make([]GraphNode, 0, len(graph.Nodes))
	for _, n := range graph.Nodes {
		if n.MainChain && !n.Centre && n.Rank > centre.Rank {
			chain = append(chain, n)
		}
	}
	slices.SortStableFunc(chain, func(a, b GraphNode) int { return cmp.Compare(a.Rank, b.Rank) })
	series := TreeBranch{Kind: core.BranchSeries}
	for i, n := range chain[:min(len(chain), core.TreeBranchSize)] {
		series.Nodes = append(series.Nodes, TreeNode{RelatedNode: n.RelatedNode, Key: "s" + strconv.Itoa(i), Pick: core.PickSeries})
	}
	if len(series.Nodes) > 0 {
		branches = append(branches, series)
	}
	adaptations := TreeBranch{Kind: core.BranchAdaptation}
	seen := map[string]bool{}
	for _, e := range graph.Edges {
		if e.Relation != core.RelationAdaptation || len(adaptations.Nodes) == core.TreeBranchSize {
			continue
		}
		other := e.To
		switch centre.Key {
		case e.From:
		case e.To:
			other = e.From
		default:
			continue
		}
		n, ok := byKey[other]
		if !ok || n.MainChain || seen[other] {
			continue
		}
		seen[other] = true
		adaptations.Nodes = append(adaptations.Nodes, TreeNode{
			RelatedNode: n.RelatedNode, Key: "a" + strconv.Itoa(len(adaptations.Nodes)), Pick: core.PickAdaptation,
		})
	}
	if len(adaptations.Nodes) > 0 {
		branches = append(branches, adaptations)
	}
	return branches
}

// treeDate is a title's date for the branch rule: the full date, else the year, else "".
func treeDate(n RelatedNode) string {
	if n.ReleaseDate != nil && len(*n.ReleaseDate) >= 4 {
		return *n.ReleaseDate
	}
	if n.Year != nil {
		return strconv.Itoa(*n.Year)
	}
	return ""
}

// Marks are the user's items among the tree's titles, by node key, read the way the relation
// graph reads them.
func (s *TreeService) Marks(ctx context.Context, userID uuid.UUID, tree Tree) (map[string]RelationMark, error) {
	nodes := []GraphNode{{RelatedNode: tree.Root.RelatedNode, Key: tree.Root.Key}}
	for _, b := range tree.Branches {
		for _, n := range b.Nodes {
			nodes = append(nodes, GraphNode{RelatedNode: n.RelatedNode, Key: b.NodeKey(n)})
		}
	}
	return s.Relations.Marks(ctx, userID, RelationGraph{Nodes: nodes})
}

// NodeKey is a node's key within the whole tree: the one Marks files it under.
func (b TreeBranch) NodeKey(n TreeNode) string { return string(b.Kind) + ":" + n.Key }
