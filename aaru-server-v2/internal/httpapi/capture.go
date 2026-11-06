package httpapi

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/upload"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"strconv"
	"strings"

	"github.com/labstack/echo/v5"
)

// captureJSONLimit bounds capture's JSON body (HTTP-001): text is at most 100,000 characters, of
// up to four bytes each, with room for its escapes.
const captureJSONLimit = 512 << 10

// captureBodyLimit is what the route's middleware lets through: several pictures and their
// multipart framing. Each form is then held to its own limit.
const captureBodyLimit = imports.MaxCaptureImageBytes + 1<<20

// errCaptureTooLarge is imports' answer for text over its limit, given to a JSON body too big to
// hold that much text.
var errCaptureTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "capture_too_large",
	"That is more text than a capture reads. Paste a shorter list, or use an import.")

// errImageTooLarge is a capture image over 5 MB.
var errImageTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That image is larger than 5 MB.")

// errImagesTooLarge is a capture's pictures over their limit together.
var errImagesTooLarge = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "Those pictures are too large together. Send fewer.")

// errTooManyImages is a capture of more pictures than it reads.
var errTooManyImages = apperr.New(http.StatusUnprocessableEntity, "capture_too_many_images",
	"Aaru reads "+strconv.Itoa(imports.MaxCaptureImages)+" pictures at a time. Send fewer, or paste the text.")

// createCaptureImport is `POST /v1/imports/capture` (AG-006): JSON with exactly one of `text` and
// `url`; one image (JPEG, PNG, GIF, WebP) up to 5 MB; or up to five in a multipart form. `?kind=book`
// reads books only (BOOK-001).
func (s *Server) createCaptureImport(c *echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	only, err := captureOnly(c.QueryParam("kind"))
	if err != nil {
		return err
	}
	req := imports.CaptureRequest{Only: only}
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
		data, err := readUpload(c, imports.MaxUploadBytes, errImageTooLarge)
		if err != nil {
			return err
		}
		image, err := checkCaptureImage(data, mediaType)
		if err != nil {
			return err
		}
		req.Images = []model.Image{image}
	case "multipart/form-data":
		images, err := readCaptureImages(c)
		if err != nil {
			return err
		}
		req.Images = images
	default:
		return errUnreadable
	}
	job, err := s.Imports.CreateCapture(ctx, user, req)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusAccepted, ImportJobDTO(job))
}

// captureOnly is the `kind` a capture may be narrowed to: books, or nothing.
func captureOnly(kind string) (core.MediaType, error) {
	switch kind {
	case "":
		return "", nil
	case "book":
		return core.MediaBook, nil
	}
	return "", apperr.Validation("kind", "Aaru cannot narrow a capture to that.").
		WithDetails(map[string]string{"kind": "Must be book."})
}

// readCaptureImages reads a multipart form's `image` parts, in order, as they arrive: nothing past
// a limit is read. Other parts are ignored.
func readCaptureImages(c *echo.Context) ([]model.Image, error) {
	req := c.Request()
	if req.ContentLength > captureBodyLimit {
		return nil, errImagesTooLarge
	}
	reader, err := req.MultipartReader()
	if err != nil {
		return nil, apperr.BadRequest()
	}
	images := []model.Image{}
	total := 0
	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) {
			return images, nil
		}
		if err != nil {
			return nil, tooLargeOrBad(err)
		}
		if part.FormName() != "image" {
			continue
		}
		if len(images) == imports.MaxCaptureImages {
			return nil, errTooManyImages
		}
		data, fits, err := readUpTo(part, imports.MaxUploadBytes)
		if err != nil {
			return nil, tooLargeOrBad(err)
		}
		if !fits {
			return nil, errImageTooLarge
		}
		if total += len(data); total > imports.MaxCaptureImageBytes {
			return nil, errImagesTooLarge
		}
		mediaType, _, err := mime.ParseMediaType(part.Header.Get("Content-Type"))
		if err != nil {
			return nil, errUnreadable
		}
		image, err := checkCaptureImage(data, strings.ToLower(mediaType))
		if err != nil {
			return nil, err
		}
		images = append(images, image)
	}
}

// pictureDoor is what capture's pictures go through (ASK-010).
var pictureDoor = upload.Door{Accept: []upload.Kind{upload.KindImage}}

// checkCaptureImage is a picture sent as a type capture reads, whose bytes say it is that type and
// whose header declares a size a decoder can hold.
func checkCaptureImage(data []byte, declared string) (model.Image, error) {
	if !imports.CaptureImageTypes[declared] {
		return model.Image{}, errCaptureImageType
	}
	file, err := upload.Check("", declared, data, pictureDoor)
	if err != nil {
		return model.Image{}, err
	}
	return model.Image{Data: file.Data, MediaType: file.MediaType}, nil
}

// errCaptureImageType is a picture capture does not read, as imports refuses it.
var errCaptureImageType = apperr.New(http.StatusUnsupportedMediaType, "capture_image_type",
	"Send the image as a JPEG, PNG, GIF or WebP.")

// tooLargeOrBad is a body the middleware cut off past its limit, or one that is not a form.
func tooLargeOrBad(err error) error {
	var tooBig *http.MaxBytesError
	if errors.As(err, &tooBig) {
		return errImagesTooLarge
	}
	return apperr.BadRequest()
}
