package imports

// AG-006 · capture as an import source (ImportService+Capture.swift). A link is read on the
// request (by its URL alone); text and images are read by the worker through the model, then
// planned like any other import.

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/telemetry"
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// CaptureDeps are what reading a capture needs (AG-006). The inputs store is always there (over
// the job store's queries); the model is nil when ANTHROPIC_API_KEY is unset.
type CaptureDeps struct {
	// Model reads text and images; nil turns them off (links still work).
	Model model.Provider
	// Usage meters each model call in `agent_usage`; nil meters nothing.
	Usage capture.UsageRecorder
}

// The capture limits Swift's ImportService kept.
const (
	// CapturesPerDay is fair use: captures one account may start in a UTC day. It keeps one account
	// from running up the bill. There is no monthly limit while Plus is off sale (BIL-005).
	CapturesPerDay = 30
	// MaxCaptureText is the longest pasted text a capture reads, in characters: a long chat fits.
	MaxCaptureText = 100000
	// MaxCaptureImages is how many pictures one capture reads (BOOK-001).
	MaxCaptureImages = 5
	// MaxCaptureImageBytes is one capture's pictures together. In base64 it stays well inside the
	// Messages API's 32 MB request limit.
	MaxCaptureImageBytes = 15 * 1024 * 1024
)

// CaptureImageTypes are the image types the model reads. Clients send JPEG; the others are what
// the Messages API also takes.
var CaptureImageTypes = map[string]bool{"image/jpeg": true, "image/png": true, "image/gif": true, "image/webp": true}

// CaptureRequest is what a capture sent: exactly one of text, a link, or images.
type CaptureRequest struct {
	Text *string
	Link *string
	// Images are set for pictures: at least one, in order.
	Images []model.Image
	// Only narrows text and images to one kind (BOOK-001). A link names its own kind.
	Only core.MediaType
}

// kind is the product event's `kind`.
func (r CaptureRequest) kind() string {
	switch {
	case r.Text != nil:
		return "text"
	case r.Link != nil:
		return "url"
	}
	return "image"
}

// CaptureStore is the capture inputs, over the job store's queries.
func (s *Service) CaptureStore() *capture.Store { return &capture.Store{Q: s.Store.Q} }

// CreateCapture starts a capture: a link's row now, or the text or image the worker gives the model.
func (s *Service) CreateCapture(ctx context.Context, user uuid.UUID, req CaptureRequest) (core.ImportJob, error) {
	jobID := uuid.New()
	rows, input, err := captureContent(req)
	if err != nil {
		return core.ImportJob{}, err
	}
	if input != nil && s.Capture.Model == nil {
		return core.ImportJob{}, apperr.New(http.StatusServiceUnavailable, "capture_unavailable",
			"Aaru cannot read captures right now. A link to the title still works.")
	}
	now := s.now()
	job := newJob(user, core.SourceCapture, nil, now)
	job.ID = jobID
	job.RowsTotal = len(rows)
	// Count and insert under the user's capture lock, in one transaction: parallel captures queue
	// behind it, so the quota holds (DB-004).
	err = pgx.BeginFunc(ctx, s.Store.Pool, func(tx pgx.Tx) error {
		if err := s.Store.LockUserCaptures(ctx, tx, user); err != nil {
			return err
		}
		q := s.Store.Q.WithTx(tx)
		if err := s.checkCaptureQuota(ctx, q, user); err != nil {
			return err
		}
		if input != nil {
			store := &capture.Store{Q: q}
			if err := store.Save(ctx, capture.Input{JobID: jobID, UserID: user, Content: *input, CreatedAt: now}); err != nil {
				return err
			}
		}
		return s.Store.InsertTx(ctx, tx, job, rows)
	})
	if err != nil {
		return core.ImportJob{}, err
	}
	telemetry.Capture(telemetry.CaptureSubmitted, user, map[string]string{"kind": req.kind()})
	return job, nil
}

// captureContent is a link's row, read from the URL now; or the text or image for the worker.
func captureContent(req CaptureRequest) ([]Row, *capture.Content, error) {
	switch {
	case req.Link != nil:
		link := capture.ParseLink(strings.TrimSpace(*req.Link))
		switch link.Kind {
		case capture.LinkTitle:
			return []Row{captureRow(*link.Title)}, nil, nil
		case capture.LinkUseCSV:
			return nil, nil, apperr.New(http.StatusUnprocessableEntity, "capture_use_csv",
				"Aaru does not read "+link.Site+" pages. Export your "+link.Site+" list as a CSV and import it instead: "+
					"it brings everything at once.")
		case capture.LinkUnsupported:
		}
		return nil, nil, apperr.New(http.StatusUnprocessableEntity, "capture_unsupported_url",
			"Aaru reads links to a title on TMDB, AniList or Open Library. For anything else, send a "+
				"screenshot or paste the names.")
	case req.Text != nil:
		text := strings.TrimSpace(*req.Text)
		if text == "" {
			return nil, nil, apperr.Validation("text", "There is nothing to read.").
				WithDetails(map[string]string{"text": "Empty."})
		}
		if core.Length(text) > MaxCaptureText {
			return nil, nil, apperr.New(http.StatusRequestEntityTooLarge, "capture_too_large",
				"That is more text than a capture reads. Paste a shorter list, or use an import.")
		}
		return nil, &capture.Content{Text: text, Only: req.Only}, nil
	}
	if len(req.Images) == 0 {
		return nil, nil, apperr.Validation("image", "There is nothing to read.").
			WithDetails(map[string]string{"image": "No picture."})
	}
	for _, image := range req.Images {
		if !CaptureImageTypes[image.MediaType] {
			return nil, nil, apperr.New(http.StatusUnsupportedMediaType, "capture_image_type",
				"Send the image as a JPEG, PNG, GIF or WebP.")
		}
	}
	first := req.Images[0]
	return nil, &capture.Content{Image: first.Data, MediaType: first.MediaType, More: req.Images[1:], Only: req.Only}, nil
}

// captureRow is a captured title as a row to plan: always a wishlist add. A book's author says more
// than its year, which is often an edition's where the catalog has the first (BOOK-001).
func captureRow(t capture.Title) Row {
	year := t.Year
	if t.Type == core.MediaBook && t.Author != nil {
		year = nil
	}
	return Row{
		SourceKey: t.SourceKey, Type: t.Type, Title: t.Title, Year: year, IDs: t.IDs, Author: t.Author,
		Status: ptr(core.StatusWishlist), Lists: []string{},
	}
}

// checkCaptureQuota is fair use, for every account: past CapturesPerDay in a UTC day, a 429.
func (s *Service) checkCaptureQuota(ctx context.Context, q *sqlc.Queries, user uuid.UUID) error {
	today, err := (&capture.Store{Q: q}).Captures(ctx, user, DayStart(s.now()))
	if err != nil {
		return err
	}
	if today < CapturesPerDay {
		return nil
	}
	return apperr.New(http.StatusTooManyRequests, "capture_fair_use",
		"Aaru reads "+strconv.Itoa(CapturesPerDay)+" captures a day. More tomorrow.")
}

// DayStart is the start of t's UTC day.
func DayStart(t time.Time) time.Time {
	u := t.UTC()
	return time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
}

// MARK: The worker's step

// fetchCapture is the titles in a text or image capture; nil (and no error) when the job failed
// here for good. The input is deleted once read, whatever the model found.
func (s *Service) fetchCapture(ctx context.Context, job *core.ImportJob) ([]Row, error) {
	store := s.CaptureStore()
	input, err := store.Input(ctx, job.ID)
	if err != nil {
		return nil, err
	}
	if input == nil {
		return nil, s.fail(ctx, job, "This capture expired before Aaru read it. Send it again.")
	}
	if s.Capture.Model == nil {
		if err := store.Delete(ctx, job.ID); err != nil {
			return nil, err
		}
		return nil, s.fail(ctx, job, "Aaru cannot read captures right now. Send it again later.")
	}
	extractor := capture.Extractor{Model: s.Capture.Model, Usage: s.Capture.Usage, Now: s.now}
	outcome, err := extractor.Titles(ctx, input.Content, job.UserID)
	if err != nil {
		return nil, err
	}
	if err := store.Delete(ctx, job.ID); err != nil {
		return nil, err
	}
	switch {
	case outcome.Refused:
		return nil, s.fail(ctx, job, "Aaru could not read that capture.")
	case len(outcome.Titles) == 0 && input.Content.Only == core.MediaBook:
		return nil, s.fail(ctx, job, "Aaru found no book in that capture.")
	case len(outcome.Titles) == 0:
		return nil, s.fail(ctx, job, "Aaru found no film, show, anime or book in that capture.")
	}
	rows := make([]Row, len(outcome.Titles))
	for i, t := range outcome.Titles {
		rows[i] = captureRow(t)
	}
	return rows, nil
}

// deleteCaptureInput forgets what a capture sent.
func (s *Service) deleteCaptureInput(ctx context.Context, jobID uuid.UUID) error {
	return s.CaptureStore().Delete(ctx, jobID)
}

// capturePlanned is "7 ready · 2 need a pick", once a capture's plan is ready.
func capturePlanned(job core.ImportJob) push.Message {
	ready := job.Stats.Created + job.Stats.Updated + job.Stats.Skipped
	var parts []string
	if ready > 0 {
		parts = append(parts, strconv.Itoa(ready)+" ready")
	}
	switch unmatched := job.Stats.Unmatched; {
	case unmatched == 1:
		parts = append(parts, "1 needs a pick")
	case unmatched > 1:
		parts = append(parts, strconv.Itoa(unmatched)+" need a pick")
	}
	body := strings.Join(parts, " · ")
	if body == "" {
		body = "Open it to see what Aaru found."
	}
	return push.Message{
		Title: "Your capture is ready to review", Body: body,
		Payload: map[string]string{"importId": strings.ToUpper(job.ID.String())},
	}
}
