package social

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"golang.org/x/sync/errgroup"
)

// What one friend may see of another (PostgresFriendViewStore.swift). Activity is read from the
// library at query time; there is no fan-out table (ARCHITECTURE.md §Social).

// FriendItem is one title on a friend's shelf, without anything private to them (notes, owned).
type FriendItem struct {
	TitleID uuid.UUID
	Status  core.LibraryStatus
	Rating  *float64
	// LastSeason and LastEpisode are the last episode they ticked, for shows.
	LastSeason   *int
	LastEpisode  *int
	BookPage     *int
	MangaChapter *int
	FinishedAt   *time.Time
	UpdatedAt    time.Time
}

// FriendShelf is what a friend's profile shows: their shelves, and what the viewer and they share.
type FriendShelf struct {
	Watching []FriendItem
	Finished []FriendItem
	// Counts is library size by kind (dropped left out): movie, show, anime, book, album, manga.
	Counts map[string]int
	// BothWant are titles both have planned.
	BothWant     []uuid.UUID
	BothFinished int
	// TheyLoved are titles the friend rated 8 or more that the viewer does not have at all.
	TheyLoved []uuid.UUID
}

// FriendActivity is one person's activity on one title on one UTC day: dated episode ticks, a
// finish, or both. Imported and restored ticks carry no date and are never activity.
type FriendActivity struct {
	Friend  uuid.UUID
	TitleID uuid.UUID
	// Day is the UTC day, yyyy-MM-dd.
	Day         string
	Episodes    int
	LastSeason  *int
	LastEpisode *int
	Finished    bool
	Rating      *float64
	// LastAt is the latest tick or finish in the row.
	LastAt time.Time
}

// Shelf reads a friend's shelf as the viewer sees it.
func (s *Store) Shelf(ctx context.Context, owner, viewer uuid.UUID, limit int) (FriendShelf, error) {
	var shelf FriendShelf
	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) {
		shelf.Watching, err = s.shelfItems(ctx, owner, "in_progress", "li.updated_at DESC", limit)
		return err
	})
	g.Go(func() (err error) {
		shelf.Finished, err = s.shelfItems(ctx, owner, "finished", "li.finished_at DESC NULLS LAST, li.updated_at DESC", limit)
		return err
	})
	g.Go(func() error {
		rows, err := s.Q.SocialKindCounts(ctx, owner)
		if err != nil {
			return err
		}
		shelf.Counts = map[string]int{}
		for _, r := range rows {
			shelf.Counts[r.Kind] = int(r.Count)
		}
		return nil
	})
	g.Go(func() (err error) {
		shelf.BothWant, err = s.Q.SocialBothWant(ctx, sqlc.SocialBothWantParams{Viewer: viewer, Owner: owner, MaxRows: int32(limit)}) //nolint:gosec // a small constant
		return err
	})
	g.Go(func() (err error) {
		shelf.TheyLoved, err = s.Q.SocialTheyLoved(ctx, sqlc.SocialTheyLovedParams{Owner: owner, Viewer: viewer, MaxRows: int32(limit)}) //nolint:gosec // a small constant
		return err
	})
	g.Go(func() error {
		n, err := s.Q.SocialBothFinished(ctx, sqlc.SocialBothFinishedParams{Viewer: viewer, Owner: owner})
		shelf.BothFinished = int(n)
		return err
	})
	if err := g.Wait(); err != nil {
		return FriendShelf{}, fmt.Errorf("friend shelf: %w", err)
	}
	return shelf, nil
}

// shelfItems is written with pgx: sqlc reads the LATERAL join's columns as never null.
func (s *Store) shelfItems(ctx context.Context, owner uuid.UUID, status, order string, limit int) ([]FriendItem, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT li.title_id, li.status, li.rating, last.season, last.episode,
			li.book_page, li.manga_chapter, li.finished_at, li.updated_at
		FROM library_items li
		LEFT JOIN LATERAL (
			SELECT season, episode FROM episode_progress
			WHERE library_item_id = li.id ORDER BY season DESC, episode DESC LIMIT 1
		) last ON true
		WHERE li.user_id = $1 AND li.status = $2
		ORDER BY `+order+`
		LIMIT $3`, owner, status, limit)
	if err != nil {
		return nil, err
	}
	out := []FriendItem{}
	for rows.Next() {
		var (
			item                                       FriendItem
			status                                     string
			season, episode, bookPage, mangaChapter    *int32
		)
		if err := rows.Scan(&item.TitleID, &status, &item.Rating, &season, &episode, &bookPage, &mangaChapter,
			&item.FinishedAt, &item.UpdatedAt); err != nil {
			rows.Close()
			return nil, err
		}
		item.Status = core.LibraryStatus(status)
		if !item.Status.Valid() {
			continue
		}
		item.LastSeason, item.LastEpisode = intOf(season), intOf(episode)
		item.BookPage, item.MangaChapter = intOf(bookPage), intOf(mangaChapter)
		out = append(out, item)
	}
	return out, rows.Err()
}

// Activity is the viewer's and their friends' activity at or after since and before before,
// newest first. Friends who hide their library are left out. Written with pgx: sqlc reads the
// filtered aggregates as never null.
func (s *Store) Activity(ctx context.Context, viewer uuid.UUID, since, before time.Time, limit int) ([]FriendActivity, error) {
	rows, err := s.Pool.Query(ctx, `
		WITH visible AS (
			SELECT f.id FROM (
				SELECT CASE WHEN user_low = $1 THEN user_high ELSE user_low END AS id
				FROM social_friendships
				WHERE user_low = $1 OR user_high = $1
			) f
			LEFT JOIN social_settings s ON s.user_id = f.id
			WHERE coalesce(s.share_library_with_friends, true)
			-- Your own rows too, so you see what friends reacted to (SOC-007).
			UNION ALL SELECT $1::uuid
		), events AS (
			SELECT li.user_id, li.title_id, ep.watched_at AS at, ep.season, ep.episode, false AS finished,
				li.rating
			FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
			WHERE li.user_id IN (SELECT id FROM visible) AND ep.watched_at_known
			  AND ep.watched_at >= $2 AND ep.watched_at < $3
			UNION ALL
			SELECT li.user_id, li.title_id, li.finished_at, NULL, NULL, true, li.rating
			FROM library_items li
			WHERE li.user_id IN (SELECT id FROM visible) AND li.status = 'finished'
			  AND li.finished_at >= $2 AND li.finished_at < $3
		)
		SELECT user_id, title_id, (at AT TIME ZONE 'UTC')::date::text AS day,
			(count(*) FILTER (WHERE NOT finished))::int AS episodes,
			(array_agg(season ORDER BY at DESC) FILTER (WHERE NOT finished))[1] AS last_season,
			(array_agg(episode ORDER BY at DESC) FILTER (WHERE NOT finished))[1] AS last_episode,
			bool_or(finished) AS finished, max(rating) AS rating, max(at) AS last_at
		FROM events
		GROUP BY user_id, title_id, (at AT TIME ZONE 'UTC')::date
		ORDER BY max(at) DESC
		LIMIT $4`, viewer, since, before, limit)
	if err != nil {
		return nil, fmt.Errorf("activity: %w", err)
	}
	items, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (FriendActivity, error) {
		var (
			a               FriendActivity
			episodes        int32
			season, episode *int32
		)
		err := row.Scan(&a.Friend, &a.TitleID, &a.Day, &episodes, &season, &episode, &a.Finished, &a.Rating, &a.LastAt)
		a.Episodes, a.LastSeason, a.LastEpisode = int(episodes), intOf(season), intOf(episode)
		return a, err
	})
	if err != nil {
		return nil, fmt.Errorf("activity: %w", err)
	}
	return items, nil
}

func intOf(v *int32) *int {
	if v == nil {
		return nil
	}
	n := int(*v)
	return &n
}
