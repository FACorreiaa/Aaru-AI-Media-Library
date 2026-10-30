package stats

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"golang.org/x/text/unicode/norm"
)

// ListenSummary is MUS-008: a period's listening, for Insights and the Recap.
type ListenSummary struct {
	Listens    int
	DurationMs int64
	// PriorListens and PriorDurationMs are the previous equal-length window; rolling spans only.
	PriorListens    *int
	PriorDurationMs *int64
	TopArtist       *ListenTotal
	// TopArtistTracks are the top artist's three most played tracks.
	TopArtistTracks []ListenTotal
}

// ListenTotal is one row of a top list: an artist, or a track with its artist.
type ListenTotal struct {
	Artist           string
	Track            *string
	Count            int
	DurationMs       int64
	ReleaseGroupMBID *string
}

type listenTop struct {
	listens    int
	durationMs int64
	items      []ListenTotal
}

// fold is Listen.fold: case-, width- and space-folded, so two spellings of one name compare equal.
func fold(text string) string {
	return strings.Join(strings.Fields(strings.ToLower(norm.NFKC.String(text))), " ")
}

const artistKey = "split_part(track_key, chr(31), 1)"

// top is PostgresListenStore.top for the two groupings the stats read (artist, track): the
// period's totals and its `limit` most played, narrowed to one folded artist when given.
//
// pgx directly: the grouping key is spliced into GROUP BY and ORDER BY, which sqlc cannot vary.
func (s *Service) top(ctx context.Context, userID uuid.UUID, byTrack bool, period Period, limit int, artist *string) (listenTop, error) {
	zone := period.TimeZone.String()
	var folded *string
	if artist != nil {
		f := fold(*artist)
		folded = &f
	}
	// The period's local midnights as instants, so `listens_user_time` bounds the scan.
	inPeriod := `user_id = $1
  AND listened_at >= ($2::date)::timestamp AT TIME ZONE $4::text
  AND listened_at < ($3::date)::timestamp AT TIME ZONE $4::text
  AND ($5::text IS NULL OR ` + artistKey + ` = $5::text)`
	args := []any{userID, period.Start.String(), period.End.String(), zone, folded}
	var out listenTop
	err := s.pool.QueryRow(ctx, `SELECT count(*)::int, coalesce(sum(duration_ms), 0)::bigint FROM listens WHERE `+inPeriod, args...).
		Scan(&out.listens, &out.durationMs)
	if err != nil {
		return out, fmt.Errorf("listen totals: %w", err)
	}
	key := artistKey
	if byTrack {
		key = "track_key"
	}
	// Grouped by the folded spelling; the newest listen's spelling is the one shown, and the newest
	// identified album gives the row its cover.
	rows, err := s.pool.Query(ctx, `
SELECT (array_agg(artist ORDER BY listened_at DESC))[1] AS artist,
       (array_agg(track ORDER BY listened_at DESC))[1] AS track,
       (array_agg(release_group_mbid ORDER BY listened_at DESC)
            FILTER (WHERE release_group_mbid IS NOT NULL))[1] AS release_group_mbid,
       count(*)::int AS count, coalesce(sum(duration_ms), 0)::bigint AS duration_ms
FROM listens
WHERE `+inPeriod+`
GROUP BY `+key+`
ORDER BY count(*) DESC, sum(duration_ms) DESC NULLS LAST, `+key+`
LIMIT $6`, append(args, limit)...)
	if err != nil {
		return out, fmt.Errorf("listen top: %w", err)
	}
	out.items, err = pgx.CollectRows(rows, func(row pgx.CollectableRow) (ListenTotal, error) {
		var t ListenTotal
		var track string
		if err := row.Scan(&t.Artist, &track, &t.ReleaseGroupMBID, &t.Count, &t.DurationMs); err != nil {
			return t, err
		}
		if byTrack {
			t.Track = &track
		}
		return t, nil
	})
	if err != nil {
		return out, fmt.Errorf("listen top: %w", err)
	}
	return out, nil
}

// music is MUS-008: the period's listens and minutes, the top artist and their three most played
// tracks. Listening never adds to the library's totals.
func (s *Service) music(ctx context.Context, userID uuid.UUID, period Period, previous *Period) (*ListenSummary, error) {
	artists, err := s.top(ctx, userID, false, period, 1, nil)
	if err != nil {
		return nil, err
	}
	if artists.listens <= 0 {
		return nil, nil //nolint:nilnil // nil: nothing was heard
	}
	summary := &ListenSummary{Listens: artists.listens, DurationMs: artists.durationMs, TopArtistTracks: []ListenTotal{}}
	if previous != nil {
		prior, err := s.top(ctx, userID, false, *previous, 1, nil)
		if err != nil {
			return nil, err
		}
		summary.PriorListens, summary.PriorDurationMs = &prior.listens, &prior.durationMs
	}
	if len(artists.items) > 0 {
		top := artists.items[0]
		summary.TopArtist = &top
		tracks, err := s.top(ctx, userID, true, period, 3, &top.Artist)
		if err != nil {
			return nil, err
		}
		summary.TopArtistTracks = tracks.items
	}
	return summary, nil
}
