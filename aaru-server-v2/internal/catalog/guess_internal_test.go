package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// IMP-021: how a book is guessed, and what the strict match still refuses.

func strPointer(s string) *string { return &s }

func bookHit(title, byline string) Hit {
	return Hit{Type: core.MediaBook, Title: title, Byline: &byline}
}

func TestBookGuessScoreWantsTheAuthorAndEnoughOfTheTitle(t *testing.T) {
	const name = "X-Men: Days of Future Past"
	assert.Positive(t, bookGuessScore(name, "Chris Claremont", bookHit("Days of Future Past", "Chris Claremont, John Byrne")))
	assert.Zero(t, bookGuessScore(name, "Chris Claremont", bookHit("Days of Future Past", "Alex Irvine")),
		"by someone else: never a guess, however close the title")
	assert.Zero(t, bookGuessScore(name, "Chris Claremont", bookHit("X-Men", "Chris Claremont")),
		"the series name alone says too little")
	assert.Zero(t, bookGuessScore("Second Coming", "Matt Fraction", bookHit("The second coming", "Walker Percy")))
}

func TestBookGuessScorePrefersTheCloserHit(t *testing.T) {
	const name = "Astonishing X-Men: Gifted"
	bare := bookHit("Astonishing X-Men", "Joss Whedon")
	subtitled := bare
	subtitled.Subtitle = strPointer("Gifted")
	assert.Greater(t, bookGuessScore(name, "Joss Whedon", subtitled), bookGuessScore(name, "Joss Whedon", bare))
}

func TestAuthorWeightAcceptsNameOrderAndLastName(t *testing.T) {
	assert.InDelta(t, 1.5, authorWeight("Chris Claremont", strPointer("John Byrne, Chris Claremont")), 0)
	assert.InDelta(t, 1, authorWeight("Liu Cixin", strPointer("Cixin Liu")), 0)
	assert.InDelta(t, 1, authorWeight("Andrew Hunt", strPointer("Andy Hunt")), 0)
	assert.Zero(t, authorWeight("Chris Claremont", strPointer("Walker Percy")))
	assert.Zero(t, authorWeight("Chris Claremont", nil))
}

type guessSearcher struct {
	hits map[string][]Hit
	err  error
}

func (g guessSearcher) Search(_ context.Context, query string, _ core.MediaType) ([]Hit, error) {
	return g.hits[query], g.err
}

func (g guessSearcher) Hydrate(context.Context, core.ExternalIDs, core.MediaType) (*Record, error) {
	return nil, nil
}

func TestGuessBookWithoutAnAuthorTakesOnlyAnExactTitle(t *testing.T) {
	r := Resolver{Providers: Providers{OpenLibrary: guessSearcher{hits: map[string][]Hit{
		"Dune":    {bookHit("Dune Messiah", "Frank Herbert"), bookHit("Dune", "Frank Herbert")},
		"Inferno": {bookHit("Inferno Rising", "Someone")},
	}}}}
	hit, err := r.guessBook(context.Background(), "Dune", nil)
	require.NoError(t, err)
	require.NotNil(t, hit)
	assert.Equal(t, "Dune", hit.Title)

	hit, err = r.guessBook(context.Background(), "Inferno", nil)
	require.NoError(t, err)
	assert.Nil(t, hit)
}

func TestGuessBookSearchesTheSubtitleWithTheAuthor(t *testing.T) {
	r := Resolver{Providers: Providers{OpenLibrary: guessSearcher{hits: map[string][]Hit{
		"Days of Future Past Chris Claremont": {bookHit("Days of Future Past", "Chris Claremont")},
	}}}}
	author := "Chris Claremont"
	hit, err := r.guessBook(context.Background(), "X-Men: Days of Future Past", &author)
	require.NoError(t, err)
	require.NotNil(t, hit)
	assert.Equal(t, "Days of Future Past", hit.Title)
}

func TestGuessByNameWantsTheExactNameAndPrefersTheYear(t *testing.T) {
	year := 2012
	older, newer := 1990, 2012
	first, second := Hit{Title: "Total Recall", Year: &older}, Hit{Title: "Total Recall", Year: &newer}
	searcher := guessSearcher{hits: map[string][]Hit{"Total Recall": {first, second}, "Heat": {{Title: "Heat Wave"}}}}

	hit, err := guessByName(context.Background(), searcher, core.MediaMovie, "Total Recall", &year)
	require.NoError(t, err)
	assert.Equal(t, &newer, hit.Year)
	hit, err = guessByName(context.Background(), searcher, core.MediaMovie, "Total Recall", nil)
	require.NoError(t, err)
	assert.Equal(t, &older, hit.Year)
	hit, err = guessByName(context.Background(), searcher, core.MediaMovie, "Heat", nil)
	require.NoError(t, err)
	assert.Nil(t, hit)
	hit, err = guessByName(context.Background(), nil, core.MediaMovie, "Heat", nil)
	require.NoError(t, err)
	assert.Nil(t, hit, "a catalog that is off has no guess")
}

func TestStrictAuthorMatchRefusesASeriesItCannotTellApart(t *testing.T) {
	r := Resolver{Providers: Providers{OpenLibrary: guessSearcher{hits: map[string][]Hit{
		"X-Men Chris Claremont": {bookHit("X-Men", "Chris Claremont"), bookHit("X-Men", "Chris Claremont")},
	}}}}
	_, err := r.ResolveBookByAuthor(context.Background(), "X-Men: Days of Future Past", "Chris Claremont")
	require.True(t, errors.Is(err, ErrUnresolvable), "%v", err)
}
