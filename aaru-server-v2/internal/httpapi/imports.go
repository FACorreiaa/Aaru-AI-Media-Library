package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"context"
	"errors"
	"io"
	"mime"
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"
)

// ImportHandlers.swift: file and account imports, the plan, approval and row triage.

func (s *Server) ListImports(ctx context.Context, _ api.ListImportsRequestObject) (api.ListImportsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	jobs, err := s.Imports.Jobs(ctx, user)
	if err != nil {
		return nil, err
	}
	items := make([]importJobJSON, len(jobs))
	for i, j := range jobs {
		items[i] = importJobOut(j)
	}
	return importListJSON{Items: items}, nil
}

func (s *Server) GetImport(ctx context.Context, req api.GetImportRequestObject) (api.GetImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	job, rows, err := s.Imports.Detail(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	out := make([]api.ImportRow, len(rows))
	for i, r := range rows {
		out[i] = ImportRowDTO(r)
	}
	return importDetailJSON{Job: importJobOut(job), Rows: out}, nil
}

func (s *Server) DeleteImport(ctx context.Context, req api.DeleteImportRequestObject) (api.DeleteImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Imports.Delete(ctx, req.Id.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteImport204Response{}, nil
}

func (s *Server) ApplyImport(ctx context.Context, req api.ApplyImportRequestObject) (api.ApplyImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	job, err := s.Imports.Apply(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return importJobOut(job), nil
}

func (s *Server) ResolveImportRow(ctx context.Context, req api.ResolveImportRowRequestObject) (api.ResolveImportRowResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	job, row, err := s.Imports.ResolveRow(ctx, req.Id.ID(), req.Index, MediaRefFromAPI(req.Body.MediaRef), user)
	if err != nil {
		return nil, err
	}
	return importResolvedJSON{Job: importJobOut(job), Row: ImportRowDTO(row)}, nil
}

func (s *Server) CreateAniListImport(ctx context.Context, req api.CreateAniListImportRequestObject) (api.CreateAniListImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	job, err := s.Imports.CreateAniListImport(ctx, user, req.Body.Username)
	if err != nil {
		return nil, err
	}
	return api.CreateAniListImport202JSONResponse(ImportJobDTO(job)), nil
}

func (s *Server) CreateTraktImport(ctx context.Context, _ api.CreateTraktImportRequestObject) (api.CreateTraktImportResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	job, err := s.Imports.CreateTraktImport(ctx, user)
	if err != nil {
		return nil, err
	}
	return api.CreateTraktImport202JSONResponse(ImportJobDTO(job)), nil
}

// MARK: Raw routes: bodies in several binary types

// errUnreadable is what the Swift server's OpenAPI layer answered for a body of a type the route
// does not list (415, through ErrorMiddleware's ServerError branch).
var errUnreadable = apperr.FromStatus(http.StatusUnsupportedMediaType, "The request could not be read.")

// errFileTooLarge is an export over 5 MB.
var errFileTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large",
	"That file is larger than 5 MB. Exports are usually much smaller; check it is the right file.")

// contentType is the request's media type, lowercased, without parameters.
func contentType(c echo.Context) string {
	mt, _, err := mime.ParseMediaType(c.Request().Header.Get("Content-Type"))
	if err != nil {
		return ""
	}
	return strings.ToLower(mt)
}

// readUpload is an upload's bytes up to limit. An oversized one is refused from its declared
// length, before a byte is read; one that turns out larger is refused once limit is passed.
func readUpload(c echo.Context, limit int64, tooLarge error) ([]byte, error) {
	req := c.Request()
	if req.ContentLength > limit {
		return nil, tooLarge
	}
	data, err := io.ReadAll(io.LimitReader(req.Body, limit+1))
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			return nil, tooLarge
		}
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, tooLarge
	}
	return data, nil
}

// uploadText is an upload's text, decoded as UTF-8 with invalid bytes replaced, as Swift's
// String(decoding:as:) did.
func uploadText(c echo.Context) (string, error) {
	data, err := readUpload(c, imports.MaxUploadBytes, errFileTooLarge)
	if err != nil {
		return "", err
	}
	return strings.ToValidUTF8(string(data), "�"), nil
}

func optionalQuery(c echo.Context, name string) *string {
	if _, ok := c.QueryParams()[name]; !ok {
		return nil
	}
	v := c.QueryParam(name)
	return &v
}

// createCSVImport is `POST /v1/imports/csv`: a text export (text/csv, application/xml) or, as
// application/octet-stream, a listening history file (MUS-004).
func (s *Server) createCSVImport(c echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	asked := c.QueryParam("source")
	filename := optionalQuery(c, "filename")
	switch contentType(c) {
	case "text/csv", "application/xml":
	case "application/octet-stream":
		return s.createListenFileImport(c, user, asked, filename)
	default:
		return errUnreadable
	}
	text, err := uploadText(c)
	if err != nil {
		return err
	}
	source, err := fileSource(asked, text)
	if err != nil {
		return err
	}
	job, err := s.Imports.CreateCSVImport(ctx, user, source, filename, text)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusAccepted, ImportJobDTO(job))
}

// fileSource is a text export's source: the one asked for, or what `auto` detects.
func fileSource(asked, text string) (core.ImportSource, error) {
	switch asked {
	case "imdb":
		return core.SourceIMDbCSV, nil
	case "letterboxd":
		return core.SourceLetterboxdCSV, nil
	case "netflix":
		return core.SourceNetflixCSV, nil
	case "tvtime":
		return core.SourceTVTimeCSV, nil
	case "goodreads":
		return core.SourceGoodreadsCSV, nil
	case "mal":
		return core.SourceMALXML, nil
	case "csv":
		return core.SourceGenericCSV, nil
	case "spotify", "youtube":
		return "", apperr.Validation("file", "Send Spotify and YouTube history as the JSON file itself, not as a CSV.").
			WithDetails(map[string]string{"file": "Send the JSON file itself."})
	case "auto":
		source, err := imports.DetectFormat(text)
		if err != nil {
			var format *imports.FormatError
			if errors.As(err, &format) {
				return "", apperr.Validation("file", format.Message)
			}
			return "", err
		}
		return source, nil
	}
	return "", apperr.BadRequest()
}

// createCATImport is `POST /v1/imports/cat`: a pasted CAT list (text/plain) or its calendar file
// (text/calendar).
func (s *Server) createCATImport(c echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	switch contentType(c) {
	case "text/plain", "text/calendar":
	default:
		return errUnreadable
	}
	text, err := uploadText(c)
	if err != nil {
		return err
	}
	job, err := s.Imports.CreateCATImport(ctx, user, text)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusAccepted, ImportJobDTO(job))
}

// MARK: DTOs

// ImportJobDTO is a job on the wire. `ignored` is listening history's only.
func ImportJobDTO(job core.ImportJob) api.ImportJob {
	stats := api.ImportStats{
		Created: job.Stats.Created, Updated: job.Stats.Updated, Skipped: job.Stats.Skipped, Unmatched: job.Stats.Unmatched,
	}
	if job.Source.IsListens() {
		ignored := job.Stats.Ignored
		stats.Ignored = &ignored
	}
	return api.ImportJob{
		Id: apiid.From(job.ID), Source: api.ImportJobSource(job.Source), State: api.ImportJobState(job.State),
		Stats: stats, ErrorSummary: job.ErrorSummary, Filename: job.Filename,
		CreatedAt: apitime.From(job.CreatedAt), UpdatedAt: apitime.From(job.UpdatedAt),
		RowsTotal: job.RowsTotal, RowsMatched: job.RowsMatched, ActionId: apiid.PtrOrNil(job.ActionID),
	}
}

// importJobJSON is a job as Swift's ImportHandlers wrote it once applied: `actionId` lowercase
// (`uuidString.lowercased()`), every other id uppercase. The generated type writes it uppercase,
// so this shadows the field. A job is only given an action by approval, so only the responses
// that can carry one (list, detail, apply, resolve) use it.
type importJobJSON struct {
	api.ImportJob
	ActionId *string `json:"actionId,omitempty"` //nolint:revive // mirrors the generated field
}

func importJobOut(job core.ImportJob) importJobJSON {
	out := importJobJSON{ImportJob: ImportJobDTO(job)}
	if job.ActionID != nil {
		id := strings.ToLower(job.ActionID.String())
		out.ActionId = &id
	}
	return out
}

func (j importJobJSON) VisitApplyImportResponse(w http.ResponseWriter) error { return writeJSON(w, j) }

type importListJSON struct {
	Items []importJobJSON `json:"items"`
}

func (l importListJSON) VisitListImportsResponse(w http.ResponseWriter) error { return writeJSON(w, l) }

type importDetailJSON struct {
	Job  importJobJSON   `json:"job"`
	Rows []api.ImportRow `json:"rows"`
}

func (d importDetailJSON) VisitGetImportResponse(w http.ResponseWriter) error { return writeJSON(w, d) }

type importResolvedJSON struct {
	Job importJobJSON `json:"job"`
	Row api.ImportRow `json:"row"`
}

func (r importResolvedJSON) VisitResolveImportRowResponse(w http.ResponseWriter) error {
	return writeJSON(w, r)
}

// ImportRowDTO is a planned row on the wire.
func ImportRowDTO(p imports.PlannedRow) api.ImportRow {
	row := p.Row
	ids := ExternalIDsDTO(row.IDs)
	out := api.ImportRow{
		Index: p.Index, Title: row.Title, Year: row.Year, Author: row.Author, Type: api.MediaType(row.Type),
		SourceKey: row.SourceKey, Ids: &ids, Rating: row.Rating, Outcome: api.ImportRowOutcome(p.Outcome),
		Reason: p.Reason, TitleId: apiid.PtrOrNil(p.TitleID),
	}
	if row.Status != nil {
		status := api.LibraryStatus(*row.Status)
		out.Status = &status
	}
	return out
}
