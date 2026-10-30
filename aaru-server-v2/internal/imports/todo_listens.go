package imports

// TODO(listens): placeholder seams for listening-history imports (ImportService+Listens,
// Imports/Listens/*). The listens port replaces this file.

import (
	"aaru-go-api/internal/core"
	"context"
	"errors"
)

// ListenHistoryReader reads listening history by username (MUS-004).
type ListenHistoryReader interface{}

// ListenLog writes imported listens into the listening log (MUS-004).
type ListenLog interface{}

var errListensNotPorted = errors.New("listening imports are not ported yet")

// planListens reads or stages a listening import's plays.
func (s *Service) planListens(ctx context.Context, job *core.ImportJob) error {
	_, _ = ctx, job
	return errListensNotPorted
}

// applyListens moves a listening import's staged plays into the log.
func (s *Service) applyListens(ctx context.Context, job core.ImportJob) (core.ImportJob, error) {
	_, _ = ctx, job
	return core.ImportJob{}, errListensNotPorted
}
