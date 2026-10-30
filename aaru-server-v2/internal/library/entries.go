package library

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// entryQuery is one page of entries with title and show progress in one query (PROG-003: no N+1).
//
// pgx directly, not sqlc: the WHERE clause is built from the filter (as the Swift store's
// SQLQueryString did), and sqlc reads the LATERAL subquery's columns as non-null although a show
// with nothing left to watch has none.
type entryQuery struct {
	where []string
	args  []any
}

// add appends a clause; each `?` binds the next arg. $1 and $2 are the user and now.
func (q *entryQuery) add(clause string, args ...any) {
	for _, a := range args {
		q.args = append(q.args, a)
		clause = strings.Replace(clause, "?", "$"+strconv.Itoa(len(q.args)+2), 1)
	}
	q.where = append(q.where, clause)
}

// entryRow is one row of entryQuery, scanned in column order.
type entryRow struct {
	id, titleID                                         uuid.UUID
	status                                              string
	rating                                              *float64
	notes                                               *string
	isOwned                                             bool
	addedAt, updatedAt                                  time.Time
	finishedAt                                          *time.Time
	bookPage                                            *int32
	bookPercent                                         *float64
	mangaChapter, mangaVolume                           *int32
	statusByHand                                        bool
	updatedMicros                                       int64
	typ, title                                          string
	originalTitle                                       *string
	year                                                *int32
	synopsis, posterURL, backdropURL, network           *string
	isAnime                                             bool
	byline                                              *string
	pageCount, chapterCount, volumeCount                *int32
	tmdb, imdb, trakt, tvdb, isbn, openLibrary, anilist *string
	mal, anidb, musicbrainz                             *string
	watchedCount, airedCount                            int32
	nextSeason, nextEpisode                             *int32
	lastWatchedAt                                       *time.Time
}

func (s *Store) entryRows(ctx context.Context, user uuid.UUID, now time.Time, q entryQuery, limit int) ([]entryRow, error) {
	const aired = `(se.airs_at <= $2 OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))`
	args := append([]any{user, now}, q.args...)
	where := ""
	for _, clause := range q.where {
		where += " AND " + clause
	}
	sql := `
SELECT li.id, li.title_id, li.status, li.rating, li.notes, li.is_owned, li.added_at, li.updated_at,
    li.finished_at, li.book_page, li.book_percent, li.manga_chapter, li.manga_volume, li.status_by_hand,
    (extract(epoch FROM li.updated_at) * 1000000)::bigint AS updated_micros,
    t.type, t.title, t.original_title, t.year, t.synopsis, t.poster_url, t.backdrop_url, t.network, t.is_anime,
    t.byline, t.page_count, t.chapter_count, t.volume_count, t.tmdb, t.imdb, t.trakt, t.tvdb, t.isbn,
    t.open_library, t.anilist, t.mal, t.anidb, t.musicbrainz,
    (SELECT count(*)::int FROM episode_progress ep WHERE ep.library_item_id = li.id AND ep.season > 0)
        AS watched_count,
    (SELECT count(*)::int FROM show_episodes se WHERE se.title_id = li.title_id AND se.season > 0
        AND ` + aired + `) AS aired_count,
    next.season AS next_season, next.episode AS next_episode,
    (SELECT max(ep.watched_at) FROM episode_progress ep WHERE ep.library_item_id = li.id
        AND ep.watched_at_known) AS last_watched_at
FROM library_items li
JOIN titles t ON t.id = li.title_id
LEFT JOIN LATERAL (
    SELECT se.season, se.episode FROM show_episodes se
    WHERE se.title_id = li.title_id AND se.season > 0 AND ` + aired + `
      AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                      AND ep.season = se.season AND ep.episode = se.episode)
    ORDER BY se.season, se.episode LIMIT 1
) next ON t.type = 'show'
WHERE li.user_id = $1` + where + `
ORDER BY li.updated_at DESC, li.id DESC LIMIT ` + strconv.Itoa(limit)
	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, fmt.Errorf("library entries: %w", err)
	}
	defer rows.Close()
	var out []entryRow
	for rows.Next() {
		var r entryRow
		if err := rows.Scan(
			&r.id, &r.titleID, &r.status, &r.rating, &r.notes, &r.isOwned, &r.addedAt, &r.updatedAt,
			&r.finishedAt, &r.bookPage, &r.bookPercent, &r.mangaChapter, &r.mangaVolume, &r.statusByHand,
			&r.updatedMicros,
			&r.typ, &r.title, &r.originalTitle, &r.year, &r.synopsis, &r.posterURL, &r.backdropURL, &r.network, &r.isAnime,
			&r.byline, &r.pageCount, &r.chapterCount, &r.volumeCount, &r.tmdb, &r.imdb, &r.trakt, &r.tvdb, &r.isbn,
			&r.openLibrary, &r.anilist, &r.mal, &r.anidb, &r.musicbrainz,
			&r.watchedCount, &r.airedCount, &r.nextSeason, &r.nextEpisode, &r.lastWatchedAt,
		); err != nil {
			return nil, fmt.Errorf("library entry row: %w", err)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("library entry rows: %w", err)
	}
	return out, nil
}

func sv(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// entry is the row as a library entry; false when its status or type is unknown.
func (r entryRow) entry(user uuid.UUID) (Entry, bool) {
	status := core.LibraryStatus(r.status)
	typ := core.MediaType(r.typ)
	if !status.Valid() || !typ.Valid() {
		return Entry{}, false
	}
	var rating *core.Rating
	if r.rating != nil {
		if v, err := core.NewRating(*r.rating); err == nil {
			rating = &v
		}
	}
	item := core.LibraryItem{
		ID: r.id, UserID: user, TitleID: r.titleID, Status: status, IsOwned: r.isOwned, Rating: rating, Notes: r.notes,
		AddedAt: r.addedAt.UTC(), UpdatedAt: r.updatedAt.UTC(), FinishedAt: utcPtr(r.finishedAt),
	}
	title := core.Title{
		ID: r.titleID, Type: typ, Title: r.title, OriginalTitle: r.originalTitle, Year: iptr(r.year), Synopsis: r.synopsis,
		PosterURL: r.posterURL, BackdropURL: r.backdropURL, Network: r.network, Byline: r.byline,
		PageCount: iptr(r.pageCount), ChapterCount: iptr(r.chapterCount), VolumeCount: iptr(r.volumeCount),
		IDs: core.ExternalIDs{
			TMDB: sv(r.tmdb), IMDB: sv(r.imdb), Trakt: sv(r.trakt), TVDB: sv(r.tvdb), ISBN: sv(r.isbn),
			OpenLibrary: sv(r.openLibrary), AniList: sv(r.anilist), MAL: sv(r.mal), AniDB: sv(r.anidb),
			MusicBrainz: sv(r.musicbrainz),
		},
		IsAnime: r.isAnime,
	}
	e := Entry{Item: item, Title: title, LastWatchedAt: utcPtr(r.lastWatchedAt), StatusByHand: r.statusByHand}
	switch typ {
	case core.MediaBook:
		e.BookProgress = &BookPosition{Page: iptr(r.bookPage), Percent: r.bookPercent}
	case core.MediaManga:
		e.MangaProgress = &MangaPosition{Chapter: iptr(r.mangaChapter), Volume: iptr(r.mangaVolume)}
	case core.MediaShow:
		p := &ProgressSummary{WatchedCount: int(r.watchedCount), AiredCount: int(r.airedCount)}
		if r.nextSeason != nil && r.nextEpisode != nil {
			if k, err := core.NewEpisodeKey(int(*r.nextSeason), int(*r.nextEpisode)); err == nil {
				p.NextEpisode = &k
			}
		}
		e.Progress = p
	}
	return e, true
}

func toEntries(rows []entryRow, user uuid.UUID) []Entry {
	out := make([]Entry, 0, len(rows))
	for _, r := range rows {
		if e, ok := r.entry(user); ok {
			out = append(out, e)
		}
	}
	return out
}

// Entry is the user's item with its title and progress, or nil. Another user's item is nil.
func (s *Store) Entry(ctx context.Context, id, user uuid.UUID, now time.Time) (*Entry, error) {
	var q entryQuery
	q.add("li.id = ?", id)
	rows, err := s.entryRows(ctx, user, now, q, 1)
	if err != nil {
		return nil, err
	}
	if es := toEntries(rows, user); len(es) > 0 {
		return &es[0], nil
	}
	return nil, nil //nolint:nilnil // none
}

// EntryForTitle is the user's item for a title, or nil.
func (s *Store) EntryForTitle(ctx context.Context, user, titleID uuid.UUID, now time.Time) (*Entry, error) {
	var q entryQuery
	q.add("li.title_id = ?", titleID)
	rows, err := s.entryRows(ctx, user, now, q, 1)
	if err != nil {
		return nil, err
	}
	if es := toEntries(rows, user); len(es) > 0 {
		return &es[0], nil
	}
	return nil, nil //nolint:nilnil // none
}

// Entries is one page of the user's entries matching the filter, newest change first, and the
// cursor for the next page (nil on the last).
func (s *Store) Entries(ctx context.Context, user uuid.UUID, filter Filter, after *Cursor, limit int, now time.Time) ([]Entry, *Cursor, error) {
	var q entryQuery
	if filter.Type != nil {
		q.add("t.type = ?", string(*filter.Type))
	}
	if filter.IsAnime != nil {
		q.add("t.is_anime = ?", *filter.IsAnime)
	}
	if filter.Status != nil {
		q.add("li.status = ?", string(*filter.Status))
	}
	if filter.IsOwned != nil {
		q.add("li.is_owned = ?", *filter.IsOwned)
	}
	if list := filter.List(); list != nil {
		q.add(`EXISTS (SELECT 1 FROM list_items lst JOIN lists l ON l.id = lst.list_id
            WHERE lst.list_id = ? AND l.user_id = li.user_id AND lst.title_id = li.title_id)`, *list)
	}
	if after != nil {
		q.add(`(li.updated_at, li.id) <
            ('epoch'::timestamptz + ?::bigint * interval '1 microsecond', ?::uuid)`, after.UpdatedAtMicros, after.ID)
	}
	rows, err := s.entryRows(ctx, user, now, q, limit+1)
	if err != nil {
		return nil, nil, err
	}
	page := rows
	var next *Cursor
	if len(rows) > limit {
		page = rows[:limit]
		last := page[len(page)-1]
		next = &Cursor{UpdatedAtMicros: last.updatedMicros, ID: last.id}
	}
	return toEntries(page, user), next, nil
}

// Changes are the items changed after since (all when nil) and the ids deleted after it.
func (s *Store) Changes(ctx context.Context, user uuid.UUID, since *time.Time, now time.Time) ([]Entry, []uuid.UUID, error) {
	var q entryQuery
	if since != nil {
		q.add("li.updated_at > ?", *since)
	}
	rows, err := s.entryRows(ctx, user, now, q, 100_000)
	if err != nil {
		return nil, nil, err
	}
	deleted := []uuid.UUID{}
	if since != nil {
		ids, err := s.q.LibraryTombstonesSince(ctx, sqlc.LibraryTombstonesSinceParams{UserID: user, Since: *since})
		if err != nil {
			return nil, nil, fmt.Errorf("tombstones: %w", err)
		}
		deleted = append(deleted, ids...)
	}
	return toEntries(rows, user), deleted, nil
}
