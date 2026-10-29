// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ExportAccount(context.Context, api.ExportAccountRequestObject) (api.ExportAccountResponseObject, error) {
	return nil, errNotImplemented
}
