package stremioapi

import (
	"fmt"
	"testing"
)

// FuzzEpisodes fuzzes the watched-episode bitfield a Stremio library item carries (HLT-002): a
// user-controlled string decoded through base64 and zlib. It must never panic, and it returns one
// flag per video.
func FuzzEpisodes(f *testing.F) {
	for _, s := range []string{
		"tt1:2:3:7:eJwTAwAAFwAX", "tt1:1:3:3:eJxjBQAABgAG", "tt1:9:9:3:eJxjBQAABgAG", "garbage",
		"tt1:1:3:-9223372036854775808:eJxjBQAABgAG", "tt1:1:3:9223372036854775807:eJxjBQAABgAG", "::",
	} {
		f.Add(s)
	}
	var videos []Video
	ids := make([]string, 0, 7)
	for _, p := range [][2]int{{0, 1}, {1, 1}, {1, 2}, {1, 3}, {2, 1}, {2, 2}, {2, 3}} {
		id := fmt.Sprintf("tt1:%d:%d", p[0], p[1])
		videos = append(videos, Video{ID: id, Season: p[0], Episode: p[1]})
		ids = append(ids, id)
	}
	f.Fuzz(func(t *testing.T, field string) {
		if keys := Episodes(field, videos); len(keys) > len(videos) {
			t.Fatalf("%d episodes from %d videos", len(keys), len(videos))
		}
		flags, err := Watched(field, ids)
		if err == nil && len(flags) != len(ids) {
			t.Fatalf("%d flags for %d videos", len(flags), len(ids))
		}
	})
}
