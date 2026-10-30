package httpapi

// TODO(listens): the listening-history file upload (MUS-004) on `POST /v1/imports/csv`. The
// listens port replaces this file.

import (
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

// createListenFileImport is a Spotify or YouTube listening history file (application/octet-stream).
func (s *Server) createListenFileImport(c echo.Context, user uuid.UUID, asked string, filename *string) error {
	_, _, _, _ = c, user, asked, filename
	return errNotImplemented
}
