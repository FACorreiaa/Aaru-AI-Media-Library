package stremioapi

import (
	"aaru-go-api/internal/core"
	"bytes"
	"compress/zlib"
	"encoding/base64"
	"errors"
	"io"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Stremio's watched-episode field on a library item: `{anchorVideoId}:{anchorLength}:{bits}`,
// where `bits` is base64 of a zlib stream, one bit per video, least significant bit first.
//
// The bits follow the show's episode list as Stremio saw it when the field was written. The anchor
// is a video id and how long the list was then, so the bits can be lined up with a list that has
// since grown. Same rules as stremio-core's `WatchedBitField::construct_and_resize`.

// Video is one entry in a show's episode list (Cinemeta `meta.videos`).
type Video struct {
	ID       string
	Season   int
	Episode  int
	Released *time.Time
}

// ErrMalformed is a watched field that cannot be read.
var ErrMalformed = errors.New("stremio: malformed watched field")

// Episodes are the episodes the field marks watched. Specials (season 0) are left out: their
// numbering differs between Cinemeta and TMDB, and a guess would tick the wrong episode.
func Episodes(field string, videos []Video) []core.EpisodeKey {
	ordered := Ordered(videos)
	ids := make([]string, len(ordered))
	for i, v := range ordered {
		ids[i] = v.ID
	}
	flags, err := Watched(field, ids)
	if err != nil {
		return []core.EpisodeKey{}
	}
	keys := []core.EpisodeKey{}
	for i, watched := range flags {
		v := ordered[i]
		if !watched || v.Season <= 0 {
			continue
		}
		if key, err := core.NewEpisodeKey(v.Season, v.Episode); err == nil {
			keys = append(keys, key)
		}
	}
	return keys
}

// Ordered is Stremio's order: season, then episode, then release date (an unknown date first).
func Ordered(videos []Video) []Video {
	out := slices.Clone(videos)
	sort.SliceStable(out, func(i, j int) bool {
		l, r := out[i], out[j]
		if l.Season != r.Season {
			return l.Season < r.Season
		}
		if l.Episode != r.Episode {
			return l.Episode < r.Episode
		}
		switch {
		case l.Released == nil:
			return r.Released != nil
		case r.Released == nil:
			return false
		}
		return l.Released.Before(*r.Released)
	})
	return out
}

// Watched is one flag per id in videoIDs. An anchor that is no longer in the list gives all false,
// as Stremio does.
func Watched(field string, videoIDs []string) ([]bool, error) {
	// Video ids contain colons (`tt0903747:1:2`), so split from the right.
	parts := strings.Split(field, ":")
	if len(parts) < 3 {
		return nil, ErrMalformed
	}
	bits := parts[len(parts)-1]
	anchorLength, err := strconv.Atoi(parts[len(parts)-2])
	if err != nil {
		return nil, ErrMalformed
	}
	anchor := strings.Join(parts[:len(parts)-2], ":")
	data, err := base64.StdEncoding.DecodeString(bits)
	if err != nil {
		return nil, ErrMalformed
	}
	raw, err := Inflate(data, 1<<20)
	if err != nil {
		return nil, err
	}
	flags := make([]bool, len(videoIDs))
	anchorIndex := slices.Index(videoIDs, anchor)
	if anchorIndex < 0 {
		return flags, nil
	}
	offset := anchorLength - anchorIndex - 1
	for index := range videoIDs {
		old := index + offset
		if old < 0 || old/8 >= len(raw) {
			continue
		}
		flags[index] = (raw[old/8]>>(old%8))&1 == 1
	}
	return flags, nil
}

// ErrInflate is zlib data that does not inflate, or inflates past the limit.
var ErrInflate = errors.New("stremio: zlib inflate failed")

// Inflate inflates zlib-wrapped data (RFC 1950), with a ceiling so a hostile input cannot balloon.
func Inflate(input []byte, limit int) ([]byte, error) {
	reader, err := zlib.NewReader(bytes.NewReader(input))
	if err != nil {
		return nil, ErrInflate
	}
	defer func() { _ = reader.Close() }()
	out, err := io.ReadAll(io.LimitReader(reader, int64(limit)+1))
	if err != nil || len(out) > limit {
		return nil, ErrInflate
	}
	return out, nil
}
