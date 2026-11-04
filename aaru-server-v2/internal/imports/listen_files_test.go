package imports

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// spotifyFile is a synthetic Streaming_History_Audio file of about size bytes, with the fields
// a real one has.
func spotifyFile(size int) []byte {
	var b bytes.Buffer
	b.WriteByte('[')
	for i := 0; b.Len() < size; i++ {
		if i > 0 {
			b.WriteByte(',')
		}
		entry, _ := json.Marshal(map[string]any{
			"ts":       time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC).Add(time.Duration(i) * time.Minute).Format(time.RFC3339),
			"username": "someone", "platform": "ios", "ms_played": 180000 + i%1000, "conn_country": "PT",
			"ip_addr":                           "192.0.2.1",
			"master_metadata_track_name":        fmt.Sprintf("Track %d", i%500),
			"master_metadata_album_artist_name": fmt.Sprintf("Artist %d", i%100),
			"master_metadata_album_album_name":  fmt.Sprintf("Album %d", i%200),
			"spotify_track_uri":                 fmt.Sprintf("spotify:track:%022d", i%500),
			"episode_name":                      nil, "episode_show_name": nil, "spotify_episode_uri": nil,
			"audiobook_title": nil, "audiobook_uri": nil, "audiobook_chapter_uri": nil, "audiobook_chapter_title": nil,
			"reason_start": "trackdone", "reason_end": "trackdone", "shuffle": false, "skipped": false,
			"offline": false, "offline_timestamp": nil, "incognito_mode": false,
		})
		b.Write(entry)
	}
	b.WriteByte(']')
	return b.Bytes()
}

func BenchmarkParseSpotifyHistory(b *testing.B) {
	data := spotifyFile(MaxListenUploadBytes)
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	b.SetBytes(int64(len(data)))
	b.ReportAllocs()
	for b.Loop() {
		page, err := ParseSpotifyHistory(data, now)
		if err != nil || len(page.Listens) == 0 {
			b.Fatal(err, len(page.Listens))
		}
	}
}

func TestListenFileParsersRefuseWhatIsNotAnArrayOfObjects(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	for _, file := range []string{
		``, `null`, `{}`, `"x"`, `[null]`, `[1]`, `[[]]`, `["x"]`, `[{}, null]`, `[{}`, `[{},]`, `[{}] trailing`, `[{}] []`,
	} {
		_, err := ParseSpotifyHistory([]byte(file), now)
		assert.Error(t, err, "spotify %q", file)
		_, err = ParseYouTubeTakeout([]byte(file), now)
		assert.Error(t, err, "takeout %q", file)
	}
	for _, file := range []string{`[]`, ` [ ] `, `[{}]`, "[{}]\n"} {
		_, err := ParseSpotifyHistory([]byte(file), now)
		assert.NoError(t, err, "spotify %q", file)
		_, err = ParseYouTubeTakeout([]byte(file), now)
		assert.NoError(t, err, "takeout %q", file)
	}
}

func TestSpotifyFieldsOfAnotherTypeAreMissing(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	file := `[
	 {"ts":"2024-01-01T00:10:00Z","ms_played":60000,"master_metadata_album_artist_name":"A","master_metadata_track_name":"T",
	  "master_metadata_album_album_name":7,"episode_name":3,"audiobook_title":{"x":1}},
	 {"ts":"2024-01-01T00:20:00Z","ms_played":"60000","master_metadata_album_artist_name":"A","master_metadata_track_name":"T"},
	 {"ts":"2024-01-01T00:30:00Z","ms_played":60000.5,"master_metadata_album_artist_name":"A","master_metadata_track_name":"T"},
	 {"ts":"2024-01-01T00:40:00Z","ms_played":60000,"master_metadata_album_artist_name":"A","master_metadata_track_name":"T","episode_name":"E"},
	 {"ts":"2024-01-01T00:50:00Z","ms_played":1,"ms_played":60000,"master_metadata_album_artist_name":"A","master_metadata_track_name":"T","master_metadata_track_name":null}
	]`
	page, err := ParseSpotifyHistory([]byte(file), now)
	require.NoError(t, err)
	require.Len(t, page.Listens, 1)
	assert.Nil(t, page.Listens[0].Album, "an album of another type is no album")
	assert.Equal(t, 4, page.Ignored, "a text or fractional length, an episode, and a later null all leave the play out")
}

func TestAWaitingListenFileGivesUpWithItsRequest(t *testing.T) {
	s := &Service{}
	done, err := s.listenFileTurn(context.Background())
	require.NoError(t, err)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_, err = s.listenFileTurn(ctx)
	require.ErrorIs(t, err, context.DeadlineExceeded)
	done()
	again, err := s.listenFileTurn(context.Background())
	require.NoError(t, err, "the turn came back")
	again()
}

// HLT-002: a listening file is whatever the person uploads. Parsers refuse or read it, never panic,
// and every play kept has the fields a listen needs.
func FuzzParseListenFile(f *testing.F) {
	for _, seed := range []string{
		`[]`, `null`, `[null]`, `[{}]`, `[{},]`, `[{}] x`,
		`[{"ts":"2024-01-01T00:10:00Z","ms_played":60000,"master_metadata_album_artist_name":"A","master_metadata_track_name":"T"}]`,
		`[{"ts":7,"ms_played":"x","master_metadata_track_name":{"a":[1]},"episode_name":null}]`,
		`[{"header":"YouTube Music","title":"Watched T","titleUrl":"https://x","time":"2024-01-01T00:00:00Z","subtitles":[{"name":"A - Topic"}]}]`,
		`[{"header":"YouTube","subtitles":[null,{"name":7}],"details":"x"}]`,
	} {
		f.Add([]byte(seed))
	}
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	f.Fuzz(func(t *testing.T, data []byte) {
		for _, parse := range []func([]byte, time.Time) (ListenHistoryPage, error){ParseSpotifyHistory, ParseYouTubeTakeout} {
			page, err := parse(data, now)
			if err != nil {
				continue
			}
			for _, l := range page.Listens {
				if l.Artist == "" || l.Track == "" || l.ListenedAt.IsZero() {
					t.Fatalf("a listen without its fields: %+v", l)
				}
			}
		}
		_, _ = DetectListenFile(data)
	})
}
