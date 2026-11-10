package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTMDBScoresCarryTheVoteAndTheStartOfReviews(t *testing.T) {
	long := strings.Repeat("word ", 200)
	stub := routes(map[string]string{
		"/tv/1399": `{"vote_average":8.456,"vote_count":25000,"reviews":{"results":[
		  {"author":" ana ","content":"Slow  start,\n great end.","author_details":{"rating":9}},
		  {"author":"blank","content":"   "},
		  {"author":"bo","content":"` + long + `","author_details":{"rating":null}},
		  {"author":"cy","content":"Fine."},
		  {"author":"di","content":"A fourth."}]}}`,
	})
	scores, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).
		Scores(context.Background(), core.ExternalIDs{TMDB: "1399"}, core.MediaShow)
	require.NoError(t, err)
	require.NotNil(t, scores)
	assert.Equal(t, "TMDB", scores.Source)
	require.NotNil(t, scores.Score)
	assert.InDelta(t, 8.456, *scores.Score, 0.0001)
	assert.Equal(t, 25000, scores.Votes)
	require.Len(t, scores.Reviews, MaxScoreReviews, "a blank review is skipped and the rest are capped")
	assert.Equal(t, ScoreReview{Author: "ana", Rating: ptr(9.0), Excerpt: "Slow start, great end."}, scores.Reviews[0])
	assert.Nil(t, scores.Reviews[1].Rating)
	assert.LessOrEqual(t, len([]rune(scores.Reviews[1].Excerpt)), MaxReviewExcerpt)
	assert.Equal(t, "reviews", urlQuery(stub.first(t).URL).Get("append_to_response"))
}

func TestTMDBScoresWithNoVotesHaveNoScore(t *testing.T) {
	stub := routes(map[string]string{"/movie/7": `{"vote_average":0,"vote_count":0}`})
	tmdb := &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}
	scores, err := tmdb.Scores(context.Background(), core.ExternalIDs{TMDB: "7"}, core.MediaMovie)
	require.NoError(t, err)
	require.NotNil(t, scores)
	assert.Nil(t, scores.Score, "an unrated title is not a zero")
	assert.Empty(t, scores.Reviews)

	scores, err = tmdb.Scores(context.Background(), core.ExternalIDs{}, core.MediaMovie)
	require.NoError(t, err)
	assert.Nil(t, scores, "no id TMDB knows")
	scores, err = tmdb.Scores(context.Background(), core.ExternalIDs{TMDB: "7"}, core.MediaBook)
	require.NoError(t, err)
	assert.Nil(t, scores, "not a kind TMDB has")
}

func TestAniListScoresAreOutOfTen(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Media":{"averageScore":86,"popularity":412000}}}`})
	anilist := &AniList{Client: testClient(stub, "anilist")}
	scores, err := anilist.Scores(context.Background(), core.ExternalIDs{AniList: "21"}, core.MediaManga)
	require.NoError(t, err)
	require.NotNil(t, scores)
	assert.Equal(t, "AniList", scores.Source)
	require.NotNil(t, scores.Score)
	assert.InDelta(t, 8.6, *scores.Score, 0.0001)
	assert.Equal(t, 412000, scores.Popularity)
	assert.Contains(t, string(stub.first(t).Body), "type: MANGA")

	scores, err = anilist.Scores(context.Background(), core.ExternalIDs{TMDB: "1"}, core.MediaShow)
	require.NoError(t, err)
	assert.Nil(t, scores, "no id AniList knows")

	unscored := routes(map[string]string{"": `{"data":{"Media":{"averageScore":null,"popularity":12}}}`})
	scores, err = (&AniList{Client: testClient(unscored, "anilist")}).Scores(context.Background(), core.ExternalIDs{MAL: "5"}, core.MediaShow)
	require.NoError(t, err)
	require.NotNil(t, scores)
	assert.Nil(t, scores.Score)
}

type countedScores struct {
	name  string
	asked int
}

func (c *countedScores) Scores(context.Context, core.ExternalIDs, core.MediaType) (*Scores, error) {
	c.asked++
	return &Scores{Source: c.name}, nil
}

func TestScoreServicePicksTheProviderOfTheKindAndCaches(t *testing.T) {
	video, anime := &countedScores{name: "TMDB"}, &countedScores{name: "AniList"}
	s := NewScoreService(video, anime, nil)
	s.Now = func() time.Time { return time.Unix(1_800_000_000, 0) }
	require.True(t, s.Available())
	ctx := context.Background()
	source := func(title core.Title) string {
		title.ID = uuid.New()
		scores := s.For(ctx, title)
		if scores == nil {
			return ""
		}
		return scores.Source
	}
	assert.Equal(t, "TMDB", source(core.Title{Type: core.MediaMovie}))
	assert.Equal(t, "TMDB", source(core.Title{Type: core.MediaShow}))
	assert.Equal(t, "AniList", source(core.Title{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{AniList: "1"}}))
	assert.Equal(t, "TMDB", source(core.Title{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{TMDB: "1"}}),
		"an anime AniList has no id for is still a show on TMDB")
	assert.Equal(t, "AniList", source(core.Title{Type: core.MediaManga}))
	assert.Empty(t, source(core.Title{Type: core.MediaBook}), "books have no score source")

	film := core.Title{ID: uuid.New(), Type: core.MediaMovie}
	before := video.asked
	s.For(ctx, film)
	s.For(ctx, film)
	assert.Equal(t, before+1, video.asked, "one title is asked for once")

	assert.False(t, NewScoreService(struct{}{}, nil, nil).Available(), "a provider that scores nothing")
}
