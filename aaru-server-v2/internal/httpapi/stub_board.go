// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListBoard(context.Context, api.ListBoardRequestObject) (api.ListBoardResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateBoardPost(context.Context, api.CreateBoardPostRequestObject) (api.CreateBoardPostResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteBoardPost(context.Context, api.DeleteBoardPostRequestObject) (api.DeleteBoardPostResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetBoardPost(context.Context, api.GetBoardPostRequestObject) (api.GetBoardPostResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) EditBoardPost(context.Context, api.EditBoardPostRequestObject) (api.EditBoardPostResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListBoardComments(context.Context, api.ListBoardCommentsRequestObject) (api.ListBoardCommentsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateBoardComment(context.Context, api.CreateBoardCommentRequestObject) (api.CreateBoardCommentResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteBoardComment(context.Context, api.DeleteBoardCommentRequestObject) (api.DeleteBoardCommentResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RemoveBoardPostUpvote(context.Context, api.RemoveBoardPostUpvoteRequestObject) (api.RemoveBoardPostUpvoteResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UpvoteBoardPost(context.Context, api.UpvoteBoardPostRequestObject) (api.UpvoteBoardPostResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListBoardPostUpvoters(context.Context, api.ListBoardPostUpvotersRequestObject) (api.ListBoardPostUpvotersResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListTitlePosts(context.Context, api.ListTitlePostsRequestObject) (api.ListTitlePostsResponseObject, error) {
	return nil, errNotImplemented
}
