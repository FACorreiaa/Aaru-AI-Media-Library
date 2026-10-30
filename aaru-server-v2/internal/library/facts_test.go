package library

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

// BadgeRuleTests.swift LibraryWriteFactsTests: what a library write earns comes from the op and its
// inverse (LibraryWriteFacts.derive), walked by collectFacts.

// ticks
func TestFactsTicksComeFromTheInverseNotTheRequest(t *testing.T) {
	item := uuid.New()
	one, two := core.EpisodeKey{Season: 1, Episode: 1}, core.EpisodeKey{Season: 1, Episode: 2}
	// Asked to watch 1 and 2; 1 was already watched, so the inverse unwatches only 2.
	facts := gamification.NewWriteFacts("episode")
	collectFacts(facts, SetEpisodes(item, []core.EpisodeKey{one, two}, nil), SetEpisodes(item, nil, []core.EpisodeKey{two}))
	assert.Equal(t, map[uuid.UUID][]core.EpisodeKey{item: {two}}, facts.Ticked)
	assert.Empty(t, facts.Unticked)
}

// fields
func TestFactsFinishingUnfinishingAndPagesImportsAndPlansDeriveNothing(t *testing.T) {
	item := uuid.New()
	ten, twenty := 10, 20
	before := ItemFields{Status: core.StatusInProgress, BookPage: &ten}
	after := ItemFields{Status: core.StatusFinished, BookPage: &twenty}

	finished := gamification.NewWriteFacts("update")
	collectFacts(finished, SetFields(item, after), SetFields(item, before))
	assert.True(t, finished.Finished[item])
	assert.True(t, finished.BookForward[item])

	undone := gamification.NewWriteFacts("undo")
	collectFacts(undone, SetFields(item, before), SetFields(item, after))
	assert.True(t, undone.Unfinished[item])

	for _, kind := range []string{"import", "plan"} {
		facts := gamification.NewWriteFacts(kind)
		collectFacts(facts, SetFields(item, after), SetFields(item, before))
		assert.True(t, facts.IsEmpty(), kind)
	}

	// A batch's inverses come back reversed.
	batch := gamification.NewWriteFacts("episode")
	collectFacts(batch,
		Batch(SetFields(item, after), SetEpisodes(item, []core.EpisodeKey{{Season: 1, Episode: 1}}, nil)),
		Batch(SetEpisodes(item, nil, []core.EpisodeKey{{Season: 1, Episode: 1}}), SetFields(item, before)))
	assert.True(t, batch.Finished[item])
	assert.Len(t, batch.Ticked[item], 1)
}
