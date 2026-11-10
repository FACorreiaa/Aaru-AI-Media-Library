package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"
)

// Audience scores for the assistant (ASK-011): TMDB's for films and shows, AniList's for anime and
// manga. Catalog data like a synopsis: read when asked, cached in memory, never stored on a Title
// and never the user's own rating.

const (
	// ScoresTTL is how long a score is served from memory: it moves slowly, and six hours keeps the
	// providers quiet.
	ScoresTTL = 6 * time.Hour
	// ScoresCacheCapacity bounds the titles whose scores are held.
	ScoresCacheCapacity = 500
	// MaxScoreReviews is how many user reviews one answer carries.
	MaxScoreReviews = 3
	// MaxReviewExcerpt is how much of each, in characters.
	MaxReviewExcerpt = 400
)

// Scores is what one provider's audience says of a title.
type Scores struct {
	// Source is the provider's name as it is credited: "TMDB", "AniList".
	Source string
	// Score is out of ten. Nil when the provider has too few votes to give one.
	Score *float64
	// Votes is how many ratings Score rests on; 0 when the provider does not say.
	Votes int
	// Popularity is how many of the provider's users keep it; 0 when it does not say.
	Popularity int
	Reviews    []ScoreReview
}

// ScoreReview is the start of one user review. Its words are the reviewer's, never checked.
type ScoreReview struct {
	Author string
	// Rating is the reviewer's own, out of ten.
	Rating  *float64
	Excerpt string
}

// ScoreSource is a provider that scores titles. Nil, with no error, when it does not know the title.
type ScoreSource interface {
	Scores(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Scores, error)
}

// ScoreService reads a title's scores from the provider that owns its kind.
type ScoreService struct {
	// Video scores films and shows; Anime scores anime and manga. Either may be nil.
	Video, Anime ScoreSource
	cache        *sharedCache[string, scoresFetch]
	Now          func() time.Time
}

type scoresFetch struct{ scores *Scores }

// NewScoreService builds the service; a provider that is no ScoreSource leaves its kinds unscored.
func NewScoreService(video, anime any, log *slog.Logger) *ScoreService {
	s := &ScoreService{cache: newSharedCache[string, scoresFetch](ScoresCacheCapacity, "Title scores failed"), Now: time.Now}
	s.cache.log = log
	if source, ok := video.(ScoreSource); ok && source != nil {
		s.Video = source
	}
	if source, ok := anime.(ScoreSource); ok && source != nil {
		s.Anime = source
	}
	return s
}

// Available says whether any provider scores anything: without one the assistant has no tool for it.
func (s *ScoreService) Available() bool { return s != nil && (s.Video != nil || s.Anime != nil) }

// For is the title's scores; nil when no provider scores its kind, knows it, or answered.
func (s *ScoreService) For(ctx context.Context, title core.Title) *Scores {
	source := s.source(title)
	if source == nil {
		return nil
	}
	fetched, ok := s.cache.get(ctx, title.ID.String(), s.Now(), func(scoresFetch) time.Duration { return ScoresTTL },
		func(ctx context.Context) (scoresFetch, error) {
			scores, err := source.Scores(ctx, title.IDs, title.Type)
			if err != nil {
				return scoresFetch{}, fmt.Errorf("title scores: %w", err)
			}
			return scoresFetch{scores: scores}, nil
		})
	if !ok {
		return nil
	}
	return fetched.scores
}

// source is the provider for the title's kind: AniList for manga and for anime it has an id for,
// TMDB for every other film and show.
func (s *ScoreService) source(title core.Title) ScoreSource {
	switch title.Type {
	case core.MediaManga:
		return s.Anime
	case core.MediaMovie, core.MediaShow:
		if title.IsAnime && s.Anime != nil && (title.IDs.AniList != "" || title.IDs.MAL != "") {
			return s.Anime
		}
		return s.Video
	default:
		return nil
	}
}

// MARK: - TMDB

type tmdbScores struct {
	VoteAverage float64 `json:"vote_average"`
	VoteCount   int     `json:"vote_count"`
	Reviews     struct {
		Results []struct {
			Author        string `json:"author"`
			Content       string `json:"content"`
			AuthorDetails struct {
				Rating *float64 `json:"rating"`
			} `json:"author_details"`
		} `json:"results"`
	} `json:"reviews"`
}

// Scores is TMDB's vote average and count, with the start of its first user reviews.
func (t *TMDB) Scores(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Scores, error) {
	kind, err := tmdbKind(mediaType)
	if err != nil {
		return nil, nil //nolint:nilnil,nilerr // not a kind TMDB has
	}
	id, err := t.tmdbID(ctx, ids, kind)
	if err != nil {
		return nil, err
	}
	if id == "" {
		return nil, nil //nolint:nilnil // TMDB does not know these ids
	}
	var detail tmdbScores
	if err := t.get(ctx, kind+"/"+id, map[string]string{"append_to_response": "reviews"}, &detail); err != nil {
		return nil, err
	}
	scores := &Scores{Source: "TMDB", Votes: detail.VoteCount}
	if detail.VoteCount > 0 {
		scores.Score = &detail.VoteAverage
	}
	for _, r := range detail.Reviews.Results {
		excerpt := core.Prefix(strings.Join(strings.Fields(r.Content), " "), MaxReviewExcerpt)
		if excerpt == "" {
			continue
		}
		scores.Reviews = append(scores.Reviews, ScoreReview{
			Author: strings.TrimSpace(r.Author), Rating: r.AuthorDetails.Rating, Excerpt: excerpt,
		})
		if len(scores.Reviews) == MaxScoreReviews {
			break
		}
	}
	return scores, nil
}

// MARK: - AniList

// Scores is AniList's average score, out of ten here, and how many of its users list the title.
func (a *AniList) Scores(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Scores, error) {
	var selector string
	var id int
	if n, err := strconv.Atoi(ids.AniList); ids.AniList != "" && err == nil {
		selector, id = "id: $id", n
	} else if n, err := strconv.Atoi(ids.MAL); ids.MAL != "" && err == nil {
		selector, id = "idMal: $id", n
	} else {
		return nil, nil //nolint:nilnil // AniList does not know these ids
	}
	var body struct {
		Media *struct {
			AverageScore *int `json:"averageScore"`
			Popularity   *int `json:"popularity"`
		} `json:"Media"`
	}
	err := a.post(ctx, fmt.Sprintf(`query ($id: Int) {
  Media(%s, type: %s) { averageScore popularity }
}`, selector, aniListType(mediaType)), map[string]any{"id": id}, &body)
	if err != nil || body.Media == nil {
		if err == nil || provider.IsNotFound(err) {
			return nil, nil //nolint:nilnil // AniList does not know these ids
		}
		return nil, err
	}
	scores := &Scores{Source: "AniList"}
	if body.Media.AverageScore != nil && *body.Media.AverageScore > 0 {
		score := float64(*body.Media.AverageScore) / 10
		scores.Score = &score
	}
	if body.Media.Popularity != nil {
		scores.Popularity = *body.Media.Popularity
	}
	return scores, nil
}
