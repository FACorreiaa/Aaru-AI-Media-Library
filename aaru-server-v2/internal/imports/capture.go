package imports

// AG-006 · capture as an import source (ImportService+Capture.swift). A link is read on the
// request (by its URL alone); text and images are read by the worker through the model, then
// planned like any other import.

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/billing"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/telemetry"
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
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
	// FreeCapturesPerMonth is billing's: captures a free account may start in one UTC month.
	FreeCapturesPerMonth = billing.FreeCapturesPerMonth
	// PlusCapturesPerDay is Plus's fair use: captures one account may start in a UTC day.
	PlusCapturesPerDay = 30
	// MaxCaptureText is the longest pasted text a capture reads, in characters.
	MaxCaptureText = 20000
)

// CaptureImageTypes are the image types the model reads. Clients send JPEG; the others are what
// the Messages API also takes.
var CaptureImageTypes = map[string]bool{"image/jpeg": true, "image/png": true, "image/gif": true, "image/webp": true}

// CaptureRequest is what a capture sent: exactly one of text, a link, or an image.
type CaptureRequest struct {
	Text *string
	Link *string
	// Image and MediaType are set for an image.
	Image     []byte
	MediaType string
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
	if err := s.checkCaptureQuota(ctx, user); err != nil {
		return core.ImportJob{}, err
	}
	now := s.now()
	if input != nil {
		if err := s.CaptureStore().Save(ctx, capture.Input{JobID: jobID, UserID: user, Content: *input, CreatedAt: now}); err != nil {
			return core.ImportJob{}, err
		}
	}
	job := newJob(user, core.SourceCapture, nil, now)
	job.ID = jobID
	job.RowsTotal = len(rows)
	if err := s.Store.Insert(ctx, job, rows); err != nil {
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
		if utf8.RuneCountInString(text) > MaxCaptureText {
			return nil, nil, apperr.New(http.StatusRequestEntityTooLarge, "capture_too_large",
				"That is more text than a capture reads. Paste a shorter list, or use an import.")
		}
		return nil, &capture.Content{Text: text}, nil
	}
	if !CaptureImageTypes[req.MediaType] {
		return nil, nil, apperr.New(http.StatusUnsupportedMediaType, "capture_image_type",
			"Send the image as a JPEG, PNG, GIF or WebP.")
	}
	return nil, &capture.Content{Image: req.Image, MediaType: req.MediaType}, nil
}

// captureRow is a captured title as a row to plan: always a wishlist add.
func captureRow(t capture.Title) Row {
	return Row{
		SourceKey: t.SourceKey, Type: t.Type, Title: t.Title, Year: t.Year, IDs: t.IDs,
		Status: ptr(core.StatusWishlist), Lists: []string{},
	}
}

// checkCaptureQuota: free accounts get FreeCapturesPerMonth; past it, a 402 the apps answer with
// Plus. Plus lifts the month's limit; PlusCapturesPerDay keeps one account from running up the bill.
func (s *Service) checkCaptureQuota(ctx context.Context, user uuid.UUID) error {
	now := s.now()
	plus, err := (&billing.Service{Q: s.Store.Q}).Active(ctx, user, now)
	if err != nil {
		return err
	}
	store := s.CaptureStore()
	if plus != nil {
		today, err := store.Captures(ctx, user, DayStart(now))
		if err != nil {
			return err
		}
		if today < PlusCapturesPerDay {
			return nil
		}
		return apperr.New(http.StatusTooManyRequests, "capture_fair_use",
			"Aaru reads "+strconv.Itoa(PlusCapturesPerDay)+" captures a day. More tomorrow.")
	}
	start, next := billing.MonthStart(now)
	used, err := store.Captures(ctx, user, start)
	if err != nil {
		return err
	}
	if used < FreeCapturesPerMonth {
		return nil
	}
	telemetry.Capture(telemetry.PaywallShown, user, map[string]string{"reason": "capture_quota"})
	return apperr.New(http.StatusPaymentRequired, "capture_quota",
		fmt.Sprintf("You have used this month's %d captures. More come on %s, or Aaru Plus lifts the limit.",
			FreeCapturesPerMonth, next.UTC().Format("January 2")))
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
