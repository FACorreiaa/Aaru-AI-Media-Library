package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ImportSpeedTests.aniListBatches (IMP-017): AniList answers MAL ids 50 at a time, keyed by MAL
// id; an id it does not know is just missing.
func TestAniListHydrateMALBatchesFiftyAtATime(t *testing.T) {
	stub := &stubTransport{handle: func(req provider.Request) provider.Response {
		var body struct {
			Variables struct {
				IDs []int `json:"ids"`
			} `json:"variables"`
		}
		_ = json.Unmarshal(req.Body, &body)
		var media []string
		for _, id := range body.Variables.IDs {
			if id == 7 {
				continue
			}
			media = append(media, fmt.Sprintf(`{"id":%d,"idMal":%d,"format":"TV","title":{"romaji":"Show %d"}}`, id+100_000, id, id))
		}
		return provider.Response{Status: 200, Body: []byte(`{"data":{"Page":{"media":[` + strings.Join(media, ",") + `]}}}`)}
	}}
	anilist := &AniList{Client: testClient(stub, "anilist"), UserAgent: "Aaru-test"}
	ids := make([]string, 0, 122)
	for i := 1; i <= 120; i++ {
		ids = append(ids, strconv.Itoa(i))
	}
	titles, err := anilist.HydrateMAL(context.Background(), append(ids, "5", "x"), core.MediaShow)
	require.NoError(t, err)

	assert.Len(t, stub.all(), 3, "120 ids, 50 per request")
	assert.Len(t, titles, 119)
	assert.NotContains(t, titles, "7")
	require.Contains(t, titles, "42")
	assert.Equal(t, core.ExternalIDs{AniList: "100042", MAL: "42"}, titles["42"].Hit.IDs)
	assert.Contains(t, string(stub.first(t).Body), "idMal_in")
}
