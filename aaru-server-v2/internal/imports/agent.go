package imports

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"context"

	"github.com/google/uuid"
)

// AgentImporter is what the agent's `plan_import` tool needs (agent.Importer, AgentTools+Import):
// a list export becomes an ordinary import job the user reviews and approves in Aaru. It never
// writes the library.
type AgentImporter struct {
	Service *Service
}

// DetectSource is ImportFormatDetector.detect; a *FormatError's message is what the user sees.
func (a AgentImporter) DetectSource(text string) (core.ImportSource, error) {
	return DetectFormat(text)
}

// IsCATCalendar is CATCalendarParser.isCalendar: the text is an iCal file.
func (a AgentImporter) IsCATCalendar(text string) bool { return IsCATCalendar(text) }

// CreateFileImport is ImportService.createCSVImport; it returns the queued job's id.
func (a AgentImporter) CreateFileImport(ctx context.Context, user uuid.UUID, source core.ImportSource, filename *string, text string) (uuid.UUID, error) {
	job, err := a.Service.CreateCSVImport(ctx, user, source, filename, text)
	if err != nil {
		return uuid.Nil, err
	}
	return job.ID, nil
}

// CreateTitleList is BOOK-003: titles Aaru chose in a chat, as an ordinary capture the user reviews in
// Aaru. It spends one capture and returns the job's id.
func (a AgentImporter) CreateTitleList(ctx context.Context, user uuid.UUID, titles []capture.Title, list string) (uuid.UUID, error) {
	job, err := a.Service.CreateCapture(ctx, user, CaptureRequest{Titles: titles, ListName: list})
	if err != nil {
		return uuid.Nil, err
	}
	return job.ID, nil
}

// MARK: Files in a chat (ASK-010)

// CreateListenImport is a listening history a chat was sent, as the listening log's import.
func (a AgentImporter) CreateListenImport(ctx context.Context, user uuid.UUID, source core.ImportSource, filename *string, data []byte) (uuid.UUID, error) {
	job, err := a.Service.CreateListenFileImport(ctx, user, &source, filename, data)
	if err != nil {
		return uuid.Nil, err
	}
	return job.ID, nil
}

// CreateTextCapture is text a chat was sent, read as a capture. It spends one capture.
func (a AgentImporter) CreateTextCapture(ctx context.Context, user uuid.UUID, text string) (uuid.UUID, error) {
	return a.capture(ctx, user, CaptureRequest{Text: &text})
}

// CreatePictureCapture is pictures a chat was sent, read together as one capture.
func (a AgentImporter) CreatePictureCapture(ctx context.Context, user uuid.UUID, pictures []model.Image) (uuid.UUID, error) {
	return a.capture(ctx, user, CaptureRequest{Images: pictures})
}

// CreateDocumentCapture is a PDF a chat was sent, read as a capture.
func (a AgentImporter) CreateDocumentCapture(ctx context.Context, user uuid.UUID, pdf []byte) (uuid.UUID, error) {
	return a.capture(ctx, user, CaptureRequest{Document: pdf})
}

func (a AgentImporter) capture(ctx context.Context, user uuid.UUID, req CaptureRequest) (uuid.UUID, error) {
	job, err := a.Service.CreateCapture(ctx, user, req)
	if err != nil {
		return uuid.Nil, err
	}
	return job.ID, nil
}
