package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"

	"github.com/google/uuid"
)

// Reading Worlds (GRAPH-007): from the database only. A read that finds nothing queues the build
// and says so; it never walks a provider.

// WorldState is what a read of a title's World found.
type WorldState string

// The states. Raw values are a wire contract.
const (
	// WorldReady: the World is there.
	WorldReady WorldState = "ready"
	// WorldBuilding: it is queued or being built; ask again shortly.
	WorldBuilding WorldState = "building"
	// WorldNone: the title was looked at and relates to nothing, or sits outside its universe's cut.
	WorldNone WorldState = "none"
)

// MaxUserWorlds is how many Worlds one user's list holds.
const MaxUserWorlds = 100

// StoredWorld is a World as it is stored, with its id.
type StoredWorld struct {
	World
	ID uuid.UUID
	// Anchor is the key of the title it was read for; "" when read for no title.
	Anchor string
	// TitleID is one of the user's own titles in it, to open it from; Nil outside a user's list.
	TitleID uuid.UUID
}

// For is the World the title belongs to. Nothing stored and nothing known queues its build, ahead
// of any import's backlog, and reads as building.
func (s *WorldService) For(ctx context.Context, titleID uuid.UUID) (StoredWorld, WorldState, error) {
	anchor, err := s.Relations.centre(ctx, titleID)
	if err != nil {
		return StoredWorld{}, WorldNone, err
	}
	keys := NodeKeys(anchor)
	if len(keys) == 0 {
		return StoredWorld{}, WorldNone, nil
	}
	rows, err := s.Store.q.WorldByKeys(ctx, keys)
	if err != nil {
		return StoredWorld{}, WorldNone, fmt.Errorf("world by keys: %w", err)
	}
	if len(rows) > 0 {
		row := rows[0]
		titles, err := s.Store.q.WorldTitles(ctx, row.ID)
		if err != nil {
			return StoredWorld{}, WorldNone, fmt.Errorf("world titles: %w", err)
		}
		world, err := storedWorld(row, titles)
		if err != nil {
			return StoredWorld{}, WorldNone, err
		}
		position, err := s.Store.q.WorldKeyPosition(ctx, sqlc.WorldKeyPositionParams{WorldID: row.ID, NodeKeys: keys})
		if err == nil && int(position) < len(world.Titles) {
			world.Anchor = world.Titles[position].Key
		} else if err != nil && !db.IsNoRows(err) {
			return StoredWorld{}, WorldNone, fmt.Errorf("world anchor: %w", err)
		}
		// A World past its recheck is rebuilt behind the read; this one is served meanwhile.
		if s.Now().Sub(row.BuiltAt) > WorldRecheck {
			s.Enqueue(ctx, titleID, WorldPriorityOpened)
		}
		return world, WorldReady, nil
	}
	build, err := s.Store.q.WorldBuild(ctx, titleID)
	switch {
	case db.IsNoRows(err):
		s.Enqueue(ctx, titleID, WorldPriorityOpened)
		return StoredWorld{}, WorldBuilding, nil
	case err != nil:
		return StoredWorld{}, WorldNone, fmt.Errorf("world build: %w", err)
	}
	if build.State == "queued" || build.State == "running" {
		// Someone is waiting on it now: it goes ahead of an import's backlog.
		if build.State == "queued" && build.Priority < WorldPriorityOpened {
			s.Enqueue(ctx, titleID, WorldPriorityOpened)
		}
		return StoredWorld{}, WorldBuilding, nil
	}
	// Looked at, and no World: asked again only once that look is stale.
	if build.CheckedAt == nil || s.Now().Sub(*build.CheckedAt) > WorldRecheck {
		s.Enqueue(ctx, titleID, WorldPriorityOpened)
		return StoredWorld{}, WorldBuilding, nil
	}
	return StoredWorld{}, WorldNone, nil
}

// Mine are the Worlds the user has at least one library item in, newest build first.
func (s *WorldService) Mine(ctx context.Context, userID uuid.UUID) ([]StoredWorld, error) {
	rows, err := s.Store.q.UserWorlds(ctx, sqlc.UserWorldsParams{UserID: userID, MaxWorlds: MaxUserWorlds})
	if err != nil {
		return nil, fmt.Errorf("user worlds: %w", err)
	}
	if len(rows) == 0 {
		return []StoredWorld{}, nil
	}
	ids := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	all, err := s.Store.q.WorldTitlesOfWorlds(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("world titles: %w", err)
	}
	byWorld := map[uuid.UUID][]sqlc.WorldTitlesRow{}
	for _, t := range all {
		byWorld[t.WorldID] = append(byWorld[t.WorldID], sqlc.WorldTitlesRow{
			Position: t.Position, NodeKey: t.NodeKey, Lane: t.Lane, LanePosition: t.LanePosition, Side: t.Side, Node: t.Node,
		})
	}
	out := make([]StoredWorld, 0, len(rows))
	for _, r := range rows {
		world, err := storedWorld(sqlc.World{
			ID: r.ID, RootKey: r.RootKey, Name: r.Name, Links: r.Links, Truncated: r.Truncated, Partial: r.Partial,
			TitleCount: r.TitleCount, BuiltAt: r.BuiltAt, CreatedAt: r.CreatedAt,
		}, byWorld[r.ID])
		if err != nil {
			return nil, err
		}
		world.TitleID = r.TitleID
		out = append(out, world)
	}
	return out, nil
}

// storedWorld reads a World back from its rows.
func storedWorld(row sqlc.World, titles []sqlc.WorldTitlesRow) (StoredWorld, error) {
	world := StoredWorld{ID: row.ID, World: World{
		RootKey: row.RootKey, Name: row.Name, Truncated: row.Truncated, Partial: row.Partial,
		Titles: make([]WorldTitle, 0, len(titles)), Links: []GraphEdge{},
	}}
	if err := json.Unmarshal(row.Links, &world.Links); err != nil {
		return StoredWorld{}, fmt.Errorf("decode world links: %w", err)
	}
	for _, t := range titles {
		var node RelatedNode
		if err := json.Unmarshal(t.Node, &node); err != nil {
			return StoredWorld{}, fmt.Errorf("decode world title: %w", err)
		}
		world.Titles = append(world.Titles, WorldTitle{
			RelatedNode: node, Key: t.NodeKey, Keys: NodeKeys(node), Lane: WorldLane(t.Lane),
			LanePosition: int(t.LanePosition), Side: t.Side,
		})
	}
	return world, nil
}

// Marks are the user's items among the titles of these Worlds, by title key. An anime season
// AniList lists on its own is marked with the TMDB show Aaru keeps it in, as in the graph.
func (s *WorldService) Marks(ctx context.Context, userID uuid.UUID, worlds ...World) (map[string]RelationMark, error) {
	var nodes []GraphNode
	for _, w := range worlds {
		for _, t := range w.Titles {
			nodes = append(nodes, GraphNode{RelatedNode: t.RelatedNode, Key: t.Key})
		}
	}
	return s.Relations.marksFor(ctx, userID, nodes)
}

// WorldProgress is where one user stands in a World.
type WorldProgress struct {
	// Total is every title on the map, side titles too (owner, 2026-11-17); Finished those the
	// user finished.
	Total, Finished int
	// Next is, per lane, the key of its first title the user has not finished or dropped, side
	// titles aside: the lane's "next".
	Next map[WorldLane]string
	// StartHere is the one title to go to: one in progress, else the next of the lane the user is
	// furthest into, else the first lane's. Nil when nothing is left.
	StartHere *string
}

// Progress reads the user's place from their status by title key.
func (w World) Progress(status map[string]core.LibraryStatus) WorldProgress {
	progress := WorldProgress{Total: len(w.Titles), Next: map[WorldLane]string{}}
	finished := map[WorldLane]int{}
	var lanes []WorldLane
	var inProgress *string
	for _, t := range w.Titles {
		if !slices.Contains(lanes, t.Lane) {
			lanes = append(lanes, t.Lane)
		}
		st := status[t.Key]
		if st == core.StatusFinished {
			progress.Finished++
			finished[t.Lane]++
		}
		if st == core.StatusInProgress && inProgress == nil {
			key := t.Key
			inProgress = &key
		}
		if t.Side || st == core.StatusFinished || st == core.StatusDropped {
			continue
		}
		if _, has := progress.Next[t.Lane]; !has {
			progress.Next[t.Lane] = t.Key
		}
	}
	if inProgress != nil {
		progress.StartHere = inProgress
		return progress
	}
	// The lane the user finished most of, among those with something left; the first lane on a tie.
	open := slices.DeleteFunc(slices.Clone(lanes), func(l WorldLane) bool { return progress.Next[l] == "" })
	if len(open) == 0 {
		return progress
	}
	best := slices.MaxFunc(open, func(a, b WorldLane) int {
		return cmp.Or(cmp.Compare(finished[a], finished[b]), cmp.Compare(slices.Index(lanes, b), slices.Index(lanes, a)))
	})
	key := progress.Next[best]
	progress.StartHere = &key
	return progress
}

// Kinds are the World's lanes in the order they are drawn.
func (w World) Kinds() []WorldLane {
	var lanes []WorldLane
	for _, t := range w.Titles {
		if !slices.Contains(lanes, t.Lane) {
			lanes = append(lanes, t.Lane)
		}
	}
	return lanes
}
