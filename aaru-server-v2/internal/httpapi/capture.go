package httpapi

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/imports"
	"encoding/json"
	"net/http"

	"github.com/labstack/echo/v4"
)

// captureJSONLimit bounds capture's JSON body (HTTP-001): text is at most 20,000 characters.
const captureJSONLimit = 128 << 10

// errCaptureTooLarge is imports' answer for text over its limit, given to a JSON body too big to
// hold that much text.
var errCaptureTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "capture_too_large",
	"That is more text than a capture reads. Paste a shorter list, or use an import.")

// errImageTooLarge is a capture image over 5 MB.
var errImageTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That image is larger than 5 MB.")

// createCaptureImport is `POST /v1/imports/capture` (AG-006): JSON with exactly one of `text` and
// `url`, or one image (JPEG, PNG, GIF, WebP) up to 5 MB.
func (s *Server) createCaptureImport(c echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	var req imports.CaptureRequest
	switch mediaType := contentType(c); mediaType {
	case "application/json":
		data, fits, err := readUpTo(c.Request().Body, captureJSONLimit)
		if err != nil {
			return apperr.BadRequest()
		}
		if !fits {
			return errCaptureTooLarge
		}
		var body struct {
			Text *string `json:"text"`
			URL  *string `json:"url"`
		}
		if err := json.Unmarshal(data, &body); err != nil {
			return apperr.BadRequest()
		}
		switch {
		case body.Text != nil && body.URL == nil:
			req.Text = body.Text
		case body.Text == nil && body.URL != nil:
			req.Link = body.URL
		default:
			return apperr.Validation("body", "Send text or a link, not both.").
				WithDetails(map[string]string{"body": "Exactly one of text and url."})
		}
	case "image/jpeg", "image/png", "image/gif", "image/webp":
		image, err := readUpload(c, imports.MaxUploadBytes, errImageTooLarge)
		if err != nil {
			return err
		}
		req.Image, req.MediaType = image, mediaType
	default:
		return errUnreadable
	}
	job, err := s.Imports.CreateCapture(ctx, user, req)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusAccepted, ImportJobDTO(job))
}
