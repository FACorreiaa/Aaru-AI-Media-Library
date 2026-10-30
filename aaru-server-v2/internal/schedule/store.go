package schedule

import (
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// TitleColumns are the title columns PostgresScheduleStore (and Tonight's store) select, for
// queries written with pgx. Scan them with TitleScan.Targets.
const TitleColumns = `t.id, t.type, t.title, t.original_title, t.year, t.synopsis, t.poster_url, t.backdrop_url,
    t.network, t.is_anime, t.tmdb, t.imdb, t.trakt, t.tvdb, t.isbn, t.open_library, t.anilist, t.mal, t.anidb`

// TitleScan receives TitleColumns.
type TitleScan struct {
	id                                                  uuid.UUID
	mediaType, title                                    string
	originalTitle, synopsis, poster, backdrop, network  *string
	year                                                *int32
	isAnime                                             bool
	tmdb, imdb, trakt, tvdb, isbn, openLibrary, anilist *string
	mal, anidb                                          *string
}

// Targets are the scan destinations, in TitleColumns' order.
func (s *TitleScan) Targets() []any {
	return []any{
		&s.id, &s.mediaType, &s.title, &s.originalTitle, &s.year, &s.synopsis, &s.poster, &s.backdrop,
		&s.network, &s.isAnime, &s.tmdb, &s.imdb, &s.trakt, &s.tvdb, &s.isbn, &s.openLibrary, &s.anilist, &s.mal, &s.anidb,
	}
}

// Title is the scanned title; false for an unknown media type.
func (s *TitleScan) Title() (core.Title, bool) {
	t := core.MediaType(s.mediaType)
	if !t.Valid() {
		return core.Title{}, false
	}
	return core.Title{
		ID: s.id, Type: t, Title: s.title, OriginalTitle: s.originalTitle, Year: intPtr(s.year),
		Synopsis: s.synopsis, PosterURL: s.poster, BackdropURL: s.backdrop, Network: s.network, IsAnime: s.isAnime,
		IDs: core.ExternalIDs{
			TMDB: str(s.tmdb), IMDB: str(s.imdb), Trakt: str(s.trakt), TVDB: str(s.tvdb), ISBN: str(s.isbn),
			OpenLibrary: str(s.openLibrary), AniList: str(s.anilist), MAL: str(s.mal), AniDB: str(s.anidb),
		},
	}, true
}

// unfinished is every dropped item, and in-progress items last changed before stalledBefore that
// are not in Continue watching (a show with an aired, unwatched episode). Newest change first.
//
// pgx directly: the LEFT JOIN LATERAL's columns are null for non-shows, and sqlc reads them as non-null.
func (s *Service) unfinished(ctx context.Context, userID uuid.UUID, stalledBefore, now time.Time, limit int) ([]UnfinishedEntry, error) {
	// `next` is Continue watching's rule: an in-progress show with one is already there.
	rows, err := s.pool.Query(ctx, `
SELECT li.id, `+TitleColumns+`, li.status, li.updated_at, next.season, next.episode
FROM library_items li
JOIN titles t ON t.id = li.title_id
LEFT JOIN LATERAL (
    SELECT se.season, se.episode FROM show_episodes se
    WHERE se.title_id = li.title_id AND se.season > 0
      AND (se.airs_at <= $3 OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
      AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                      AND ep.season = se.season AND ep.episode = se.episode)
    ORDER BY se.season, se.episode LIMIT 1
) next ON t.type = 'show'
WHERE li.user_id = $1
  AND (li.status = 'dropped'
       OR (li.status = 'in_progress' AND li.updated_at < $2 AND next.season IS NULL))
ORDER BY li.updated_at DESC, li.id DESC
LIMIT $4`, userID, stalledBefore, now, limit)
	if err != nil {
		return nil, fmt.Errorf("unfinished: %w", err)
	}
	defer rows.Close()
	out := []UnfinishedEntry{}
	for rows.Next() {
		var (
			itemID          uuid.UUID
			ts              TitleScan
			status          string
			updatedAt       time.Time
			season, episode *int32
		)
		targets := append([]any{&itemID}, ts.Targets()...)
		targets = append(targets, &status, &updatedAt, &season, &episode)
		if err := rows.Scan(targets...); err != nil {
			return nil, fmt.Errorf("unfinished row: %w", err)
		}
		title, ok := ts.Title()
		if !ok {
			continue
		}
		entry := UnfinishedEntry{LibraryItemID: itemID, Title: title, Reason: ReasonStalled, Since: updatedAt}
		if status == string(core.StatusDropped) {
			entry.Reason = ReasonDropped
		}
		if season != nil && episode != nil {
			if key, err := core.NewEpisodeKey(int(*season), int(*episode)); err == nil {
				entry.Next = &key
			}
		}
		out = append(out, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("unfinished rows: %w", err)
	}
	return out, nil
}
