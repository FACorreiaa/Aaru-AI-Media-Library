package concerts

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

// Store is PostgresConcertStore.swift: the saved city, album artists and their matches.
type Store struct {
	Q    *sqlc.Queries
	Pool *pgxpool.Pool
}

// Place is the user's saved "Concerts near" city; nil when none is saved.
func (s *Store) Place(ctx context.Context, userID uuid.UUID) (*Place, error) {
	row, err := s.Q.ConcertPlace(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	if err != nil {
		return nil, fmt.Errorf("concert place: %w", err)
	}
	point, ok := NewGeoPoint(row.Latitude, row.Longitude)
	if !ok {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	return &Place{Name: row.Name, Region: row.Region, Country: row.Country, CountryCode: row.CountryCode, Point: point}, nil
}

// SavePlace saves or replaces the user's city.
func (s *Store) SavePlace(ctx context.Context, place Place, userID uuid.UUID, now time.Time) error {
	if err := s.Q.SaveConcertPlace(ctx, sqlc.SaveConcertPlaceParams{
		UserID: userID, Name: place.Name, Region: place.Region, Country: place.Country, CountryCode: place.CountryCode,
		Latitude: place.Point.Latitude, Longitude: place.Point.Longitude, UpdatedAt: now,
	}); err != nil {
		return fmt.Errorf("save concert place: %w", err)
	}
	return nil
}

// DeletePlace forgets the user's city.
func (s *Store) DeletePlace(ctx context.Context, userID uuid.UUID) error {
	if err := s.Q.DeleteConcertPlace(ctx, userID); err != nil {
		return fmt.Errorf("delete concert place: %w", err)
	}
	return nil
}

// AlbumsMissingArtists is albums in someone's library whose artists have not been looked up.
func (s *Store) AlbumsMissingArtists(ctx context.Context, limit int) ([]AlbumArtistsDue, error) {
	rows, err := s.Q.AlbumsMissingArtists(ctx, int32(min(limit, 1<<31-1))) //nolint:gosec // clamped
	if err != nil {
		return nil, fmt.Errorf("albums missing artists: %w", err)
	}
	out := make([]AlbumArtistsDue, 0, len(rows))
	for _, r := range rows {
		out = append(out, AlbumArtistsDue{TitleID: r.ID, MusicBrainzID: r.Musicbrainz})
	}
	return out, nil
}

// SaveAlbumArtists saves the album's artists and stamps it as looked up, even when the list is empty.
func (s *Store) SaveAlbumArtists(ctx context.Context, artists []MusicArtist, titleID uuid.UUID, now time.Time) error {
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		for position, artist := range artists {
			if err := q.UpsertMusicArtist(ctx, sqlc.UpsertMusicArtistParams{Musicbrainz: artist.MusicBrainzID, Name: artist.Name}); err != nil {
				return err
			}
			if err := q.UpsertAlbumArtist(ctx, sqlc.UpsertAlbumArtistParams{
				TitleID: titleID, Artist: artist.MusicBrainzID, Position: int32(position), //nolint:gosec // a tracklist's credits
			}); err != nil {
				return err
			}
		}
		return q.MarkAlbumArtistsChecked(ctx, sqlc.MarkAlbumArtistsCheckedParams{ID: titleID, ArtistsCheckedAt: &now})
	})
	if err != nil {
		return fmt.Errorf("save album artists: %w", err)
	}
	return nil
}

// ArtistsToMatch is artists of albums in someone's library never matched, or matched before checkedBefore.
func (s *Store) ArtistsToMatch(ctx context.Context, checkedBefore time.Time, limit int) ([]MusicArtist, error) {
	rows, err := s.Q.ArtistsToMatch(ctx, sqlc.ArtistsToMatchParams{CheckedBefore: &checkedBefore, RowLimit: int32(min(limit, 1<<31-1))}) //nolint:gosec // clamped
	if err != nil {
		return nil, fmt.Errorf("artists to match: %w", err)
	}
	out := make([]MusicArtist, 0, len(rows))
	for _, r := range rows {
		out = append(out, MusicArtist{MusicBrainzID: r.Musicbrainz, Name: r.Name})
	}
	return out, nil
}

// SaveMatch stamps an artist as asked, with the provider's performer id when it matched.
func (s *Store) SaveMatch(ctx context.Context, musicbrainzID string, performerID *string, now time.Time) error {
	if err := s.Q.SaveArtistMatch(ctx, sqlc.SaveArtistMatchParams{PerformerID: performerID, MatchedAt: &now, Musicbrainz: musicbrainzID}); err != nil {
		return fmt.Errorf("save artist match: %w", err)
	}
	return nil
}

// LibraryArtists is the artists of the user's albums, dropped ones aside, most-shelved first.
func (s *Store) LibraryArtists(ctx context.Context, userID uuid.UUID) ([]LibraryArtist, error) {
	rows, err := s.Q.LibraryArtists(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("library artists: %w", err)
	}
	out := make([]LibraryArtist, 0, len(rows))
	for _, r := range rows {
		out = append(out, LibraryArtist{
			Artist: MusicArtist{MusicBrainzID: r.Musicbrainz, Name: r.Name}, PerformerID: r.PerformerID, Checked: r.MatchedAt != nil,
		})
	}
	return out, nil
}
