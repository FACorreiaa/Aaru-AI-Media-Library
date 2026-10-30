package httpapi

// MUS-004 · listening history imports (ImportHandlers.swift: createListenFileImport,
// createLastFMImport, createListenBrainzImport, undoListenImport).

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"context"
	"net/http"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

// errListenFileTooLarge is a listening file over 24 MB.
var errListenFileTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large",
	"That file is larger than 24 MB, the most Aaru reads at once. Spotify splits its history into "+
		"smaller files: add them one at a time.")

// createListenFileImport is a Spotify or YouTube listening history file (application/octet-stream
// on `POST /v1/imports/csv`). Bigger than an export, so its own limit.
func (s *Server) createListenFileImport(c echo.Context, user uuid.UUID, asked string, filename *string) error {
	var source *core.ImportSource
	switch asked {
	case "spotify":
		v := core.SourceSpotifyJSON
		source = &v
	case "youtube":
		v := core.SourceYouTubeTakeout
		source = &v
	case "auto":
	case "imdb", "letterboxd", "netflix", "tvtime", "goodreads", "mal", "csv":
		return apperr.Validation("file", "Only Spotify and YouTube history are JSON. Send other exports as CSV or XML.").
			WithDetails(map[string]string{"file": "Only Spotify and YouTube history are JSON."})
	default:
		return apperr.BadRequest()
	}
	data, err := readUpload(c, imports.MaxListenUploadBytes, errListenFileTooLarge)
	if err != nil {
		return err
	}
	job, err := s.Imports.CreateListenFileImport(c.Request().Context(), user, source, filename, data)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusAccepted, ImportJobDTO(job))
}

func (s *Server) CreateLastFMImport(ctx context.Context, req api.CreateLastFMImportRequestObject) (api.CreateLastFMImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	job, err := s.Imports.CreateListenAccountImport(ctx, user, core.SourceLastFM, req.Body.Username)
	if err != nil {
		return nil, err
	}
	return api.CreateLastFMImport202JSONResponse(ImportJobDTO(job)), nil
}

func (s *Server) CreateListenBrainzImport(ctx context.Context, req api.CreateListenBrainzImportRequestObject) (api.CreateListenBrainzImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	job, err := s.Imports.CreateListenAccountImport(ctx, user, core.SourceListenBrainz, req.Body.Username)
	if err != nil {
		return nil, err
	}
	return api.CreateListenBrainzImport202JSONResponse(ImportJobDTO(job)), nil
}

func (s *Server) UndoListenImport(ctx context.Context, req api.UndoListenImportRequestObject) (api.UndoListenImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Imports.UndoListens(ctx, req.Id.ID(), user); err != nil {
		return nil, err
	}
	return api.UndoListenImport204Response{}, nil
}
