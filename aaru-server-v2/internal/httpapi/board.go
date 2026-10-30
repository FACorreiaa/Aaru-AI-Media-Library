package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/boards"
	"aaru-go-api/internal/core"
	"context"

	"github.com/google/uuid"
)

// Board routes (API/BoardHandlers.swift, BOARD-001). A malformed post id reads as uuid.Nil, which
// no post has: the missing post's 404.

// optionalID is a query cursor; a malformed one is no cursor at all, as Swift read it.
func optionalID(id *apiid.UUID) *uuid.UUID {
	if id == nil || id.ID() == uuid.Nil {
		return nil
	}
	v := id.ID()
	return &v
}

// ListBoard is GET /v1/board.
func (s *Server) ListBoard(ctx context.Context, req api.ListBoardRequestObject) (api.ListBoardResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	sort := boards.SortRecent
	if req.Params.Sort != nil && *req.Params.Sort == api.ListBoardParamsSortTop {
		sort = boards.SortTop
	}
	page, err := s.Boards.Feed(ctx, sort, optionalID(req.Params.Before), req.Params.Limit, viewer)
	if err != nil {
		return nil, err
	}
	items, err := s.boardPostsDTO(ctx, page.Posts, page.Veiled, viewer)
	if err != nil {
		return nil, err
	}
	return api.ListBoard200JSONResponse(api.BoardPostPage{Items: items}), nil
}

// ListTitlePosts is GET /v1/titles/{id}/posts.
func (s *Server) ListTitlePosts(ctx context.Context, req api.ListTitlePostsRequestObject) (api.ListTitlePostsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound("That title isn't here.")
	}
	page, err := s.Boards.TitlePosts(ctx, req.Id.ID(), req.Params.Limit, viewer)
	if err != nil {
		return nil, err
	}
	items, err := s.boardPostsDTO(ctx, page.Posts, page.Veiled, viewer)
	if err != nil {
		return nil, err
	}
	return api.ListTitlePosts200JSONResponse(api.BoardPostPage{Items: items}), nil
}

// CreateBoardPost is POST /v1/board/posts.
func (s *Server) CreateBoardPost(ctx context.Context, req api.CreateBoardPostRequestObject) (api.CreateBoardPostResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var ref *core.MediaRef
	if req.Body.Title != nil {
		r := MediaRefFromAPI(*req.Body.Title)
		ref = &r
	}
	choice, err := spoilerChoice(req.Body.Spoiler, req.Body.SpoilerFree)
	if err != nil {
		return nil, err
	}
	post, err := s.Boards.Create(ctx, req.Body.Body, ref, req.Body.Rating, choice, viewer)
	if err != nil {
		return nil, err
	}
	dto, err := s.boardPostDTO(ctx, post, false, viewer)
	if err != nil {
		return nil, err
	}
	return api.CreateBoardPost201JSONResponse(dto), nil
}

// GetBoardPost is GET /v1/board/posts/{postId}.
func (s *Server) GetBoardPost(ctx context.Context, req api.GetBoardPostRequestObject) (api.GetBoardPostResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	post, veiled, err := s.Boards.Post(ctx, req.PostId.ID(), viewer)
	if err != nil {
		return nil, err
	}
	dto, err := s.boardPostDTO(ctx, post, veiled, viewer)
	if err != nil {
		return nil, err
	}
	return api.GetBoardPost200JSONResponse(dto), nil
}

// EditBoardPost is PATCH /v1/board/posts/{postId}.
func (s *Server) EditBoardPost(ctx context.Context, req api.EditBoardPostRequestObject) (api.EditBoardPostResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	post, err := s.Boards.Edit(ctx, req.PostId.ID(), req.Body.Body, viewer)
	if err != nil {
		return nil, err
	}
	dto, err := s.boardPostDTO(ctx, post, false, viewer)
	if err != nil {
		return nil, err
	}
	return api.EditBoardPost200JSONResponse(dto), nil
}

// DeleteBoardPost is DELETE /v1/board/posts/{postId}.
func (s *Server) DeleteBoardPost(ctx context.Context, req api.DeleteBoardPostRequestObject) (api.DeleteBoardPostResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Boards.Delete(ctx, req.PostId.ID(), viewer); err != nil {
		return nil, err
	}
	return api.DeleteBoardPost204Response{}, nil
}

// UpvoteBoardPost is PUT /v1/board/posts/{postId}/upvote.
func (s *Server) UpvoteBoardPost(ctx context.Context, req api.UpvoteBoardPostRequestObject) (api.UpvoteBoardPostResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Boards.Upvote(ctx, req.PostId.ID(), true, viewer); err != nil {
		return nil, err
	}
	return api.UpvoteBoardPost204Response{}, nil
}

// RemoveBoardPostUpvote is DELETE /v1/board/posts/{postId}/upvote.
func (s *Server) RemoveBoardPostUpvote(ctx context.Context, req api.RemoveBoardPostUpvoteRequestObject) (api.RemoveBoardPostUpvoteResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Boards.Upvote(ctx, req.PostId.ID(), false, viewer); err != nil {
		return nil, err
	}
	return api.RemoveBoardPostUpvote204Response{}, nil
}

// ListBoardPostUpvoters is GET /v1/board/posts/{postId}/upvotes.
func (s *Server) ListBoardPostUpvoters(ctx context.Context, req api.ListBoardPostUpvotersRequestObject) (api.ListBoardPostUpvotersResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	users, err := s.Boards.Upvoters(ctx, req.PostId.ID(), viewer)
	if err != nil {
		return nil, err
	}
	return api.ListBoardPostUpvoters200JSONResponse(api.SocialUserList{Items: groupUsersDTO(users)}), nil
}

// ListBoardComments is GET /v1/board/posts/{postId}/comments.
func (s *Server) ListBoardComments(ctx context.Context, req api.ListBoardCommentsRequestObject) (api.ListBoardCommentsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	page, err := s.Boards.Comments(ctx, req.PostId.ID(), optionalID(req.Params.After), req.Params.Limit, viewer)
	if err != nil {
		return nil, err
	}
	items := make([]api.BoardComment, len(page.Items))
	for i, c := range page.Items {
		items[i] = boardCommentDTO(c, viewer)
	}
	return api.ListBoardComments200JSONResponse(api.BoardCommentPage{Items: items, Next: apiid.PtrOrNil(page.Next)}), nil
}

// CreateBoardComment is POST /v1/board/posts/{postId}/comments.
func (s *Server) CreateBoardComment(ctx context.Context, req api.CreateBoardCommentRequestObject) (api.CreateBoardCommentResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var replyTo *uuid.UUID
	if req.Body.ReplyTo != nil {
		// A malformed id is a comment that isn't here.
		if req.Body.ReplyTo.ID() == uuid.Nil {
			return nil, boards.ErrNoReplyTarget
		}
		id := req.Body.ReplyTo.ID()
		replyTo = &id
	}
	comment, err := s.Boards.AddComment(ctx, req.PostId.ID(), req.Body.Body, replyTo, viewer)
	if err != nil {
		return nil, err
	}
	return api.CreateBoardComment201JSONResponse(boardCommentDTO(comment, viewer)), nil
}

// DeleteBoardComment is DELETE /v1/board/posts/{postId}/comments/{commentId}.
func (s *Server) DeleteBoardComment(ctx context.Context, req api.DeleteBoardCommentRequestObject) (api.DeleteBoardCommentResponseObject, error) {
	if req.CommentId.ID() == uuid.Nil {
		return nil, boards.ErrNoSuchComment
	}
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Boards.DeleteComment(ctx, req.PostId.ID(), req.CommentId.ID(), viewer); err != nil {
		return nil, err
	}
	return api.DeleteBoardComment204Response{}, nil
}

func (s *Server) boardPostDTO(ctx context.Context, post boards.Post, veiled bool, viewer uuid.UUID) (api.BoardPost, error) {
	items, err := s.boardPostsDTO(ctx, []boards.Post{post}, map[uuid.UUID]bool{post.ID: veiled}, viewer)
	if err != nil {
		return api.BoardPost{}, err
	}
	return items[0], nil
}

// boardPostsDTO hydrates the titles in one batch.
func (s *Server) boardPostsDTO(ctx context.Context, posts []boards.Post, veiled map[uuid.UUID]bool, viewer uuid.UUID) ([]api.BoardPost, error) {
	seen := map[uuid.UUID]bool{}
	var ids []uuid.UUID
	for _, p := range posts {
		if p.TitleID != nil && !seen[*p.TitleID] {
			seen[*p.TitleID] = true
			ids = append(ids, *p.TitleID)
		}
	}
	byID := map[uuid.UUID]core.Title{}
	if len(ids) > 0 {
		titles, err := s.Catalog.Store.Titles(ctx, ids)
		if err != nil {
			return nil, err
		}
		for _, t := range titles {
			if _, ok := byID[t.ID]; !ok {
				byID[t.ID] = t
			}
		}
	}
	out := make([]api.BoardPost, len(posts))
	for i, p := range posts {
		dto := api.BoardPost{
			Id: apiid.From(p.ID), Author: groupUserDTO(p.Author), Rating: p.Rating, Body: p.Body,
			CreatedAt: apitime.From(p.CreatedAt), EditedAt: apitime.PtrOrNil(p.EditedAt), Upvotes: p.Upvotes,
			UpvotedByMe: p.UpvotedByViewer, CommentCount: p.CommentCount, Veiled: veiled[p.ID], Mine: p.Author.ID == viewer,
		}
		if p.TitleID != nil {
			if t, ok := byID[*p.TitleID]; ok {
				summary := TitleSummaryDTO(t)
				dto.Title = &summary
			}
		}
		// The stamp says where the author is in the title, so only the author sees it.
		if p.Author.ID == viewer {
			dto.Spoiler = spoilerStampDTO(p.Spoiler)
		}
		out[i] = dto
	}
	return out, nil
}

// boardCommentDTO: a deleted row only holds the thread together: no author, body or mentions.
func boardCommentDTO(c boards.Comment, viewer uuid.UUID) api.BoardComment {
	gone := c.DeletedAt != nil
	mine := c.Author != nil && c.Author.ID == viewer
	dto := api.BoardComment{
		Id: apiid.From(c.ID), PostId: apiid.From(c.PostID), Body: c.Body, Mentions: apiid.Slice(c.Mentions),
		MentionsAgent: c.MentionsAgent, Deleted: gone, CreatedAt: apitime.From(c.CreatedAt), FromAgent: c.FromAgent,
		ReplyTo: apiid.PtrOrNil(c.ReplyTo), Mine: &mine,
	}
	if c.Author != nil && !gone {
		author := groupUserDTO(*c.Author)
		dto.Author = &author
	}
	if gone {
		dto.Body, dto.Mentions, dto.MentionsAgent = "", []apiid.UUID{}, false
	}
	return dto
}
