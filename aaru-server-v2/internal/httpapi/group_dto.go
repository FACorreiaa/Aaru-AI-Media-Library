package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/groups"
)

// DTO mappers groups and the Board share (GroupHandlers.swift, SocialHandlers.swift).

// spoilerStampDTO is a stamp on the wire: season and episode, or the ending.
func spoilerStampDTO(s *groups.SpoilerStamp) *api.SpoilerStamp {
	if s == nil {
		return nil
	}
	if s.Ending || s.Episode == nil {
		ending := true
		return &api.SpoilerStamp{Ending: &ending}
	}
	season, episode := s.Episode.Season, s.Episode.Episode
	return &api.SpoilerStamp{Season: &season, Episode: &episode}
}

// spoilerChoice reads a request's `spoiler` and `spoilerFree`.
func spoilerChoice(stamp *api.SpoilerStamp, free *bool) (groups.SpoilerChoice, error) {
	if stamp == nil {
		return groups.ParseSpoilerChoice(false, nil, nil, nil, free)
	}
	return groups.ParseSpoilerChoice(true, stamp.Season, stamp.Episode, stamp.Ending, free)
}
