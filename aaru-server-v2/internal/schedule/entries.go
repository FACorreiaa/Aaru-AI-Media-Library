package schedule

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The library reads schedule and export need, through the library store (one entry read, one
// DTO mapper: httpapi.LibraryEntryDTO).

// LibraryEntry is a library item with its title and derived progress (library.Entry).
type LibraryEntry = library.Entry

// ProgressSummary is a show's derived progress (library.ProgressSummary).
type ProgressSummary = library.ProgressSummary

// EntryFilter narrows ReadEntries. Zero values mean no filter.
type EntryFilter struct {
	Status *core.LibraryStatus
}

// ReadEntries is the user's library entries, newest change first, at most limit.
func ReadEntries(ctx context.Context, pool *pgxpool.Pool, userID uuid.UUID, filter EntryFilter, limit int, now time.Time) ([]LibraryEntry, error) {
	entries, _, err := library.NewStore(pool).Entries(ctx, userID, library.Filter{Status: filter.Status}, nil, limit, now)
	return entries, err
}

// ReadWatched is every tick of these items, sorted by season then episode (one query, no N+1).
func ReadWatched(ctx context.Context, pool *pgxpool.Pool, itemIDs []uuid.UUID) (map[uuid.UUID][]core.EpisodeKey, error) {
	sets, err := library.NewStore(pool).WatchedOf(ctx, itemIDs)
	if err != nil {
		return nil, err
	}
	out := make(map[uuid.UUID][]core.EpisodeKey, len(sets))
	for id, set := range sets {
		out[id] = library.SortedKeys(set)
	}
	return out, nil
}

func intPtr(v *int32) *int {
	if v == nil {
		return nil
	}
	n := int(*v)
	return &n
}

func str(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}
