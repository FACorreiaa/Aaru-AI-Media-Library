package httpapi

// ASK-010 · files in a Chat with Aaru: one file per request, read by internal/upload before
// anything else touches it, kept an hour in chat_attachments for the next turns to carry.

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/upload"
	"bytes"
	"context"
	"errors"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v5"
)

const (
	// maxChatAttachmentBytes is the largest file read: a listening history. Each kind has its own
	// limit under it.
	maxChatAttachmentBytes = imports.MaxListenUploadBytes
	// chatAttachmentsPerHour is each user's files an hour, across chats.
	chatAttachmentsPerHour = 40
	// maxAttachingInFlight is how many files this process reads at once.
	maxAttachingInFlight = 4
)

var (
	errAttachmentTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large",
		"That file is larger than 24 MB, the most Aaru reads.")
	errAttachmentTextTooLong = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large",
		"That is more text than Aaru reads at once (100,000 characters). Send part of it.")
	errChatAttachmentsFull = apperr.New(http.StatusConflict, "chat_attachments_full",
		"This chat holds as many files as it can. Remove one, or start a new chat.")
	errTooManyAttachments = apperr.RateLimited("Too many files. Try again later.")
	errAttachingBusy      = apperr.RateLimited("Aaru is reading other files right now. Try again in a moment.")
)

// chatDoor is what a chat takes: pictures, PDFs and text of every shape, MAL's .xml.gz unpacked.
var chatDoor = upload.Door{
	Accept:  []upload.Kind{upload.KindImage, upload.KindPDF, upload.KindText},
	MaxText: maxChatAttachmentBytes, Gzip: true,
}

// exportExts are the names that make plain text an export rather than words to read.
var exportExts = map[string]bool{".csv": true, ".tsv": true}

// createChatAttachment is `POST /v1/chats/{id}/attachments?filename=`: the body is the file.
func (s *Server) createChatAttachment(c *echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	if s.Model == nil {
		return errAgentUnavailable
	}
	chat, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return errChatNotFound
	}
	select {
	case s.attachingNow <- struct{}{}:
		defer func() { <-s.attachingNow }()
	default:
		return errAttachingBusy // before Allow: a busy server does not spend the user's hour
	}
	if !s.attaching.Allow(user.String(), time.Now()) {
		return errTooManyAttachments
	}
	data, err := readUpload(c, maxChatAttachmentBytes, errAttachmentTooLarge)
	if err != nil {
		return err
	}
	sent := c.QueryParam("filename")
	file, err := upload.Check(sent, contentType(c), data, chatDoor)
	if err != nil {
		return err
	}
	a, err := chatAttachment(file, sent)
	if err != nil {
		return err
	}
	saved, err := s.chats().SaveAttachment(ctx, chat, user, a)
	switch {
	case errors.Is(err, agent.ErrTooManyAttachments):
		return errChatAttachmentsFull
	case err != nil:
		return err
	case !saved:
		return errChatNotFound
	}
	return c.JSON(http.StatusCreated, chatAttachmentDTO(a))
}

// chatAttachment is a checked file as the chat keeps it: what it is for, and for an export or a
// history, which one and how many rows. An export Aaru does not recognise is refused with the
// importer's own words; text that only looks like one (JSON or XML of another kind) is text.
func chatAttachment(file upload.File, sent string) (agent.Attachment, error) {
	a := agent.Attachment{
		ID: uuid.New(), Name: agent.AttachmentName(sent), MediaType: file.MediaType, Data: file.Data,
		CreatedAt: time.Now().UTC(),
	}
	switch file.Kind {
	case upload.KindImage:
		a.Kind = agent.AttachImage
		return a, nil
	case upload.KindPDF:
		a.Kind = agent.AttachPDF
		return a, nil
	case upload.KindText:
	}
	ext := strings.ToLower(path.Ext(strings.TrimSuffix(strings.ToLower(sent), ".gz")))
	switch file.Format {
	case upload.FormatJSON:
		source, err := imports.DetectListenFile(file.Data)
		if err == nil {
			a.Kind, a.Source = agent.AttachListens, &source
			a.Rows = countOf(countPlays(file.Data, source))
			return a, nil
		}
		if ext == ".json" {
			return agent.Attachment{}, formatRefusal(err)
		}
	case upload.FormatXML:
		if source, err := imports.DetectFormat(file.Text); err == nil {
			a.Kind, a.Source = agent.AttachExport, &source
			a.Rows = countOf(strings.Count(file.Text, "<anime>") + strings.Count(file.Text, "<manga>"))
			return exportSized(a)
		}
	case upload.FormatCalendar:
		source := core.SourceCATICS
		a.Kind, a.Source = agent.AttachExport, &source
		a.Rows = countOf(strings.Count(strings.ToUpper(file.Text), "BEGIN:VEVENT"))
		return exportSized(a)
	case upload.FormatPlain:
		if exportExts[ext] {
			source, err := imports.DetectFormat(file.Text)
			if err != nil {
				return agent.Attachment{}, formatRefusal(err)
			}
			a.Kind, a.Source = agent.AttachExport, &source
			a.Rows = countOf(max(0, nonEmptyLines(file.Text)-1))
			return exportSized(a)
		}
	}
	if core.Length(file.Text) > imports.MaxCaptureText {
		return agent.Attachment{}, errAttachmentTextTooLong
	}
	a.Kind = agent.AttachText
	if a.MediaType != "text/plain" {
		a.MediaType = "text/plain"
	}
	return a, nil
}

// exportSized holds an export to the import's own 5 MB.
func exportSized(a agent.Attachment) (agent.Attachment, error) {
	if len(a.Data) > imports.MaxUploadBytes {
		return agent.Attachment{}, errFileTooLarge
	}
	return a, nil
}

// formatRefusal is the importer's word on a file it does not read, as a 422.
func formatRefusal(err error) error {
	var format *imports.FormatError
	if errors.As(err, &format) {
		return apperr.Validation("file", format.Message)
	}
	return err
}

func countPlays(data []byte, source core.ImportSource) int {
	if source == core.SourceSpotifyJSON {
		return bytes.Count(data, []byte(`"ms_played"`))
	}
	return bytes.Count(data, []byte(`"titleUrl"`))
}

func nonEmptyLines(text string) int {
	n := 0
	for line := range strings.SplitSeq(text, "\n") {
		if strings.TrimSpace(line) != "" {
			n++
		}
	}
	return n
}

func countOf(v int) *int { return &v }

func chatAttachmentDTO(a agent.Attachment) api.ChatAttachment {
	dto := api.ChatAttachment{
		Id: apiid.From(a.ID), Kind: api.ChatAttachmentKind(a.Kind), Name: a.Name, Size: len(a.Data), Rows: a.Rows,
		Summary: strings.TrimPrefix(a.Describe(), a.Name+", "),
	}
	if a.Source != nil {
		v := string(*a.Source)
		dto.Source = &v
	}
	return dto
}

// DeleteChatAttachment is `DELETE /v1/chats/{id}/attachments/{attachmentId}`. Gone already is fine.
func (s *Server) DeleteChatAttachment(ctx context.Context, req api.DeleteChatAttachmentRequestObject) (api.DeleteChatAttachmentResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if _, err := s.chats().DeleteAttachment(ctx, req.AttachmentId.ID(), req.Id.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteChatAttachment204Response{}, nil
}
