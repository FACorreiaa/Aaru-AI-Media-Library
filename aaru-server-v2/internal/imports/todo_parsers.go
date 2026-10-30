package imports

// TODO(parsers): placeholder seams for the file parsers (CSVImportParser, GenericCSVParser,
// NetflixCSVParser, TVTimeCSVParser, CATImport, AnimeListImport, ImportFormatDetector). The parser
// port replaces this file.

import (
	"aaru-go-api/internal/core"
	"context"

	"github.com/google/uuid"
)

// CATFeed reads the user's CAT calendar by its link (IMP-010).
type CATFeed interface{}

// Parse is the uploaded file's rows: MyAnimeList XML, a CAT list or calendar, or one of the CSV
// layouts.
func Parse(text string, source core.ImportSource, filename *string) ([]Row, error) {
	_, _, _ = text, source, filename
	return nil, formatError("This import is not available yet.")
}

// DetectFormat is the source `auto` picks for a text export.
func DetectFormat(text string) (core.ImportSource, error) {
	_ = text
	return "", formatError("This import is not available yet.")
}

// CreateCATImport queues a CAT show list or calendar file.
func (s *Service) CreateCATImport(ctx context.Context, user uuid.UUID, text string) (core.ImportJob, error) {
	return s.CreateCSVImport(ctx, user, core.SourceCATList, nil, text)
}

// CreateCATFeedImport reads the user's CAT iCal link once and queues it.
func (s *Service) CreateCATFeedImport(ctx context.Context, user uuid.UUID, link string) (core.ImportJob, error) {
	_, _, _ = ctx, user, link
	return core.ImportJob{}, formatError("This import is not available yet.")
}
