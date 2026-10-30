package sports

import (
	"aaru-go-api/internal/db/sqlc"
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is PostgresSportsStore.swift: follows and the "Where to watch" country.
type Store struct {
	Q    *sqlc.Queries
	Pool *pgxpool.Pool
}

// Follows is the user's follows, oldest first.
func (s *Store) Follows(ctx context.Context, userID uuid.UUID) ([]Follow, error) {
	rows, err := s.Q.SportFollows(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("sport follows: %w", err)
	}
	out := make([]Follow, 0, len(rows))
	for _, r := range rows {
		kind := EntityKind(r.Kind)
		if !kind.Valid() {
			continue
		}
		out = append(out, Follow{
			Entity: Entity{
				Kind: kind, ID: r.ProviderID, Name: r.Name, Sport: r.Sport, BadgeURL: r.BadgeUrl, Country: r.Country,
				LeagueID: r.LeagueID, TeamID: r.TeamID, TeamName: r.TeamName,
			},
			CreatedAt: r.CreatedAt,
		})
	}
	return out, nil
}

func prefixPtr(s *string, n int) *string {
	if s == nil {
		return nil
	}
	v := prefixRunes(*s, n)
	return &v
}

// Follow saves or refreshes a follow. False when the user is at limit and this one is new.
func (s *Store) Follow(ctx context.Context, entity Entity, userID uuid.UUID, limit int, now time.Time) (bool, error) {
	saved := false
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		// One writer per user at a time, so two follows racing at the limit cannot both pass.
		if err := q.LockUserForSportFollow(ctx, userID); err != nil {
			return err
		}
		counts, err := q.SportFollowCounts(ctx, sqlc.SportFollowCountsParams{Kind: string(entity.Kind), ProviderID: entity.ID, UserID: userID})
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		if counts.Existing == 0 && int(counts.Count) >= limit {
			return nil
		}
		if err := q.UpsertSportFollow(ctx, sqlc.UpsertSportFollowParams{
			UserID: userID, Kind: string(entity.Kind), ProviderID: entity.ID,
			Name: prefixRunes(entity.Name, 300), Sport: prefixRunes(entity.Sport, 100), BadgeUrl: entity.BadgeURL,
			Country: prefixPtr(entity.Country, 200), LeagueID: entity.LeagueID, TeamID: entity.TeamID,
			TeamName: prefixPtr(entity.TeamName, 300), CreatedAt: now,
		}); err != nil {
			return err
		}
		saved = true
		return nil
	})
	if err != nil {
		return false, fmt.Errorf("sport follow: %w", err)
	}
	return saved, nil
}

// Unfollow forgets a follow; unknown ones are fine.
func (s *Store) Unfollow(ctx context.Context, kind EntityKind, id string, userID uuid.UUID) error {
	if err := s.Q.DeleteSportFollow(ctx, sqlc.DeleteSportFollowParams{UserID: userID, Kind: string(kind), ProviderID: id}); err != nil {
		return fmt.Errorf("sport unfollow: %w", err)
	}
	return nil
}

// WatchCountry is ISO 3166-1 alpha-2, uppercase; nil when never chosen.
func (s *Store) WatchCountry(ctx context.Context, userID uuid.UUID) (*string, error) {
	code, err := s.Q.SportWatchCountry(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("sport watch country: %w", err)
	}
	return code, nil
}

// SaveWatchCountry saves or clears the "Where to watch" country.
func (s *Store) SaveWatchCountry(ctx context.Context, code *string, userID uuid.UUID, now time.Time) error {
	if err := s.Q.SaveSportWatchCountry(ctx, sqlc.SaveSportWatchCountryParams{UserID: userID, WatchCountryCode: code, UpdatedAt: now}); err != nil {
		return fmt.Errorf("save sport watch country: %w", err)
	}
	return nil
}
