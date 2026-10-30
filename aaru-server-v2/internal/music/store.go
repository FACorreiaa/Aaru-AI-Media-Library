package music

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/stats"
	"context"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is PostgresListenStore: the listening log, the lookup cache and import staging.
type Store struct {
	Pool *pgxpool.Pool
	Q    *sqlc.Queries
}

// NewStore builds the store over the pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool, Q: sqlc.New(pool)}
}

func ts(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: true} }

func i32(p *int) *int32 {
	if p == nil {
		return nil
	}
	v := int32(min(max(*p, math.MinInt32), math.MaxInt32)) //nolint:gosec // clamped
	return &v
}

func intPtr(p *int32) *int {
	if p == nil {
		return nil
	}
	v := int(*p)
	return &v
}

// userKey is the lock key Swift used: the id as `uuidString` (upper case), so both servers lock alike.
func userKey(user uuid.UUID) string { return strings.ToUpper(user.String()) }

// Insert stores the listens in order, skipping any inside a stored listen's duplicate window.
// Returns how many were kept.
func (s *Store) Insert(ctx context.Context, listens []NewListen, user uuid.UUID, agentTokenID *uuid.UUID) (int, error) {
	if len(listens) == 0 {
		return 0, nil
	}
	kept := 0
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		// One writer per user at a time, so two scrobblers sending the same play at once
		// cannot both pass the duplicate check.
		if err := q.LockUserListens(ctx, userKey(user)); err != nil {
			return err
		}
		for _, l := range listens {
			_, err := q.InsertListen(ctx, sqlc.InsertListenParams{
				ID: uuid.New(), UserID: user, ListenedAt: ts(l.ListenedAt), Artist: l.Artist, Track: l.Track,
				Album: l.Album, TrackKey: l.TrackKey(), DurationMs: i32(l.DurationMs), Isrc: l.ISRC,
				RecordingMbid: l.RecordingMBID, ReleaseMbid: l.ReleaseMBID, ReleaseGroupMbid: l.ReleaseGroupMBID,
				ArtistMbid: l.ArtistMBID, SpotifyID: l.SpotifyID, OriginUrl: l.OriginURL, Client: l.Client,
				MusicService: l.MusicService, AgentTokenID: agentTokenID,
				WindowSecs: l.DuplicateWindow().Seconds(), VideoID: l.YouTubeVideoID(),
				VideoWindowSecs: l.VideoWindow().Seconds(), VideoPattern: YouTubeVideoPattern,
			})
			if db.IsNoRows(err) {
				continue
			}
			if err != nil {
				return err
			}
			kept++
		}
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("insert listens: %w", err)
	}
	return kept, nil
}

// Listens is newest first, older than before when it is set.
func (s *Store) Listens(ctx context.Context, user uuid.UUID, before *time.Time, limit int64) ([]Listen, error) {
	var b pgtype.Timestamptz
	if before != nil {
		b = ts(*before)
	}
	rows, err := s.Q.ListenPage(ctx, sqlc.ListenPageParams{UserID: user, Before: b, MaxRows: limit})
	if err != nil {
		return nil, fmt.Errorf("listens: %w", err)
	}
	out := make([]Listen, len(rows))
	for i, r := range rows {
		out[i] = Listen{
			ID: r.ID, ListenedAt: r.ListenedAt, Artist: r.Artist, Track: r.Track, Album: r.Album,
			DurationMs: intPtr(r.DurationMs), ReleaseGroupMBID: r.ReleaseGroupMbid, AlbumTitleID: r.AlbumTitleID,
			OriginURL: r.OriginUrl, Client: r.Client, MusicService: r.MusicService,
		}
	}
	return out, nil
}

const artistKey = "split_part(track_key, chr(31), 1)"

// Top is the period's totals and its limit most played artists, tracks or albums. artist narrows it
// to one artist, compared folded.
//
// pgx directly: the grouping key is spliced into GROUP BY and ORDER BY, which sqlc cannot vary.
func (s *Store) Top(ctx context.Context, user uuid.UUID, by Grouping, period stats.Period, limit int, artist *string) (Top, error) {
	var folded *string
	if artist != nil {
		f := Fold(*artist)
		folded = &f
	}
	// The period's local midnights as instants, so `listens_user_time` bounds the scan; the same
	// days as comparing each listen's local date, without computing it per row.
	inPeriod := `user_id = $1
  AND listened_at >= ($2::date)::timestamp AT TIME ZONE $4::text
  AND listened_at < ($3::date)::timestamp AT TIME ZONE $4::text
  AND ($5::text IS NULL OR ` + artistKey + ` = $5::text)`
	args := []any{user, period.Start.String(), period.End.String(), period.TimeZone.String(), folded}
	var out Top
	err := s.Pool.QueryRow(ctx,
		`SELECT count(*)::int, coalesce(sum(duration_ms), 0)::bigint FROM listens WHERE `+inPeriod, args...).
		Scan(&out.Listens, &out.DurationMs)
	if err != nil {
		return Top{}, fmt.Errorf("listen totals: %w", err)
	}
	// Grouped by the folded spelling; the newest listen's spelling is the one shown, and the newest
	// identified album gives the row its cover.
	key, albumOnly := artistKey, ""
	switch by {
	case ByTrack:
		key = "track_key"
	case ByAlbum:
		key = artistKey + " || chr(31) || lower(album)"
		albumOnly = "AND album IS NOT NULL"
	case ByArtist:
	}
	rows, err := s.Pool.Query(ctx, `
SELECT ranked.artist, ranked.track, ranked.album, ranked.release_group_mbid, ranked.count, ranked.duration_ms,
       t.id AS album_title_id
FROM (
    SELECT (array_agg(artist ORDER BY listened_at DESC))[1] AS artist,
           (array_agg(track ORDER BY listened_at DESC))[1] AS track,
           (array_agg(album ORDER BY listened_at DESC))[1] AS album,
           (array_agg(release_group_mbid ORDER BY listened_at DESC)
                FILTER (WHERE release_group_mbid IS NOT NULL))[1] AS release_group_mbid,
           count(*)::int AS count, coalesce(sum(duration_ms), 0)::bigint AS duration_ms,
           `+key+` AS sort_key
    FROM listens
    WHERE `+inPeriod+` `+albumOnly+`
    GROUP BY `+key+`
    ORDER BY count(*) DESC, sum(duration_ms) DESC NULLS LAST, `+key+`
    LIMIT $6
) ranked
LEFT JOIN titles t ON t.musicbrainz = ranked.release_group_mbid
ORDER BY ranked.count DESC, ranked.duration_ms DESC, ranked.sort_key`, append(args, limit)...)
	if err != nil {
		return Top{}, fmt.Errorf("top listens: %w", err)
	}
	defer rows.Close()
	out.Items = []Total{}
	for rows.Next() {
		var t Total
		var track, album *string
		if err := rows.Scan(&t.Artist, &track, &album, &t.ReleaseGroupMBID, &t.Count, &t.DurationMs, &t.AlbumTitleID); err != nil {
			return Top{}, fmt.Errorf("top listens: %w", err)
		}
		if by == ByTrack {
			t.Track = track
		}
		if by == ByAlbum {
			t.Album = album
		}
		out.Items = append(out.Items, t)
	}
	if err := rows.Err(); err != nil {
		return Top{}, fmt.Errorf("top listens: %w", err)
	}
	return out, nil
}

// Unresolved is tracks still waiting for an album that were never looked up, or whose last miss is
// older than retryBefore; newest listens first.
func (s *Store) Unresolved(ctx context.Context, retryBefore time.Time, limit int) ([]Lookup, error) {
	rows, err := s.Q.UnresolvedListens(ctx, sqlc.UnresolvedListensParams{
		RetryBefore: ts(retryBefore), MaxRows: int32(min(limit, math.MaxInt32)), //nolint:gosec // clamped
	})
	if err != nil {
		return nil, fmt.Errorf("unresolved listens: %w", err)
	}
	out := make([]Lookup, len(rows))
	for i, r := range rows {
		out[i] = Lookup{TrackKey: r.TrackKey, AlbumKey: r.AlbumKey, Query: catalog.RecordingQuery{
			Artist: r.Artist, Track: r.Track, Album: r.Album, RecordingMBID: r.RecordingMbid, ISRC: r.Isrc,
		}}
	}
	return out, nil
}

// Resolve keeps what MusicBrainz said, and fills the ids of every listen of that track and album
// that lacks them. Returns how many listens gained an album.
func (s *Store) Resolve(ctx context.Context, lookup Lookup, match catalog.RecordingMatch, at time.Time) (int, error) {
	var filled int64
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.SaveMusicLookup(ctx, sqlc.SaveMusicLookupParams{
			TrackKey: lookup.TrackKey, AlbumKey: lookup.AlbumKey, RecordingMbid: match.RecordingMBID,
			ReleaseGroupMbid: match.ReleaseGroupMBID, ArtistMbid: match.ArtistMBID, LookedUpAt: ts(at),
		}); err != nil {
			return err
		}
		var err error
		filled, err = q.FillListenIDs(ctx, sqlc.FillListenIDsParams{
			RecordingMbid: match.RecordingMBID, ReleaseGroupMbid: match.ReleaseGroupMBID, ArtistMbid: match.ArtistMBID,
			TrackKey: lookup.TrackKey, AlbumKey: lookup.AlbumKey,
		})
		return err
	})
	if err != nil {
		return 0, fmt.Errorf("resolve listens: %w", err)
	}
	if match.ReleaseGroupMBID == nil {
		return 0, nil
	}
	return int(filled), nil
}

// MARK: MUS-004 · listening history imports. A job's plays are staged, counted against the log with
// the live duplicate window, written as the job's `import` listens, and deleted with it on undo.

// Stage adds plays to a job's staging, numbered from index.
//
// pgx COPY directly: sqlc rejects the many-array unnest a bulk insert needs.
func (s *Store) Stage(ctx context.Context, listens []NewListen, jobID uuid.UUID, index int) error {
	rows := make([][]any, len(listens))
	for i, l := range listens {
		rows[i] = []any{
			jobID, int32(index + i), l.ListenedAt, l.Artist, l.Track, l.Album, l.TrackKey(), i32(l.DurationMs), //nolint:gosec // an import's size
			l.ISRC, l.RecordingMBID, l.ReleaseMBID, l.ReleaseGroupMBID, l.ArtistMBID, l.SpotifyID, l.OriginURL,
			l.Client, l.MusicService,
		}
	}
	_, err := s.Pool.CopyFrom(ctx, pgx.Identifier{"import_listens"}, []string{
		"job_id", "idx", "listened_at", "artist", "track", "album", "track_key", "duration_ms", "isrc",
		"recording_mbid", "release_mbid", "release_group_mbid", "artist_mbid", "spotify_id", "origin_url",
		"client", "music_service",
	}, pgx.CopyFromRows(rows))
	if err != nil {
		return fmt.Errorf("stage listens: %w", err)
	}
	return nil
}

// ClearStaged empties a job's staging, so a retried fetch starts over.
func (s *Store) ClearStaged(ctx context.Context, jobID uuid.UUID) error {
	if err := s.Q.ClearStagedListens(ctx, jobID); err != nil {
		return fmt.Errorf("clear staged listens: %w", err)
	}
	return nil
}

// CountNew is how many staged plays applying would keep: those outside every stored listen's
// duplicate window and outside the window of the play before them of the same track.
func (s *Store) CountNew(ctx context.Context, jobID, user uuid.UUID) (int, error) {
	n, err := s.Q.CountNewStagedListens(ctx, sqlc.CountNewStagedListensParams{JobID: jobID, UserID: user})
	if err != nil {
		return 0, fmt.Errorf("count staged listens: %w", err)
	}
	return int(n), nil
}

// ApplyStaged writes the plays CountNew counts as the job's `import` listens, then empties its
// staging. Returns how many were written.
func (s *Store) ApplyStaged(ctx context.Context, jobID, user uuid.UUID) (int, error) {
	var written int32
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		// The same per-user lock as a scrobbler's insert, so a live listen arriving now is compared
		// with these, or these with it.
		if err := q.LockUserListens(ctx, userKey(user)); err != nil {
			return err
		}
		var err error
		if written, err = q.ApplyStagedListens(ctx, sqlc.ApplyStagedListensParams{JobID: jobID, UserID: user}); err != nil {
			return err
		}
		return q.ClearStagedListens(ctx, jobID)
	})
	if err != nil {
		return 0, fmt.Errorf("apply staged listens: %w", err)
	}
	return int(written), nil
}

// DeleteImported deletes the listens a job wrote. Returns how many.
func (s *Store) DeleteImported(ctx context.Context, jobID, user uuid.UUID) (int, error) {
	n, err := s.Q.DeleteImportedListens(ctx, sqlc.DeleteImportedListensParams{UserID: user, JobID: jobID})
	if err != nil {
		return 0, fmt.Errorf("delete imported listens: %w", err)
	}
	return int(n), nil
}

// NewestImported is the newest listen an applied import of this source and account wrote, so the
// next import of it reads only what came after.
func (s *Store) NewestImported(ctx context.Context, user uuid.UUID, source core.ImportSource, account string) (*time.Time, error) {
	newest, err := s.Q.NewestImportedListen(ctx, sqlc.NewestImportedListenParams{
		UserID: user, Source: string(source), Account: account,
	})
	if err != nil {
		return nil, fmt.Errorf("newest imported listen: %w", err)
	}
	if !newest.Valid {
		return nil, nil //nolint:nilnil // none imported yet
	}
	t := newest.Time
	return &t, nil
}
