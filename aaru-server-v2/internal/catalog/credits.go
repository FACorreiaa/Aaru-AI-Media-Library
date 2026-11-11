package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// Credit is who a title tree branches on (GRAPH-005): a film's director, a show's creator, an
// anime's studio, a book's or manga's author, an album's artist. ID is the provider's own id for
// them; a person is never matched by name.
type Credit struct {
	Kind core.TreeBranchKind `json:"kind"`
	ID   string              `json:"id"`
	Name string              `json:"name"`
}

// CreditedWork is one title a credited person made. Score is the provider's own count for it
// (TMDB votes, AniList popularity, Open Library reading logs), the same for every user; 0 when
// the provider has none.
type CreditedWork struct {
	RelatedNode
	Score int `json:"score,omitempty"`
}

// CreditSource is one provider of credits: TMDB, AniList, Open Library, MusicBrainz.
type CreditSource interface {
	// CreditSourceName names the source in the cache.
	CreditSourceName() string
	// CreditKey is the title's cache key at this source; "" when the source cannot answer for it.
	CreditKey(n RelatedNode) string
	// People are who made the title, the one a tree branches on first. Empty when unknown.
	People(ctx context.Context, n RelatedNode) ([]Credit, error)
	// Works are the titles the credited person made, the asked title among them.
	Works(ctx context.Context, credit Credit) ([]CreditedWork, error)
}

// Credits are cached like relations: a month, and a day for "nothing found".
const (
	CreditsTTL      = RelationsTTL
	CreditsEmptyTTL = RelationsEmptyTTL
)

// creditCache keeps credit answers in `catalog_credits`.
type creditCache struct {
	q   *sqlc.Queries
	now func() time.Time
	log *slog.Logger
}

// cachedCredits is fetch's answer for source and key, from the cache while it is fresh. A failed
// fetch serves the old answer when there is one.
func cachedCredits[T any](ctx context.Context, c creditCache, source, key string, fetch func(context.Context) ([]T, error)) ([]T, error) {
	var stale []T
	hasStale := false
	row, err := c.q.CatalogCredits(ctx, sqlc.CatalogCreditsParams{Source: source, Key: key})
	switch {
	case err == nil:
		var cached []T
		if json.Unmarshal(row.Payload, &cached) == nil {
			ttl := CreditsTTL
			if len(cached) == 0 {
				ttl = CreditsEmptyTTL
			}
			if c.now().Sub(row.FetchedAt.Time) < ttl {
				return cached, nil
			}
			stale, hasStale = cached, true
		}
	case !db.IsNoRows(err):
		c.log.Warn("Credit cache read failed", "source", source, "key", key, "error", err.Error())
	}
	fresh, err := fetch(ctx)
	if err != nil {
		if hasStale {
			return stale, nil
		}
		return nil, fmt.Errorf("%s credits: %w", source, err)
	}
	if fresh == nil {
		fresh = []T{}
	}
	payload, err := json.Marshal(fresh)
	if err != nil {
		return fresh, nil //nolint:nilerr // an answer that cannot be cached is still the answer
	}
	// Written past the caller: a closed page must not throw away an answer already paid for.
	err = c.q.PutCatalogCredits(context.WithoutCancel(ctx), sqlc.PutCatalogCreditsParams{
		Source: source, Key: key, Payload: payload,
		FetchedAt: pgtype.Timestamptz{Time: c.now(), Valid: true},
	})
	if err != nil {
		c.log.Warn("Credit cache write failed", "source", source, "key", key, "error", err.Error())
	}
	return fresh, nil
}
