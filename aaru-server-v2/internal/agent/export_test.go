package agent

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/library"

	"github.com/google/uuid"
)

// NewGroupToolsForTest is the tools `@aaru` gets for one mention, built as the reply worker builds them.
func NewGroupToolsForTest(kit *catalog.Kit, lib *library.Service, user uuid.UUID) *GroupTools {
	return &GroupTools{titleReads: newTitleReads(kit, lib, user, nil)}
}
