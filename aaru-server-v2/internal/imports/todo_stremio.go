package imports

// TODO(stremio): placeholder seams for the Stremio history import (ImportService+Stremio,
// Imports/Stremio/*). The Stremio port replaces this file.

import "context"

// StremioAccount is Stremio's account API and Cinemeta, for history imports (IMP-016).
type StremioAccount interface{}

// expandStremioWatched decodes each row's Stremio watched bitfield into ticks.
func (s *Service) expandStremioWatched(ctx context.Context, rows []PlannedRow) ([]PlannedRow, error) {
	_ = ctx
	return rows, nil
}
