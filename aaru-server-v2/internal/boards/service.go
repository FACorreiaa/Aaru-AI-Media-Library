package boards

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/library"
	"context"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Limits (BoardService.swift).
const (
	MaxBodyLength   = 4000
	DefaultPageSize = 20
	MaxPageSize     = 50
	TopLimit        = 10
	TopWindow       = 7 * 24 * time.Hour
)

// ErrNoSuchPost is the one 404 for a post: missing, deleted, someone else's all read the same.
var ErrNoSuchPost = apperr.NotFound("That post isn't here.")

var errOnlyAuthor = groups.Forbidden("Only the author can change this post.")

// Sort is the feed's order.
type Sort string

// The sorts: newest first, or this week by upvotes.
const (
	SortRecent Sort = "recent"
	SortTop    Sort = "top"
)

// Page is a page of posts and the ones this viewer should see behind a spoiler veil.
type Page struct {
	Posts  []Post
	Veiled map[uuid.UUID]bool
}

// TitleResolver turns a ref into a stored title (catalog.Resolver).
type TitleResolver interface {
	Resolve(ctx context.Context, ref core.MediaRef, searchHint *string) (core.Title, error)
}

// Service is the Board's rules.
type Service struct {
	Store    *Store
	Social   groups.Social
	Q        *sqlc.Queries
	Resolver TitleResolver
	Library  *library.Service
	Now      func() time.Time
}

// New builds the service over one set of queries.
func New(q *sqlc.Queries, resolver TitleResolver, lib *library.Service) *Service {
	return &Service{Store: &Store{Q: q}, Social: groups.Social{Q: q}, Q: q, Resolver: resolver, Library: lib, Now: time.Now}
}

func (s *Service) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

func pageSize(limit *int, def, maxSize int) int {
	size := def
	if limit != nil {
		size = *limit
	}
	return min(max(size, 1), maxSize)
}

// Feed is posts by the viewer's audience. `top` is the last seven days by upvotes and ignores
// before.
func (s *Service) Feed(ctx context.Context, sort Sort, before *uuid.UUID, limit *int, viewer uuid.UUID) (Page, error) {
	authors, err := s.audience(ctx, viewer)
	if err != nil {
		return Page{}, err
	}
	var posts []Post
	if sort == SortTop {
		posts, err = s.Store.Top(ctx, authors, s.now().Add(-TopWindow), TopLimit, viewer)
	} else {
		posts, err = s.Store.Feed(ctx, authors, before, pageSize(limit, DefaultPageSize, MaxPageSize), viewer)
	}
	if err != nil {
		return Page{}, err
	}
	return s.page(ctx, posts, viewer)
}

// TitlePosts is posts about one title by the viewer's audience, newest first.
func (s *Service) TitlePosts(ctx context.Context, title uuid.UUID, limit *int, viewer uuid.UUID) (Page, error) {
	authors, err := s.audience(ctx, viewer)
	if err != nil {
		return Page{}, err
	}
	posts, err := s.Store.TitlePosts(ctx, title, authors, pageSize(limit, DefaultPageSize, MaxPageSize), viewer)
	if err != nil {
		return Page{}, err
	}
	return s.page(ctx, posts, viewer)
}

func (s *Service) page(ctx context.Context, posts []Post, viewer uuid.UUID) (Page, error) {
	veiled, err := s.veiled(ctx, posts, viewer)
	if err != nil {
		return Page{}, err
	}
	return Page{Posts: posts, Veiled: veiled}, nil
}

// veiled are the posts whose spoiler stamp is ahead of the viewer's own progress. Progress is
// read once per title.
func (s *Service) veiled(ctx context.Context, posts []Post, viewer uuid.UUID) (map[uuid.UUID]bool, error) {
	progress := map[uuid.UUID]*groups.TitleProgress{}
	veiled := map[uuid.UUID]bool{}
	for _, p := range posts {
		if p.Spoiler == nil || p.TitleID == nil || p.Author.ID == viewer {
			continue
		}
		mine, read := progress[*p.TitleID]
		if !read {
			var err error
			if mine, err = groups.ProgressOf(ctx, s.Q, *p.TitleID, viewer); err != nil {
				return nil, err
			}
			progress[*p.TitleID] = mine
		}
		if groups.Veils(p.Spoiler, mine) {
			veiled[p.ID] = true
		}
	}
	return veiled, nil
}

// Create posts to the Board. A rating needs a title and is a library write: a new title lands as
// Watched, an existing one keeps its status.
func (s *Service) Create(
	ctx context.Context, body string, ref *core.MediaRef, rating *float64, spoiler groups.SpoilerChoice, viewer uuid.UUID,
) (Post, error) {
	// The store's reads join profiles: a post by someone without a handle would vanish.
	author, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return Post{}, err
	}
	body, err = ValidBody(body)
	if err != nil {
		return Post{}, err
	}
	// Validate before any catalog call.
	var stored *float64
	if rating != nil {
		if ref == nil {
			return Post{}, groups.Invalid("rating", "Pick the title you are rating.")
		}
		r, err := core.NewRating(*rating)
		if err != nil {
			return Post{}, err
		}
		value := r.Value()
		stored = &value
	}
	var title *core.Title
	if ref != nil {
		resolved, err := s.Resolver.Resolve(ctx, *ref, nil)
		if err != nil {
			return Post{}, err
		}
		title = &resolved
	}
	var stamp *groups.SpoilerStamp
	if title != nil {
		switch spoiler.Kind {
		case groups.SpoilerFree:
		case groups.SpoilerStamped:
			stamp = spoiler.Stamp
		case groups.SpoilerAuto:
			mine, err := groups.ProgressOf(ctx, s.Q, title.ID, viewer)
			if err != nil {
				return Post{}, err
			}
			stamp = groups.AutoStamp(mine)
		}
	}
	if ref != nil && title != nil && stored != nil {
		if err := s.rate(ctx, *ref, title.ID, *stored, viewer); err != nil {
			return Post{}, err
		}
	}
	post := Post{ID: uuid.New(), Author: author, Rating: stored, Body: body, Spoiler: stamp, CreatedAt: s.now()}
	if title != nil {
		id := title.ID
		post.TitleID = &id
	}
	return s.Store.CreatePost(ctx, post)
}

// rate writes the rating to the viewer's library item, adding the title as Watched first if new.
func (s *Service) rate(ctx context.Context, ref core.MediaRef, title uuid.UUID, rating float64, viewer uuid.UUID) error {
	existing, err := s.Library.ItemForTitle(ctx, viewer, title)
	if err != nil {
		return err
	}
	var itemID uuid.UUID
	if existing != nil {
		itemID = existing.Item.ID
	} else {
		finished := core.StatusFinished
		added, err := s.Library.Add(ctx, ref, &finished, viewer, library.UserCaller)
		if err != nil {
			return err
		}
		itemID = added.Item.ID
	}
	if _, err := s.Library.Patch(ctx, itemID, viewer, library.ItemPatch{Rating: &rating}, library.UserCaller); err != nil {
		return fmt.Errorf("rate from the board: %w", err)
	}
	return nil
}

// Post is one visible post and whether it is veiled for the viewer.
func (s *Service) Post(ctx context.Context, id, viewer uuid.UUID) (Post, bool, error) {
	found, err := s.RequireVisible(ctx, id, viewer)
	if err != nil {
		return Post{}, false, err
	}
	veiled, err := s.veiled(ctx, []Post{found}, viewer)
	if err != nil {
		return Post{}, false, err
	}
	return found, len(veiled) > 0, nil
}

// Edit replaces the body of the viewer's own post.
func (s *Service) Edit(ctx context.Context, id uuid.UUID, body string, viewer uuid.UUID) (Post, error) {
	original, err := s.RequireVisible(ctx, id, viewer)
	if err != nil {
		return Post{}, err
	}
	if original.Author.ID != viewer {
		return Post{}, errOnlyAuthor
	}
	body, err = ValidBody(body)
	if err != nil {
		return Post{}, err
	}
	if err := s.Store.EditPost(ctx, id, body, s.now()); err != nil {
		return Post{}, err
	}
	return s.RequireVisible(ctx, id, viewer)
}

// Delete removes the viewer's own post.
func (s *Service) Delete(ctx context.Context, id, viewer uuid.UUID) error {
	original, err := s.RequireVisible(ctx, id, viewer)
	if err != nil {
		return err
	}
	if original.Author.ID != viewer {
		return errOnlyAuthor
	}
	return s.Store.DeletePost(ctx, id, s.now())
}

// Upvote sets or clears the viewer's upvote on a visible post.
func (s *Service) Upvote(ctx context.Context, id uuid.UUID, on bool, viewer uuid.UUID) error {
	if _, err := s.RequireVisible(ctx, id, viewer); err != nil {
		return err
	}
	return s.Store.SetUpvote(ctx, id, viewer, on)
}

// Upvoters are who upvoted, minus anyone blocked in either direction with the viewer.
func (s *Service) Upvoters(ctx context.Context, id, viewer uuid.UUID) ([]groups.User, error) {
	if _, err := s.RequireVisible(ctx, id, viewer); err != nil {
		return nil, err
	}
	hidden, err := s.Social.BlockedEitherWay(ctx, viewer)
	if err != nil {
		return nil, err
	}
	all, err := s.Store.Upvoters(ctx, id)
	if err != nil {
		return nil, err
	}
	users := make([]groups.User, 0, len(all))
	for _, u := range all {
		if !hidden[u.ID] {
			users = append(users, u)
		}
	}
	return users, nil
}

// audience is the viewer and their friends, minus anyone blocked in either direction.
func (s *Service) audience(ctx context.Context, viewer uuid.UUID) ([]uuid.UUID, error) {
	friends, err := s.Social.Friends(ctx, viewer)
	if err != nil {
		return nil, err
	}
	hidden, err := s.Social.BlockedEitherWay(ctx, viewer)
	if err != nil {
		return nil, err
	}
	authors := []uuid.UUID{viewer}
	for _, f := range friends {
		if !hidden[f.ID] {
			authors = append(authors, f.ID)
		}
	}
	return authors, nil
}

// RequireVisible is a live post by the viewer, or by a friend neither side blocked; else the
// missing 404.
func (s *Service) RequireVisible(ctx context.Context, id, viewer uuid.UUID) (Post, error) {
	post, err := s.Store.Post(ctx, id, viewer)
	if err != nil {
		return Post{}, err
	}
	if post == nil {
		return Post{}, ErrNoSuchPost
	}
	if post.Author.ID == viewer {
		return *post, nil
	}
	friends, err := s.Social.AreFriends(ctx, viewer, post.Author.ID)
	if err != nil {
		return Post{}, err
	}
	if !friends {
		return Post{}, ErrNoSuchPost
	}
	blocked, err := s.Social.IsBlocked(ctx, viewer, post.Author.ID)
	if err != nil {
		return Post{}, err
	}
	if blocked {
		return Post{}, ErrNoSuchPost
	}
	return *post, nil
}

// ValidBody is a post or comment body, trimmed.
func ValidBody(raw string) (string, error) {
	body := strings.TrimFunc(raw, unicode.IsSpace)
	if body == "" {
		return "", groups.Invalid("body", "Write something first.")
	}
	if utf8.RuneCountInString(body) > MaxBodyLength {
		return "", groups.Invalid("body", fmt.Sprintf("Keep posts under %d characters.", MaxBodyLength))
	}
	return body, nil
}
