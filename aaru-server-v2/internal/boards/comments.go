package boards

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/groups"
	"context"

	"github.com/google/uuid"
)

// Comment page sizes (BoardService+Comments.swift).
const (
	DefaultCommentPageSize = 50
	MaxCommentPageSize     = 100
)

// ErrNoSuchComment: missing, deleted, or by someone blocked either way.
var ErrNoSuchComment = apperr.NotFound("That comment isn't here.")

// ErrNoReplyTarget: a reply to a comment that is not there (or not for this viewer).
var ErrNoReplyTarget = groups.Invalid("replyTo", "That comment isn't here.")

// CommentPage is a page of comments and the cursor for the next one.
type CommentPage struct {
	Items []Comment
	// Next is the id of the last row the store scanned, filtered or not; nil when that was the end.
	Next *uuid.UUID
}

// Comments are oldest first, minus anyone blocked in either direction with the viewer. A deleted
// comment with live replies on this page stays as a DeletedAt row (the DTO blanks it); one
// without is dropped. The store pages over deleted and blocked rows too, so a page can come back
// shorter than limit (even empty): follow Next, not the item count. A deleted parent whose
// replies sit on a later page is dropped.
func (s *Service) Comments(ctx context.Context, post uuid.UUID, after *uuid.UUID, limit *int, viewer uuid.UUID) (CommentPage, error) {
	if _, err := s.RequireVisible(ctx, post, viewer); err != nil {
		return CommentPage{}, err
	}
	size := pageSize(limit, DefaultCommentPageSize, MaxCommentPageSize)
	hidden, err := s.Social.BlockedEitherWay(ctx, viewer)
	if err != nil {
		return CommentPage{}, err
	}
	scanned, err := s.Store.Comments(ctx, post, after, size)
	if err != nil {
		return CommentPage{}, err
	}
	rows := make([]Comment, 0, len(scanned))
	answered := map[uuid.UUID]bool{}
	for _, c := range scanned {
		if c.Author != nil && hidden[c.Author.ID] {
			continue
		}
		rows = append(rows, c)
		if c.DeletedAt == nil && c.ReplyTo != nil {
			answered[*c.ReplyTo] = true
		}
	}
	items := make([]Comment, 0, len(rows))
	for _, c := range rows {
		if c.DeletedAt == nil || answered[c.ID] {
			items = append(items, c)
		}
	}
	page := CommentPage{Items: items}
	if len(scanned) >= size && len(scanned) > 0 {
		last := scanned[len(scanned)-1].ID
		page.Next = &last
	}
	return page, nil
}

// liveComment is a comment this viewer can act on: live, on this post, and not by anyone blocked
// either way.
func (s *Service) liveComment(ctx context.Context, id, post, viewer uuid.UUID) (*Comment, error) {
	found, err := s.Store.Comment(ctx, id, post)
	if err != nil || found == nil || found.DeletedAt != nil {
		return nil, err
	}
	if found.Author != nil {
		hidden, err := s.Social.BlockedEitherWay(ctx, viewer)
		if err != nil {
			return nil, err
		}
		if hidden[found.Author.ID] {
			return nil, nil //nolint:nilnil // nil: hidden reads as missing
		}
	}
	return found, nil
}

// AddComment comments on a visible post. A reply to a reply hangs off the top-level comment.
func (s *Service) AddComment(ctx context.Context, post uuid.UUID, body string, replyTo *uuid.UUID, viewer uuid.UUID) (Comment, error) {
	found, err := s.RequireVisible(ctx, post, viewer)
	if err != nil {
		return Comment{}, err
	}
	author, err := s.Social.RequireHandle(ctx, viewer)
	if err != nil {
		return Comment{}, err
	}
	body, err = ValidBody(body)
	if err != nil {
		return Comment{}, err
	}
	var parent *uuid.UUID
	if replyTo != nil {
		target, err := s.liveComment(ctx, *replyTo, post, viewer)
		if err != nil {
			return Comment{}, err
		}
		if target == nil {
			return Comment{}, ErrNoReplyTarget
		}
		// Nesting stays one level: a reply to a reply hangs off the top-level comment.
		top := target.ID
		if target.ReplyTo != nil {
			top = *target.ReplyTo
		}
		parent = &top
	}
	// Mentions notify the post's audience: its author and the author's friends, so a commenter
	// can't reach someone the post never showed to.
	hidden, err := s.Social.BlockedEitherWay(ctx, viewer)
	if err != nil {
		return Comment{}, err
	}
	authorHidden, err := s.Social.BlockedEitherWay(ctx, found.Author.ID)
	if err != nil {
		return Comment{}, err
	}
	friends, err := s.Social.Friends(ctx, found.Author.ID)
	if err != nil {
		return Comment{}, err
	}
	candidates := make([]groups.User, 0, len(friends)+1)
	for _, f := range friends {
		if !hidden[f.ID] && !authorHidden[f.ID] {
			candidates = append(candidates, f)
		}
	}
	candidates = append(candidates, found.Author)
	mentioned, agent := groups.Mentions(body, candidates)
	mentions := make([]uuid.UUID, 0, len(mentioned))
	for _, id := range mentioned {
		if id != viewer {
			mentions = append(mentions, id)
		}
	}
	return s.Store.AddComment(ctx, Comment{
		ID: uuid.New(), PostID: post, Author: &author, ReplyTo: parent, Body: body, Mentions: mentions,
		MentionsAgent: agent, CreatedAt: s.now(),
	})
}

// DeleteComment is for the comment's author or the post's author.
func (s *Service) DeleteComment(ctx context.Context, post, id, viewer uuid.UUID) error {
	found, err := s.RequireVisible(ctx, post, viewer)
	if err != nil {
		return err
	}
	target, err := s.liveComment(ctx, id, post, viewer)
	if err != nil {
		return err
	}
	if target == nil {
		return ErrNoSuchComment
	}
	if (target.Author == nil || target.Author.ID != viewer) && found.Author.ID != viewer {
		return groups.Forbidden("Only the comment's author or the post's author can delete it.")
	}
	return s.Store.DeleteComment(ctx, id, s.now())
}
