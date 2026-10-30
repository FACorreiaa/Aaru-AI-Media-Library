package imports

import (
	"aaru-go-api/internal/core"
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
func (a AgentImporter) DetectSource(text string) (core.ImportSource, error) { return DetectFormat(text) }

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
