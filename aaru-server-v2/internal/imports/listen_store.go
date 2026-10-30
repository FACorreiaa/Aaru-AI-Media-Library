package imports

// MUS-004 · listening history imports in the database (PostgresListenStore+Imports.swift): a job's
// plays are staged, counted against the log with the live duplicate window, written as the job's
// `import` listens, and deleted with it on undo.

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ListenLog is what listening imports need of the listening log (ListenStore's MUS-004 part).
type ListenLog interface {
	// Stage adds plays to a job's staging, numbered from index.
	Stage(ctx context.Context, listens []NewListen, jobID uuid.UUID, index int) error
	// ClearStaged empties a job's staging, so a retried fetch starts over.
	ClearStaged(ctx context.Context, jobID uuid.UUID) error
	// CountNew is how many staged plays applying would keep: those outside every stored listen's
	// duplicate window and outside the window of the play before them of the same track.
	CountNew(ctx context.Context, jobID, user uuid.UUID) (int, error)
	// ApplyStaged writes the plays CountNew counts as the job's `import` listens, then empties its
	// staging. It returns how many were written.
	ApplyStaged(ctx context.Context, jobID, user uuid.UUID) (int, error)
	// DeleteImported deletes the listens a job wrote and returns how many.
	DeleteImported(ctx context.Context, jobID, user uuid.UUID) (int, error)
	// NewestImported is the newest listen an applied import of this source and account wrote, so
	// the next import of it reads only what came after.
	NewestImported(ctx context.Context, user uuid.UUID, source core.ImportSource, account string) (*time.Time, error)
}

// ListenStore is the ListenLog over Postgres.
type ListenStore struct {
	Pool *pgxpool.Pool
	Q    *sqlc.Queries
}

// NewListenStore builds the store over the pool.
func NewListenStore(pool *pgxpool.Pool) *ListenStore {
	return &ListenStore{Pool: pool, Q: sqlc.New(pool)}
}

var _ ListenLog = (*ListenStore)(nil)

func int32Ptr(v *int) *int32 {
	if v == nil {
		return nil
	}
	n := int32(*v) //nolint:gosec // a play's length in ms, checked < 1 day or from a file
	return &n
}

// Stage copies the plays into staging (Swift sent 1,000-row INSERTs; COPY is one round trip).
func (s *ListenStore) Stage(ctx context.Context, listens []NewListen, jobID uuid.UUID, index int) error {
	if len(listens) == 0 {
		return nil
	}
	rows := make([]sqlc.ImportListensStageParams, len(listens))
	for i, l := range listens {
		rows[i] = sqlc.ImportListensStageParams{
			JobID: jobID, Idx: int32(index + i), ListenedAt: l.ListenedAt, //nolint:gosec // a row index
			Artist: l.Artist, Track: l.Track, Album: l.Album, TrackKey: l.TrackKey(),
			DurationMs: int32Ptr(l.DurationMs), Isrc: l.ISRC, RecordingMbid: l.RecordingMBID,
			ReleaseMbid: l.ReleaseMBID, ReleaseGroupMbid: l.ReleaseGroupMBID, ArtistMbid: l.ArtistMBID,
			SpotifyID: l.SpotifyID, OriginUrl: l.OriginURL, Client: l.Client, MusicService: l.MusicService,
		}
	}
	if _, err := s.Q.ImportListensStage(ctx, rows); err != nil {
		return fmt.Errorf("stage listens: %w", err)
	}
	return nil
}

func (s *ListenStore) ClearStaged(ctx context.Context, jobID uuid.UUID) error {
	if err := s.Q.ImportListensClear(ctx, jobID); err != nil {
		return fmt.Errorf("clear staged listens: %w", err)
	}
	return nil
}

func (s *ListenStore) CountNew(ctx context.Context, jobID, user uuid.UUID) (int, error) {
	n, err := s.Q.ImportListensCountNew(ctx, sqlc.ImportListensCountNewParams{JobID: jobID, UserID: user})
	if err != nil {
		return 0, fmt.Errorf("count new listens: %w", err)
	}
	return int(n), nil
}

func (s *ListenStore) ApplyStaged(ctx context.Context, jobID, user uuid.UUID) (int, error) {
	var written int32
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		// The same per-user lock as a scrobbler's insert, so a live listen arriving now is
		// compared with these, or these with it.
		if err := q.ImportListensLock(ctx, strings.ToUpper(user.String())); err != nil {
			return fmt.Errorf("lock listens: %w", err)
		}
		var err error
		if written, err = q.ImportListensApply(ctx, sqlc.ImportListensApplyParams{JobID: jobID, UserID: user}); err != nil {
			return fmt.Errorf("apply staged listens: %w", err)
		}
		return q.ImportListensClear(ctx, jobID)
	})
	if err != nil {
		return 0, fmt.Errorf("apply listen import: %w", err)
	}
	return int(written), nil
}

func (s *ListenStore) DeleteImported(ctx context.Context, jobID, user uuid.UUID) (int, error) {
	n, err := s.Q.ImportListensDeleteImported(ctx, sqlc.ImportListensDeleteImportedParams{UserID: user, JobID: &jobID})
	if err != nil {
		return 0, fmt.Errorf("delete imported listens: %w", err)
	}
	return int(n), nil
}

func (s *ListenStore) NewestImported(ctx context.Context, user uuid.UUID, source core.ImportSource, account string) (*time.Time, error) {
	t, err := s.Q.ImportListensNewestImported(ctx, sqlc.ImportListensNewestImportedParams{
		UserID: user, Source: string(source), Account: account,
	})
	if db.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("newest imported listen: %w", err)
	}
	t = t.UTC()
	return &t, nil
}
