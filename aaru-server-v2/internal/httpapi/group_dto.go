package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/groups"
	"fmt"
	"strings"
)

// DTO mappers groups and the Board share (GroupHandlers.swift, SocialHandlers.swift).

// avatarPath is `GET /v1/users/{userId}/avatar` with its version (SocialService.avatarPath).
func avatarPath(id apiid.UUID, version int64) string {
	return fmt.Sprintf("/v1/users/%s/avatar?v=%d", strings.ToUpper(id.ID().String()), version)
}

// groupUserDTO is a SocialUser on the wire. The social area maps its own users the same way.
func groupUserDTO(u groups.User) api.SocialUser {
	dto := api.SocialUser{UserId: apiid.From(u.ID), Handle: u.Handle, DisplayName: u.DisplayName}
	if u.AvatarVersion != nil {
		path := avatarPath(dto.UserId, *u.AvatarVersion)
		dto.AvatarUrl = &path
	}
	return dto
}

func groupUsersDTO(users []groups.User) []api.SocialUser {
	out := make([]api.SocialUser, len(users))
	for i, u := range users {
		out[i] = groupUserDTO(u)
	}
	return out
}

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
