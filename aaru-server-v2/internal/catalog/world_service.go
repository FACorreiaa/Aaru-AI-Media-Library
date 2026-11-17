package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/safe"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

// Building Worlds (GRAPH-007). A World costs many provider calls, so no request builds one: a
// title is queued in `world_builds`, one worker leases it, walks the graph at the providers' own
// pace, and stores the World. Reads are from the database only.

// The queue's priorities: a title someone is looking at goes before an import's backlog.
const (
	WorldPriorityImport int32 = 0
	WorldPriorityOpened int32 = 10
)

const (
	// WorldBuildDeadline bounds one build's walk.
	WorldBuildDeadline = 3 * time.Minute
	// WorldBuildLease is how long a build is held; past it another worker may take it over.
	WorldBuildLease = 5 * time.Minute
	// WorldBuildAttempts is how often a build is tried before it ends as failed.
	WorldBuildAttempts = 5
	// WorldRecheck is how long "this title has no World" (or a World as it was built) is
	// believed before a read asks again: as long as the relation cache keeps an answer.
	WorldRecheck = RelationsTTL
	// worldRetryBase and worldRetryMax pace a build whose sources failed: 5 minutes, doubling.
	worldRetryBase = 5 * time.Minute
	worldRetryMax  = 6 * time.Hour
)

// worldRetryAfter is how long a build that failed on its nth attempt waits.
func worldRetryAfter(attempts int32) time.Duration {
	wait := worldRetryBase
	for i := int32(1); i < attempts && wait < worldRetryMax; i++ {
		wait *= 2
	}
	return min(wait, worldRetryMax)
}

// WorldService queues, builds and stores Worlds.
type WorldService struct {
	Relations *RelationService
	Store     *Store
	Log       *slog.Logger
	Now       func() time.Time
}

// NewWorldService builds the service over the relation service's cached sources.
func NewWorldService(relations *RelationService, store *Store, log *slog.Logger) *WorldService {
	if log == nil {
		log = slog.Default()
	}
	return &WorldService{Relations: relations, Store: store, Log: log, Now: time.Now}
}

// Enqueue asks for the title's World to be built. A title looked at within WorldRecheck is left
// as it is; one already queued only gains priority. It never fails the caller: the World is an
// extra, and a title that could not be queued is queued by the next read.
func (s *WorldService) Enqueue(ctx context.Context, titleID uuid.UUID, priority int32) {
	if s == nil || titleID == uuid.Nil {
		return
	}
	now := s.Now()
	err := s.Store.q.EnqueueWorldBuild(context.WithoutCancel(ctx), sqlc.EnqueueWorldBuildParams{
		TitleID: titleID, Priority: priority, Now: now,
		StaleBefore: pgtype.Timestamptz{Time: now.Add(-WorldRecheck), Valid: true},
	})
	if err != nil {
		s.Log.Warn("World build could not be queued", "title", titleID.String(), "error", err.Error())
	}
}

// EnqueueLibrary queues every title of the user's library that was never looked at, behind the
// titles people open: after an import. It returns how many were queued.
func (s *WorldService) EnqueueLibrary(ctx context.Context, userID uuid.UUID) (int64, error) {
	if s == nil {
		return 0, nil
	}
	queued, err := s.Store.q.EnqueueWorldBuildsForUser(ctx, sqlc.EnqueueWorldBuildsForUserParams{
		Priority: WorldPriorityImport, Now: pgtype.Timestamptz{Time: s.Now(), Valid: true}, UserID: userID,
	})
	if err != nil {
		return 0, fmt.Errorf("queue world builds: %w", err)
	}
	return queued, nil
}

// BuildNext leases the next queued title and builds its World. worked is false when the queue
// is empty.
func (s *WorldService) BuildNext(ctx context.Context) (worked bool, err error) {
	now := s.Now()
	if _, err := s.Store.q.WorldBuildFailExpired(ctx, sqlc.WorldBuildFailExpiredParams{Now: &now, MaxAttempts: WorldBuildAttempts}); err != nil {
		return false, fmt.Errorf("fail expired world builds: %w", err)
	}
	lease := now.Add(WorldBuildLease)
	claim, err := s.Store.q.WorldBuildClaim(ctx, sqlc.WorldBuildClaimParams{LeasedUntil: &lease, Now: now, MaxAttempts: WorldBuildAttempts})
	if db.IsNoRows(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("claim world build: %w", err)
	}
	// Settled past the caller: a shutdown mid-build must not leave the title leased for nothing.
	settle := context.WithoutCancel(ctx)
	complete, err := s.build(ctx, claim.TitleID)
	finished := s.Now()
	if err == nil && complete {
		if err := s.Store.q.WorldBuildDone(settle, sqlc.WorldBuildDoneParams{TitleID: claim.TitleID, Now: &finished}); err != nil {
			return true, fmt.Errorf("finish world build: %w", err)
		}
		return true, nil
	}
	// A failed or partial build waits and is tried again; out of attempts it ends as failed.
	retryErr := s.Store.q.WorldBuildRetry(settle, sqlc.WorldBuildRetryParams{
		TitleID: claim.TitleID, MaxAttempts: WorldBuildAttempts,
		RunAfter: finished.Add(worldRetryAfter(claim.Attempts)), Now: &finished,
	})
	if retryErr != nil {
		return true, errors.Join(err, fmt.Errorf("requeue world build: %w", retryErr))
	}
	return true, err
}

// build walks and stores the World the title belongs to. complete is false when a source failed,
// so the title is tried again later; what was found is stored meanwhile unless a complete World
// is already there.
func (s *WorldService) build(ctx context.Context, titleID uuid.UUID) (complete bool, err error) {
	anchor, err := s.Relations.centre(ctx, titleID)
	if err != nil {
		var appErr *apperr.Error
		if errors.As(err, &appErr) && appErr.Status == 404 {
			return true, nil // the title is gone: nothing to build
		}
		return false, err
	}
	walk, cancel := context.WithTimeout(ctx, WorldBuildDeadline)
	world, found := BuildWorld(walk, anchor, s.Relations.Sources, s.knownRoots)
	cancel()
	if err := ctx.Err(); err != nil {
		return false, err
	}
	if !found {
		return !world.Partial, nil
	}
	if err := s.put(ctx, world); err != nil {
		return false, err
	}
	return !world.Partial, nil
}

// knownRoots is the first titles of the Worlds already stored around these ids.
func (s *WorldService) knownRoots(ctx context.Context, keys []string) []RelatedNode {
	worlds, err := s.Store.q.WorldByKeys(ctx, keys)
	if err != nil {
		s.Log.Warn("Stored Worlds could not be read", "error", err.Error())
		return nil
	}
	var roots []RelatedNode
	for _, w := range worlds {
		raw, err := s.Store.q.WorldTitleByKey(ctx, sqlc.WorldTitleByKeyParams{WorldID: w.ID, NodeKey: w.RootKey})
		if err != nil {
			continue
		}
		var root RelatedNode
		if json.Unmarshal(raw, &root) == nil {
			roots = append(roots, root)
		}
	}
	return roots
}

// put stores the World, replacing the one its titles were in. Two stored Worlds that turn out to
// be one are merged into the older, so a World keeps its id. A partial build never replaces a
// complete one.
func (s *WorldService) put(ctx context.Context, world World) error {
	keys, positions, err := s.worldKeys(ctx, world)
	if err != nil {
		return err
	}
	links, err := json.Marshal(world.Links)
	if err != nil {
		return fmt.Errorf("encode world links: %w", err)
	}
	titles := sqlc.PutWorldTitlesParams{}
	for position, t := range world.Titles {
		node, err := json.Marshal(t.RelatedNode)
		if err != nil {
			return fmt.Errorf("encode world title: %w", err)
		}
		titles.Positions = append(titles.Positions, int32(position))
		titles.NodeKeys = append(titles.NodeKeys, t.Key)
		titles.Lanes = append(titles.Lanes, string(t.Lane))
		titles.LanePositions = append(titles.LanePositions, int32(t.LanePosition)) //nolint:gosec // bounded by WorldMaxTitles
		titles.Sides = append(titles.Sides, t.Side)
		titles.Nodes = append(titles.Nodes, node)
	}
	now := s.Now()
	return pgx.BeginFunc(ctx, s.Store.pool, func(tx pgx.Tx) error {
		q := sqlc.New(tx)
		existing, err := q.WorldByKeys(ctx, keys)
		if err != nil {
			return fmt.Errorf("stored worlds: %w", err)
		}
		if world.Partial && slices.ContainsFunc(existing, func(w sqlc.World) bool { return !w.Partial }) {
			return nil
		}
		id := uuid.New()
		var merged []uuid.UUID
		if len(existing) > 0 {
			id = existing[0].ID
			for _, w := range existing[1:] {
				merged = append(merged, w.ID)
			}
		}
		if err := q.DeleteWorlds(ctx, sqlc.DeleteWorldsParams{Ids: merged, RootKey: world.RootKey, Keep: id}); err != nil {
			return fmt.Errorf("merge worlds: %w", err)
		}
		err = q.PutWorld(ctx, sqlc.PutWorldParams{
			ID: id, RootKey: world.RootKey, Name: world.Name, Links: links, Truncated: world.Truncated,
			Partial: world.Partial, TitleCount: int32(len(world.Titles)), BuiltAt: now, //nolint:gosec // bounded by WorldMaxTitles
		})
		if err != nil {
			return fmt.Errorf("put world: %w", err)
		}
		if err := q.ClearWorldMembers(ctx, id); err != nil {
			return fmt.Errorf("clear world titles: %w", err)
		}
		if err := q.ClearWorldKeys(ctx, sqlc.ClearWorldKeysParams{WorldID: id, NodeKeys: keys}); err != nil {
			return fmt.Errorf("clear world keys: %w", err)
		}
		titles.WorldID = id
		if err := q.PutWorldTitles(ctx, titles); err != nil {
			return fmt.Errorf("put world titles: %w", err)
		}
		if err := q.PutWorldKeys(ctx, sqlc.PutWorldKeysParams{NodeKeys: keys, WorldID: id, Positions: positions}); err != nil {
			return fmt.Errorf("put world keys: %w", err)
		}
		return nil
	})
}

// worldKeys is every id that finds the World, each once, with the place of the title it names. An
// anime season AniList lists on its own is also found by the TMDB show Aaru keeps it in.
func (s *WorldService) worldKeys(ctx context.Context, world World) (keys []string, positions []int32, err error) {
	var anilist []string
	for _, t := range world.Titles {
		if t.IDs.AniList != "" {
			anilist = append(anilist, t.IDs.AniList)
		}
	}
	mappings, err := s.Store.MappingsByAniList(ctx, anilist)
	if err != nil {
		return nil, nil, err
	}
	showOf := map[string]string{}
	for _, m := range mappings {
		if m.TMDB != nil && *m.TMDB != "" {
			showOf[m.AniList] = *m.TMDB
		}
	}
	seen := map[string]bool{}
	add := func(key string, position int) {
		if !seen[key] {
			seen[key] = true
			keys, positions = append(keys, key), append(positions, int32(position)) //nolint:gosec // bounded by WorldMaxTitles
		}
	}
	// Each title's own ids first, so a show that is itself in the World keeps its own place.
	for position, t := range world.Titles {
		for _, k := range t.Keys {
			add(k, position)
		}
	}
	for position, t := range world.Titles {
		if show := showOf[t.IDs.AniList]; show != "" {
			add("tmdb:show:"+show, position)
		}
	}
	return keys, positions, nil
}

// WorldWorker builds queued Worlds, one at a time: the providers' pacers are shared with every
// page, and a World is never urgent.
type WorldWorker struct {
	Worlds *WorldService
	Log    *slog.Logger
	// Idle is how long the worker sleeps when the queue is empty (5 s).
	Idle time.Duration
}

// Name names the worker in logs.
func (w *WorldWorker) Name() string { return "worlds" }

// Run builds until ctx is cancelled.
func (w *WorldWorker) Run(ctx context.Context) error {
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	idle := w.Idle
	if idle <= 0 {
		idle = 5 * time.Second
	}
	for ctx.Err() == nil {
		worked, err := safe.Value(func() (bool, error) { return w.Worlds.BuildNext(ctx) })
		if ctx.Err() != nil {
			return nil
		}
		metrics.WorkerPass(w.Name(), err)
		if err != nil {
			log.Error("World build failed", "error", err.Error())
		} else if worked {
			continue
		}
		timer := time.NewTimer(idle)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-timer.C:
		}
	}
	return nil
}
