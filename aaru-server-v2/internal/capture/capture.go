// Package capture is AG-006's intake (Capture/*.swift, PostgresCaptureStore.swift): what a capture
// sent, kept only until the worker has read the titles out of it; links parsed by id and never
// fetched; the one model call that reads text and images. The import pipeline (internal/imports)
// plans what it finds; this package knows nothing of imports, so its titles are its own type.
package capture

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/model"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Content is what a capture sent: text, or images (JPEG, PNG, GIF or WebP) as uploaded.
type Content struct {
	// Text is set for a text capture.
	Text string
	// Image and MediaType are set for an image capture: its first picture.
	Image     []byte
	MediaType string
	// More are an image capture's other pictures, in order.
	More []model.Image
	// Only narrows what is read to one kind, as the Books page asks (BOOK-001). Empty reads all.
	Only core.MediaType
}

// Images are an image capture's pictures, in order.
func (c Content) Images() []model.Image {
	return append([]model.Image{{Data: c.Image, MediaType: c.MediaType}}, c.More...)
}

// IsImage is whether the content is an image.
func (c Content) IsImage() bool { return c.MediaType != "" }

// Kind is `text` or `image`, as `capture_inputs.kind` keeps it.
func (c Content) Kind() string {
	if c.IsImage() {
		return "image"
	}
	return "text"
}

// Input is one capture's content (CaptureInput).
type Input struct {
	JobID     uuid.UUID
	UserID    uuid.UUID
	Content   Content
	CreatedAt time.Time
}

// Title is one title a capture names, as the import plans it: always a wishlist add (the
// import's row). SourceKey is set for a link; Author, when named, narrows a book's search.
type Title struct {
	SourceKey *string
	Type      core.MediaType
	Title     string
	Year      *int
	Author    *string
	IDs       core.ExternalIDs
	// Place is the title's step in a roadmap (GRAPH-003); nil in a plain list.
	Place *Place
}

// Place is a title's place in a roadmap (GRAPH-003): the numbered step it belongs to, with that
// step's heading and note, and its own note ("FF #570-588"), whether it is optional, and the pair it
// is read side by side with. Kept on the import row and written to the list on approval.
type Place struct {
	Step     int    `json:"step"`
	Heading  string `json:"heading,omitempty"`
	StepNote string `json:"stepNote,omitempty"`
	Note     string `json:"note,omitempty"`
	Optional bool   `json:"optional,omitempty"`
	// Pair numbers the titles read side by side within the roadmap; 0 for none.
	Pair int `json:"pair,omitempty"`
}

// InputLifetime is how long an input the worker never got to is kept.
const InputLifetime = time.Hour

// Store is capture inputs (PostgresCaptureStore).
type Store struct {
	Q *sqlc.Queries
}

// Save writes an input.
func (s *Store) Save(ctx context.Context, in Input) error {
	params := sqlc.CaptureInputSaveParams{
		JobID: in.JobID, UserID: in.UserID, Kind: in.Content.Kind(), CreatedAt: in.CreatedAt,
	}
	if in.Content.IsImage() {
		params.Image, params.MediaType = in.Content.Image, &in.Content.MediaType
		if params.Image == nil {
			params.Image = []byte{}
		}
	} else {
		params.Text = &in.Content.Text
	}
	if in.Content.Only != "" {
		only := string(in.Content.Only)
		params.OnlyType = &only
	}
	if err := s.Q.CaptureInputSave(ctx, params); err != nil {
		return fmt.Errorf("save capture input: %w", err)
	}
	for i, image := range in.Content.More {
		err := s.Q.CaptureImageSave(ctx, sqlc.CaptureImageSaveParams{
			JobID: in.JobID, Position: int32(i + 1), Image: image.Data, MediaType: image.MediaType,
		})
		if err != nil {
			return fmt.Errorf("save capture image: %w", err)
		}
	}
	return nil
}

// Input is a job's input; nil when there is none.
func (s *Store) Input(ctx context.Context, jobID uuid.UUID) (*Input, error) {
	rows, err := s.Q.CaptureInputGet(ctx, jobID)
	if err != nil {
		return nil, fmt.Errorf("capture input: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil // no input
	}
	r := rows[0]
	in := &Input{JobID: jobID, UserID: r.UserID, CreatedAt: r.CreatedAt}
	switch {
	case r.Image != nil && r.MediaType != nil:
		in.Content = Content{Image: r.Image, MediaType: *r.MediaType}
	case r.Text != nil:
		in.Content = Content{Text: *r.Text}
	}
	if r.OnlyType != nil {
		in.Content.Only = core.MediaType(*r.OnlyType)
	}
	if in.Content.IsImage() {
		more, err := s.Q.CaptureImages(ctx, jobID)
		if err != nil {
			return nil, fmt.Errorf("capture images: %w", err)
		}
		for _, image := range more {
			in.Content.More = append(in.Content.More, model.Image{Data: image.Image, MediaType: image.MediaType})
		}
	}
	return in, nil
}

// Delete forgets a job's input.
func (s *Store) Delete(ctx context.Context, jobID uuid.UUID) error {
	if err := s.Q.CaptureInputDelete(ctx, jobID); err != nil {
		return fmt.Errorf("delete capture input: %w", err)
	}
	return nil
}

// Sweep deletes every input written before before; it returns how many.
func (s *Store) Sweep(ctx context.Context, before time.Time) (int, error) {
	ids, err := s.Q.CaptureInputSweep(ctx, before)
	if err != nil {
		return 0, fmt.Errorf("sweep capture inputs: %w", err)
	}
	return len(ids), nil
}

// Captures is the user's capture jobs started at or after since, failed ones included, and the chat
// plans from then that spend one and are approved or, at now, still waiting.
func (s *Store) Captures(ctx context.Context, user uuid.UUID, since, now time.Time) (int, error) {
	n, err := s.Q.BillingCapturesSince(ctx, sqlc.BillingCapturesSinceParams{UserID: user, Since: since, Now: now})
	if err != nil {
		return 0, fmt.Errorf("count captures: %w", err)
	}
	return int(n), nil
}
