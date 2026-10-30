package schedule

import (
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The library reads below mirror PostgresLibraryStore+Reads.swift's entryRows and watchedKeys.
// The library service is ported on its own branch; fold these into internal/library after merge.

// ProgressSummary is PROG-003's derived show progress: specials (season 0) are not counted, and
// aired counts episodes whose air time has passed plus undated episodes of an ended or canceled show.
type ProgressSummary struct {
	WatchedCount int
	AiredCount   int
	NextEpisode  *core.EpisodeKey
}

// LibraryEntry is a library item with the title it points at and, for shows, derived progress.
type LibraryEntry struct {
	Item  core.LibraryItem
	Title core.Title
	// BookPage/BookPercent are set for books only (HasBookProgress).
	HasBookProgress bool
	BookPage        *int
	BookPercent     *float64
	Progress        *ProgressSummary
	// MangaChapter/MangaVolume are set for manga only (HasMangaProgress).
	HasMangaProgress bool
	MangaChapter     *int
	MangaVolume      *int
	// LastWatchedAt is the newest episode tick made live in Aaru (`watched_at_known`).
	LastWatchedAt *time.Time
	// StatusByHand is a status chosen by a tap, not an import.
	StatusByHand bool
}

// InBacklog is APP-018: an anime in progress the user never touched in Aaru (an imported status
// and no live tick). Derived, never stored, never a status.
func (e LibraryEntry) InBacklog() bool {
	return e.Title.IsAnime && e.Item.Status == core.StatusInProgress && !e.StatusByHand && e.LastWatchedAt == nil
}

// EntryFilter narrows ReadEntries. Zero values mean no filter.
type EntryFilter struct {
	Status *core.LibraryStatus
}

// entryQuery is entryRows' one query: entries with their title and show progress, no N+1.
//
// pgx directly: the LEFT JOIN LATERAL's columns are null for a show with nothing left, and sqlc
// reads them as non-null.
const entryQuery = `
SELECT li.id, li.title_id, li.status, li.rating, li.notes, li.is_owned, li.added_at, li.updated_at,
    li.finished_at, li.book_page, li.book_percent, li.manga_chapter, li.manga_volume, li.status_by_hand,
    t.type, t.title, t.original_title, t.year, t.synopsis, t.poster_url, t.backdrop_url, t.network, t.is_anime,
    t.byline, t.page_count, t.chapter_count, t.volume_count, t.tmdb, t.imdb, t.trakt, t.tvdb, t.isbn,
    t.open_library, t.anilist, t.mal, t.anidb, t.musicbrainz,
    (SELECT count(*)::int FROM episode_progress ep WHERE ep.library_item_id = li.id AND ep.season > 0)
        AS watched_count,
    (SELECT count(*)::int FROM show_episodes se WHERE se.title_id = li.title_id AND se.season > 0
        AND (se.airs_at <= $2 OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))) AS aired_count,
    next.season AS next_season, next.episode AS next_episode,
    (SELECT max(ep.watched_at) FROM episode_progress ep WHERE ep.library_item_id = li.id
        AND ep.watched_at_known) AS last_watched_at
FROM library_items li
JOIN titles t ON t.id = li.title_id
LEFT JOIN LATERAL (
    SELECT se.season, se.episode FROM show_episodes se
    WHERE se.title_id = li.title_id AND se.season > 0
      AND (se.airs_at <= $2 OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
      AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                      AND ep.season = se.season AND ep.episode = se.episode)
    ORDER BY se.season, se.episode LIMIT 1
) next ON t.type = 'show'
WHERE li.user_id = $1 AND ($3::text IS NULL OR li.status = $3)
ORDER BY li.updated_at DESC, li.id DESC
LIMIT $4`

// ReadEntries is the user's library entries, newest change first.
func ReadEntries(ctx context.Context, pool *pgxpool.Pool, userID uuid.UUID, filter EntryFilter, limit int, now time.Time) ([]LibraryEntry, error) {
	var status *string
	if filter.Status != nil {
		s := string(*filter.Status)
		status = &s
	}
	rows, err := pool.Query(ctx, entryQuery, userID, now, status, limit)
	if err != nil {
		return nil, fmt.Errorf("library entries: %w", err)
	}
	entries, err := pgx.CollectRows(rows, scanEntry)
	if err != nil {
		return nil, fmt.Errorf("library entries: %w", err)
	}
	out := make([]LibraryEntry, 0, len(entries))
	for _, e := range entries {
		if e != nil {
			e.Item.UserID = userID
			out = append(out, *e)
		}
	}
	return out, nil
}

// scanEntry decodes one row; nil for an unknown status or media type, as Swift's compactMap.
func scanEntry(row pgx.CollectableRow) (*LibraryEntry, error) {
	var (
		e                                          LibraryEntry
		status, mediaType                          string
		rating                                     *float64
		year, pageCount, chapterCount, volumeCount *int32
		bookPage, mangaChapter, mangaVolume        *int32
		tmdb, imdb, trakt, tvdb, isbn, openLibrary *string
		anilist, mal, anidb, musicbrainz           *string
		watchedCount, airedCount                   int32
		nextSeason, nextEpisode                    *int32
	)
	err := row.Scan(&e.Item.ID, &e.Item.TitleID, &status, &rating, &e.Item.Notes, &e.Item.IsOwned, &e.Item.AddedAt,
		&e.Item.UpdatedAt, &e.Item.FinishedAt, &bookPage, &e.BookPercent, &mangaChapter, &mangaVolume, &e.StatusByHand,
		&mediaType, &e.Title.Title, &e.Title.OriginalTitle, &year, &e.Title.Synopsis, &e.Title.PosterURL,
		&e.Title.BackdropURL, &e.Title.Network, &e.Title.IsAnime, &e.Title.Byline, &pageCount, &chapterCount,
		&volumeCount, &tmdb, &imdb, &trakt, &tvdb, &isbn, &openLibrary, &anilist, &mal, &anidb, &musicbrainz,
		&watchedCount, &airedCount, &nextSeason, &nextEpisode, &e.LastWatchedAt)
	if err != nil {
		return nil, err
	}
	e.Item.Status = core.LibraryStatus(status)
	e.Title.Type = core.MediaType(mediaType)
	if !e.Item.Status.Valid() || !e.Title.Type.Valid() {
		return nil, nil
	}
	e.Title.ID = e.Item.TitleID
	if rating != nil {
		if r, err := core.NewRating(*rating); err == nil {
			e.Item.Rating = &r
		}
	}
	e.Title.Year, e.Title.PageCount = intPtr(year), intPtr(pageCount)
	e.Title.ChapterCount, e.Title.VolumeCount = intPtr(chapterCount), intPtr(volumeCount)
	e.Title.IDs = core.ExternalIDs{
		TMDB: str(tmdb), IMDB: str(imdb), Trakt: str(trakt), TVDB: str(tvdb), ISBN: str(isbn),
		OpenLibrary: str(openLibrary), AniList: str(anilist), MAL: str(mal), AniDB: str(anidb), MusicBrainz: str(musicbrainz),
	}
	switch e.Title.Type {
	case core.MediaBook:
		e.HasBookProgress, e.BookPage = true, intPtr(bookPage)
	case core.MediaShow:
		p := &ProgressSummary{WatchedCount: int(watchedCount), AiredCount: int(airedCount)}
		if nextSeason != nil && nextEpisode != nil {
			if key, err := core.NewEpisodeKey(int(*nextSeason), int(*nextEpisode)); err == nil {
				p.NextEpisode = &key
			}
		}
		e.Progress = p
	case core.MediaManga:
		e.HasMangaProgress, e.MangaChapter, e.MangaVolume = true, intPtr(mangaChapter), intPtr(mangaVolume)
	}
	if !e.HasBookProgress {
		e.BookPercent = nil
	}
	return &e, nil
}

// ReadWatched is every tick of these items, sorted by season then episode (one query, no N+1).
func ReadWatched(ctx context.Context, pool *pgxpool.Pool, itemIDs []uuid.UUID) (map[uuid.UUID][]core.EpisodeKey, error) {
	out := map[uuid.UUID][]core.EpisodeKey{}
	if len(itemIDs) == 0 {
		return out, nil
	}
	rows, err := pool.Query(ctx, `SELECT library_item_id, season, episode FROM episode_progress
WHERE library_item_id = ANY($1::uuid[])`, itemIDs)
	if err != nil {
		return nil, fmt.Errorf("watched episodes: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var (
			id              uuid.UUID
			season, episode int32
		)
		if err := rows.Scan(&id, &season, &episode); err != nil {
			return nil, fmt.Errorf("watched episode: %w", err)
		}
		if key, err := core.NewEpisodeKey(int(season), int(episode)); err == nil {
			out[id] = append(out[id], key)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("watched episodes: %w", err)
	}
	for id, keys := range out {
		slices.SortFunc(keys, core.EpisodeKey.Compare)
		out[id] = slices.Compact(keys)
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
