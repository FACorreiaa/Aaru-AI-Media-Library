package imports

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"fmt"
	"slices"

	"github.com/google/uuid"
	"golang.org/x/sync/errgroup"
)

// Rows that land on one title (ImportRowMerge). AniList and MAL list each anime season as its own
// entry, all ticked as season 1; when the community mapping sends an entry to a later TMDB season,
// its ticks move there, and every entry of the show merges into one row.

type titleGroup struct {
	titleID uuid.UUID
	indices []int
}

// groups are matched rows by title, in the order each title first appears.
func groups(rows []PlannedRow) []titleGroup {
	var order []uuid.UUID
	indices := map[uuid.UUID][]int{}
	for i, r := range rows {
		if r.Outcome == OutcomeUnmatched || r.TitleID == nil {
			continue
		}
		if _, ok := indices[*r.TitleID]; !ok {
			order = append(order, *r.TitleID)
		}
		indices[*r.TitleID] = append(indices[*r.TitleID], i)
	}
	out := make([]titleGroup, len(order))
	for i, id := range order {
		out[i] = titleGroup{titleID: id, indices: indices[id]}
	}
	return out
}

// mergeContext is what merging and deciding a plan's titles read, loaded once for the whole plan:
// the user's items for those titles, the anime mappings of rows with ticks, and the TMDB id of each
// title.
type mergeContext struct {
	states    map[uuid.UUID]library.ImportItemState
	byAniList map[string]catalog.AnimeMapping
	byMAL     map[string]catalog.AnimeMapping
	tmdb      map[uuid.UUID]string
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, v := range values {
		if v != "" && !seen[v] {
			seen[v] = true
			out = append(out, v)
		}
	}
	return out
}

func uniqueIDs(values []uuid.UUID) []uuid.UUID {
	seen := map[uuid.UUID]bool{}
	var out []uuid.UUID
	for _, v := range values {
		if !seen[v] {
			seen[v] = true
			out = append(out, v)
		}
	}
	return out
}

func (s *Service) mergeContext(ctx context.Context, rows []PlannedRow, user uuid.UUID) (mergeContext, error) {
	var titleIDs, animeTitles []uuid.UUID
	var anilist, mal []string
	for _, r := range rows {
		if r.Outcome == OutcomeUnmatched || r.TitleID == nil {
			continue
		}
		titleIDs = append(titleIDs, *r.TitleID)
		if len(r.Row.Watched) > 0 {
			anilist = append(anilist, r.Row.IDs.AniList)
			mal = append(mal, r.Row.IDs.MAL)
			animeTitles = append(animeTitles, *r.TitleID)
		}
	}
	mc := mergeContext{byAniList: map[string]catalog.AnimeMapping{}, tmdb: map[uuid.UUID]string{}}
	store := s.Catalog.Store
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		var err error
		mc.states, err = s.Library.ImportStates(gctx, user, uniqueIDs(titleIDs))
		return err
	})
	var byAniList []catalog.AnimeMapping
	g.Go(func() error {
		ids := uniqueStrings(anilist)
		if len(ids) == 0 {
			return nil
		}
		var err error
		byAniList, err = store.MappingsByAniList(gctx, ids)
		return err
	})
	g.Go(func() error {
		ids := uniqueStrings(mal)
		if len(ids) == 0 {
			mc.byMAL = map[string]catalog.AnimeMapping{}
			return nil
		}
		var err error
		mc.byMAL, err = store.MappingsByMAL(gctx, ids)
		return err
	})
	var titles []core.Title
	g.Go(func() error {
		ids := uniqueIDs(animeTitles)
		if len(ids) == 0 {
			return nil
		}
		var err error
		titles, err = store.Titles(gctx, ids)
		return err
	})
	if err := g.Wait(); err != nil {
		return mergeContext{}, fmt.Errorf("merge context: %w", err)
	}
	for _, m := range byAniList {
		if _, ok := mc.byAniList[m.AniList]; !ok {
			mc.byAniList[m.AniList] = m
		}
	}
	for _, t := range titles {
		if _, ok := mc.tmdb[t.ID]; !ok && t.IDs.TMDB != "" {
			mc.tmdb[t.ID] = t.IDs.TMDB
		}
	}
	if mc.byMAL == nil {
		mc.byMAL = map[string]catalog.AnimeMapping{}
	}
	return mc, nil
}

// seasonRows are each row with its ticks in the TMDB season its anime mapping names.
func seasonRows(rows []PlannedRow, mc mergeContext) []Row {
	out := make([]Row, len(rows))
	for i, planned := range rows {
		row := planned.Row
		if len(row.Watched) > 0 && planned.TitleID != nil {
			if season, ok := mappedSeason(row.IDs, *planned.TitleID, mc); ok {
				moved := make([]core.EpisodeKey, 0, len(row.Watched))
				for _, k := range row.Watched {
					if k.Season == 1 {
						if nk, err := core.NewEpisodeKey(season, k.Episode); err == nil {
							moved = append(moved, nk)
						}
						continue
					}
					moved = append(moved, k)
				}
				row.Watched = moved
			}
		}
		out[i] = row
	}
	return out
}

// mappedSeason is the TMDB season an anime entry maps to, when its title is that TMDB show. The
// AniList id's mapping wins; the MAL id's is the fallback.
func mappedSeason(ids core.ExternalIDs, titleID uuid.UUID, mc mergeContext) (int, bool) {
	var mapping *catalog.AnimeMapping
	if ids.AniList != "" {
		if m, ok := mc.byAniList[ids.AniList]; ok {
			mapping = &m
		}
	}
	if mapping == nil && ids.MAL != "" {
		if m, ok := mc.byMAL[ids.MAL]; ok {
			mapping = &m
		}
	}
	if mapping == nil || mapping.TMDBSeason == nil || *mapping.TMDBSeason == 1 || mapping.TMDB == nil ||
		mc.tmdb[titleID] != *mapping.TMDB {
		return 0, false
	}
	return *mapping.TMDBSeason, true
}

// Merged is one row for a title: every tick, the furthest status, the first rating, the latest
// finish.
func Merged(rows []Row) Row {
	merged := rows[0]
	merged.Watched = cloneKeys(merged.Watched)
	for _, row := range rows[1:] {
		if (merged.Status == nil || *merged.Status != core.StatusDropped) && row.Status != nil {
			current := -1
			if merged.Status != nil {
				current = ImportRank(*merged.Status)
			}
			if ImportRank(*row.Status) > current {
				merged.Status = row.Status
			}
		}
		if merged.Rating == nil {
			merged.Rating = row.Rating
		}
		if merged.Notes == nil {
			merged.Notes = row.Notes
		}
		if isTrue(row.IsOwned) {
			merged.IsOwned = ptr(true)
		}
		if row.FinishedAt != nil && (merged.FinishedAt == nil || row.FinishedAt.After(*merged.FinishedAt)) {
			merged.FinishedAt = row.FinishedAt
		}
		if row.Watched != nil {
			set := map[core.EpisodeKey]bool{}
			for _, k := range merged.Watched {
				set[k] = true
			}
			for _, k := range row.Watched {
				set[k] = true
			}
			merged.Watched = library.SortedKeys(set)
		}
		merged.MangaChapter = maxPtr(merged.MangaChapter, row.MangaChapter)
		merged.MangaVolume = maxPtr(merged.MangaVolume, row.MangaVolume)
		if !isTrue(row.ListOnly) {
			merged.ListOnly = nil
		}
	}
	return merged
}

func cloneKeys(keys []core.EpisodeKey) []core.EpisodeKey {
	if keys == nil {
		return nil
	}
	return slices.Clone(keys)
}

func maxPtr(a, b *int) *int {
	switch {
	case a == nil:
		return b
	case b == nil:
		return a
	case *b > *a:
		return b
	}
	return a
}
