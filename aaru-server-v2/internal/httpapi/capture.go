package httpapi

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/imports"
	"encoding/json"
	"io"
	"net/http"

	"github.com/labstack/echo/v4"
)

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
		data, err := io.ReadAll(c.Request().Body)
		if err != nil {
			return apperr.BadRequest()
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
