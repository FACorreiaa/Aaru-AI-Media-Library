// Package boards is the friends-only Board (BOARD-001): posts, upvotes and comments. A post is
// visible to its author and to the author's friends, unless either side blocked the other.
// Ported from BoardService.swift, BoardService+Comments.swift, Stores+Boards.swift and
// PostgresBoardStore.swift.
package boards

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/groups"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Post is one post on the Board. Rating needs a title. Counts and UpvotedByViewer are read-time
// values.
type Post struct {
	ID              uuid.UUID
	Author          groups.User
	TitleID         *uuid.UUID
	Rating          *float64
	Body            string
	Spoiler         *groups.SpoilerStamp
	CreatedAt       time.Time
	EditedAt        *time.Time
	Upvotes         int
	UpvotedByViewer bool
	CommentCount    int
}

// Comment is one comment under a post. Author is nil for Aaru (FromAgent) and once the account
// is gone.
type Comment struct {
	ID            uuid.UUID
	PostID        uuid.UUID
	Author        *groups.User
	FromAgent     bool
	ReplyTo       *uuid.UUID
	Body          string
	Mentions      []uuid.UUID
	MentionsAgent bool
	CreatedAt     time.Time
	DeletedAt     *time.Time
}

// Store is the Board's half of the data layer.
type Store struct {
	Q *sqlc.Queries
}

// postFrom reads a post row; every post read's generated row type converts to this one.
func postFrom(r sqlc.BoardPostRow) Post { //nolint:gocritic // rows are passed by value
	p := Post{
		ID:              r.ID,
		Author:          groups.User{ID: r.UserID, Handle: r.Handle, DisplayName: r.DisplayName, AvatarVersion: r.AvatarVersion},
		TitleID:         r.TitleID,
		Rating:          r.Rating,
		Body:            r.Body,
		CreatedAt:       r.CreatedAt,
		EditedAt:        r.EditedAt,
		Upvotes:         int(r.Upvotes),
		UpvotedByViewer: r.UpvotedByViewer,
		CommentCount:    int(r.CommentCount),
	}
	switch {
	case r.SpoilerEnding:
		p.Spoiler = groups.EndingStamp()
	case r.SpoilerSeason != nil && r.SpoilerEpisode != nil:
		p.Spoiler = groups.EpisodeStamp(groups.EpisodePoint{Season: int(*r.SpoilerSeason), Episode: int(*r.SpoilerEpisode)})
	}
	return p
}

// postFields is the shape every generated post row shares.
type postFields = struct {
	ID              uuid.UUID
	UserID          uuid.UUID
	Handle          string
	DisplayName     *string
	AvatarVersion   *int64
	TitleID         *uuid.UUID
	Rating          *float64
	Body            string
	SpoilerSeason   *int32
	SpoilerEpisode  *int32
	SpoilerEnding   bool
	CreatedAt       time.Time
	EditedAt        *time.Time
	Upvotes         int32
	UpvotedByViewer bool
	CommentCount    int32
}

func posts[R ~postFields](rows []R) []Post {
	out := make([]Post, len(rows))
	for i, r := range rows {
		out[i] = postFrom(sqlc.BoardPostRow(r))
	}
	return out
}

// commentFrom reads a comment row; BoardCommentsRow converts to this one.
func commentFrom(r sqlc.BoardCommentRow) Comment { //nolint:gocritic // rows are passed by value
	c := Comment{
		ID: r.ID, PostID: r.PostID, FromAgent: r.AuthorKind == "agent", ReplyTo: r.ReplyTo, Body: r.Body,
		Mentions: r.Mentions, MentionsAgent: r.MentionsAgent, CreatedAt: r.CreatedAt, DeletedAt: r.DeletedAt,
	}
	if c.Mentions == nil {
		c.Mentions = []uuid.UUID{}
	}
	if r.UserID != nil && r.Handle != nil {
		c.Author = &groups.User{ID: *r.UserID, Handle: *r.Handle, DisplayName: r.DisplayName, AvatarVersion: r.AvatarVersion}
	}
	return c
}

// CreatePost stores a post and returns it as given.
func (s *Store) CreatePost(ctx context.Context, p Post) (Post, error) {
	params := sqlc.BoardInsertPostParams{
		ID: p.ID, UserID: p.Author.ID, TitleID: p.TitleID, Rating: p.Rating, Body: p.Body, CreatedAt: p.CreatedAt,
	}
	if p.Spoiler != nil {
		if p.Spoiler.Ending {
			params.SpoilerEnding = true
		} else if p.Spoiler.Episode != nil {
			season, episode := int32(p.Spoiler.Episode.Season), int32(p.Spoiler.Episode.Episode) //nolint:gosec // validated small
			params.SpoilerSeason, params.SpoilerEpisode = &season, &episode
		}
	}
	if err := s.Q.BoardInsertPost(ctx, params); err != nil {
		return Post{}, fmt.Errorf("create board post: %w", err)
	}
	return p, nil
}

// Post is one live post, or nil when it is unknown or deleted.
func (s *Store) Post(ctx context.Context, id, viewer uuid.UUID) (*Post, error) {
	row, err := s.Q.BoardPost(ctx, sqlc.BoardPostParams{ID: id, Viewer: viewer})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: no such post
	}
	if err != nil {
		return nil, fmt.Errorf("board post: %w", err)
	}
	p := postFrom(row)
	return &p, nil
}

// Feed is posts by these authors, newest first, keyset-paged by the id of the last post seen.
func (s *Store) Feed(ctx context.Context, authors []uuid.UUID, before *uuid.UUID, limit int, viewer uuid.UUID) ([]Post, error) {
	rows, err := s.Q.BoardFeed(ctx, sqlc.BoardFeedParams{Viewer: viewer, Authors: authors, Before: before, RowLimit: int32(limit)}) //nolint:gosec // clamped
	if err != nil {
		return nil, fmt.Errorf("board feed: %w", err)
	}
	return posts(rows), nil
}

// Top is posts by these authors created since `since`: upvotes descending, then newest.
func (s *Store) Top(ctx context.Context, authors []uuid.UUID, since time.Time, limit int, viewer uuid.UUID) ([]Post, error) {
	rows, err := s.Q.BoardTop(ctx, sqlc.BoardTopParams{Viewer: viewer, Authors: authors, Since: since, RowLimit: int32(limit)}) //nolint:gosec // clamped
	if err != nil {
		return nil, fmt.Errorf("board top: %w", err)
	}
	return posts(rows), nil
}

// TitlePosts is posts about one title by these authors, newest first.
func (s *Store) TitlePosts(ctx context.Context, title uuid.UUID, authors []uuid.UUID, limit int, viewer uuid.UUID) ([]Post, error) {
	rows, err := s.Q.BoardTitlePosts(ctx, sqlc.BoardTitlePostsParams{
		Viewer: viewer, TitleID: &title, Authors: authors, RowLimit: int32(limit), //nolint:gosec // clamped
	})
	if err != nil {
		return nil, fmt.Errorf("board title posts: %w", err)
	}
	return posts(rows), nil
}

// EditPost replaces a live post's body.
func (s *Store) EditPost(ctx context.Context, id uuid.UUID, body string, now time.Time) error {
	if err := s.Q.BoardEditPost(ctx, sqlc.BoardEditPostParams{ID: id, Body: body, Now: now}); err != nil {
		return fmt.Errorf("edit board post: %w", err)
	}
	return nil
}

// DeletePost is a soft delete: the post vanishes from every read.
func (s *Store) DeletePost(ctx context.Context, id uuid.UUID, now time.Time) error {
	if err := s.Q.BoardDeletePost(ctx, sqlc.BoardDeletePostParams{ID: id, Now: now}); err != nil {
		return fmt.Errorf("delete board post: %w", err)
	}
	return nil
}

// SetUpvote is idempotent both ways.
func (s *Store) SetUpvote(ctx context.Context, post, user uuid.UUID, on bool) error {
	var err error
	if on {
		err = s.Q.BoardUpvote(ctx, sqlc.BoardUpvoteParams{PostID: post, UserID: user})
	} else {
		err = s.Q.BoardRemoveUpvote(ctx, sqlc.BoardRemoveUpvoteParams{PostID: post, UserID: user})
	}
	if err != nil {
		return fmt.Errorf("board upvote: %w", err)
	}
	return nil
}

// Upvoters are who upvoted a post, in the order they did.
func (s *Store) Upvoters(ctx context.Context, post uuid.UUID) ([]groups.User, error) {
	rows, err := s.Q.BoardUpvoters(ctx, post)
	if err != nil {
		return nil, fmt.Errorf("board upvoters: %w", err)
	}
	users := make([]groups.User, len(rows))
	for i, r := range rows {
		users[i] = groups.User{ID: r.UserID, Handle: r.Handle, DisplayName: r.DisplayName, AvatarVersion: r.AvatarVersion}
	}
	return users, nil
}

// AddComment stores a comment and returns it as given.
func (s *Store) AddComment(ctx context.Context, c Comment) (Comment, error) {
	params := sqlc.BoardInsertCommentParams{
		ID: c.ID, PostID: c.PostID, AuthorKind: "user", ReplyTo: c.ReplyTo, Body: c.Body, Mentions: c.Mentions,
		MentionsAgent: c.MentionsAgent, CreatedAt: c.CreatedAt,
	}
	if c.FromAgent {
		params.AuthorKind = "agent"
	}
	if c.Author != nil {
		id := c.Author.ID
		params.UserID = &id
	}
	if params.Mentions == nil {
		params.Mentions = []uuid.UUID{}
	}
	if err := s.Q.BoardInsertComment(ctx, params); err != nil {
		return Comment{}, fmt.Errorf("add board comment: %w", err)
	}
	return c, nil
}

// Comment is one comment on a post, deleted or not, or nil.
func (s *Store) Comment(ctx context.Context, id, post uuid.UUID) (*Comment, error) {
	row, err := s.Q.BoardComment(ctx, sqlc.BoardCommentParams{ID: id, PostID: post})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: no such comment
	}
	if err != nil {
		return nil, fmt.Errorf("board comment: %w", err)
	}
	c := commentFrom(row)
	return &c, nil
}

// Comments is oldest first and includes deleted comments (DeletedAt set); the service filters them.
func (s *Store) Comments(ctx context.Context, post uuid.UUID, after *uuid.UUID, limit int) ([]Comment, error) {
	rows, err := s.Q.BoardComments(ctx, sqlc.BoardCommentsParams{PostID: post, After: after, RowLimit: int32(limit)}) //nolint:gosec // clamped
	if err != nil {
		return nil, fmt.Errorf("board comments: %w", err)
	}
	out := make([]Comment, len(rows))
	for i, r := range rows {
		out[i] = commentFrom(sqlc.BoardCommentRow(r))
	}
	return out, nil
}

// DeleteComment is a soft delete.
func (s *Store) DeleteComment(ctx context.Context, id uuid.UUID, now time.Time) error {
	if err := s.Q.BoardDeleteComment(ctx, sqlc.BoardDeleteCommentParams{ID: id, Now: now}); err != nil {
		return fmt.Errorf("delete board comment: %w", err)
	}
	return nil
}
