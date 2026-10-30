package catalog

import (
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MUS-006: MusicBrainz's recording search against canned JSON. No network.
// Ported from ListenResolverTests.swift (RecordingMatchTests).

// mbRecordingG4 is one recording search result; each release is title, release-group id,
// primary type.
func mbRecordingG4(t *testing.T, id, title string, score int, releases [][3]string) MusicBrainzRecording {
	t.Helper()
	rels := make([]map[string]any, 0, len(releases))
	for _, r := range releases {
		rels = append(rels, map[string]any{
			"title":         r[0],
			"release-group": map[string]any{"id": r[1], "title": r[0], "primary-type": r[2]},
		})
	}
	raw, err := json.Marshal(map[string]any{
		"id": id, "score": score, "title": title,
		"artist-credit": []any{map[string]any{"name": "Beastie Boys", "joinphrase": "", "artist": map[string]any{"id": "a-1", "name": "Beastie Boys"}}},
		"releases":      rels,
	})
	require.NoError(t, err)
	var recording MusicBrainzRecording
	require.NoError(t, json.Unmarshal(raw, &recording))
	return recording
}

func recordingMatchG4(recording, group, artist string) RecordingMatch {
	opt := func(s string) *string {
		if s == "" {
			return nil
		}
		return &s
	}
	return RecordingMatch{RecordingMBID: opt(recording), ReleaseGroupMBID: opt(group), ArtistMBID: opt(artist)}
}

func TestRecordingSearchAsksBySentIDElseISRCElseArtistAndTitle(t *testing.T) {
	stub := stubFunc(func(provider.Request) provider.Response {
		return provider.Response{Status: 200, Body: []byte(`{"recordings":[]}`)}
	})
	mb := musicBrainz(stub)
	ctx := context.Background()
	_, err := mb.Match(ctx, RecordingQuery{Artist: "Beastie Boys", Track: "Sabotage", RecordingMBID: ptr("r-1")})
	require.NoError(t, err)
	_, err = mb.Match(ctx, RecordingQuery{Artist: "Beastie Boys", Track: "Sabotage", ISRC: ptr("USCA29400153")})
	require.NoError(t, err)
	_, err = mb.Match(ctx, RecordingQuery{Artist: "AC/DC", Track: "T.N.T."})
	require.NoError(t, err)
	var queries []string
	for _, req := range stub.all() {
		queries = append(queries, urlQuery(req.URL).Get("query"))
		assert.True(t, strings.HasSuffix(urlPath(req.URL), "/ws/2/recording"), req.URL)
		assert.True(t, hasHeader(req, "User-Agent", "Aaru-test"))
	}
	assert.Equal(t, []string{"rid:r-1", "isrc:USCA29400153", `recording:"T.N.T." AND artist:"AC\/DC"`}, queries)
}

func TestRecordingMatchIsExactOnlyAndTheAlbumIsTheOneNamed(t *testing.T) {
	recordings := []MusicBrainzRecording{
		mbRecordingG4(t, "r-1", "Sabotage", 100, [][3]string{{"Ill Communication", "rg-ill", "Album"}, {"Sabotage", "rg-s", "Single"}}),
		mbRecordingG4(t, "r-2", "sabotage", 100, [][3]string{{"The Sounds of Science", "rg-sos", "Album"}}),
		mbRecordingG4(t, "r-3", "Sabotage (live)", 100, [][3]string{{"Live", "rg-live", "Album"}}),
		mbRecordingG4(t, "r-4", "Sabotage", 88, [][3]string{{"Ill Communication", "rg-other", "Album"}}),
	}
	named := MatchRecording(RecordingQuery{Artist: "beastie  boys", Track: "SABOTAGE", Album: ptr("ill communication")}, recordings)
	assert.Equal(t, recordingMatchG4("", "rg-ill", "a-1"), named,
		"two exact recordings: no recording id, but the named album and the artist are certain")

	unnamed := MatchRecording(RecordingQuery{Artist: "Beastie Boys", Track: "Sabotage"}, recordings)
	assert.Nil(t, unnamed.ReleaseGroupMBID, "two albums and no album named: nothing is guessed")

	one := MatchRecording(RecordingQuery{Artist: "Beastie Boys", Track: "Sabotage"}, recordings[:1])
	assert.Equal(t, recordingMatchG4("r-1", "rg-ill", "a-1"), one, "with no album named, the only album wins over a single")

	fuzzy := MatchRecording(RecordingQuery{Artist: "Beastie Boys", Track: "Sabotage!"}, recordings)
	assert.Equal(t, RecordingMatch{}, fuzzy)
	elsewhere := MatchRecording(RecordingQuery{Artist: "Beastie Boys", Track: "Sabotage", Album: ptr("Hello Nasty")}, recordings[:1])
	assert.Equal(t, recordingMatchG4("r-1", "", "a-1"), elsewhere)
}

func TestRecordingMatchTrustsTheSentIDWhateverTheSpelling(t *testing.T) {
	match := MatchRecording(
		RecordingQuery{Artist: "Beasties", Track: "Sabotage [Remastered]", RecordingMBID: ptr("r-1")},
		[]MusicBrainzRecording{mbRecordingG4(t, "r-1", "Sabotage", 100, [][3]string{{"Ill Communication", "rg-ill", "Album"}})},
	)
	assert.Equal(t, recordingMatchG4("r-1", "rg-ill", "a-1"), match)
}

func TestRecordingMatchAJoinedCreditMatchesTheWholeByline(t *testing.T) {
	var recording MusicBrainzRecording
	require.NoError(t, json.Unmarshal([]byte(`{"id":"r-9","score":100,"title":"The Boxer","artist-credit":[
	  {"name":"Simon","joinphrase":" & ","artist":{"id":"a-s"}},
	  {"name":"Garfunkel","joinphrase":"","artist":{"id":"a-g"}}],
	 "releases":[{"title":"Bridge over Troubled Water",
	   "release-group":{"id":"rg-b","title":"Bridge over Troubled Water","primary-type":"Album"}}]}`), &recording))
	match := MatchRecording(RecordingQuery{Artist: "Simon & Garfunkel", Track: "The Boxer"}, []MusicBrainzRecording{recording})
	require.NotNil(t, match.ReleaseGroupMBID)
	assert.Equal(t, "rg-b", *match.ReleaseGroupMBID)
	require.NotNil(t, match.ArtistMBID)
	assert.Equal(t, "a-s", *match.ArtistMBID, "the first credited artist")
}
