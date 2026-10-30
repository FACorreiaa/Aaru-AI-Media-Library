package imports

// TODO(capture): placeholder seams for capture imports (ImportService+Capture). The capture port
// replaces this file.

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/push"
	"context"

	"github.com/google/uuid"
)

// CaptureDeps are the capture inputs store and the extractor (AG-006).
type CaptureDeps struct{}

// fetchCapture reads a capture's titles with one model call; nil when it failed the job for good.
func (s *Service) fetchCapture(ctx context.Context, job *core.ImportJob) ([]Row, error) {
	return nil, s.fail(ctx, job, "Captures are not available right now.")
}

// deleteCaptureInput forgets what a capture sent.
func (s *Service) deleteCaptureInput(ctx context.Context, jobID uuid.UUID) error {
	_, _ = ctx, jobID
	return nil
}

// capturePlanned is the push that says a capture's plan is ready.
func capturePlanned(job core.ImportJob) push.Message {
	_ = job
	return push.Message{}
}
