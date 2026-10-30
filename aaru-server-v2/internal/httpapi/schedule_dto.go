package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/core"
)

// EpisodeRefsDTO is a sorted list of ticks on the wire.
func EpisodeRefsDTO(keys []core.EpisodeKey) []api.EpisodeRef {
	out := make([]api.EpisodeRef, 0, len(keys))
	for _, k := range keys {
		out = append(out, api.EpisodeRef{Season: k.Season, Number: k.Episode})
	}
	return out
}
