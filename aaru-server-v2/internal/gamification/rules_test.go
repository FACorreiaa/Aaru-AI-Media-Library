package gamification

import (
	"aaru-go-api/internal/core"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// setters set the fact a badge reads to a value (BadgeRuleTests).
func setters() map[string]func(*Facts, int) {
	m := map[string]func(*Facts, int){
		"first_film": func(f *Facts, v int) { f.FilmsFinished = v }, "films": func(f *Facts, v int) { f.FilmsFinished = v },
		"silver_screen":  func(f *Facts, v int) { f.FilmsBefore1960 = v },
		"double_feature": func(f *Facts, v int) { f.DoubleFeatureDays = v },
		"first_episode":  func(f *Facts, v int) { f.EpisodesTicked = v }, "episodes": func(f *Facts, v int) { f.EpisodesTicked = v },
		"shows": func(f *Facts, v int) { f.ShowsFinished = v }, "seasons": func(f *Facts, v int) { f.SeasonsComplete = v },
		"completionist": func(f *Facts, v int) { f.EndedShowsComplete = v },
		"long_haul":     func(f *Facts, v int) { f.LongShowsComplete = v },
		"binge":         func(f *Facts, v int) { f.BingedSeasons = v }, "marathon": func(f *Facts, v int) { f.MarathonDays = v },
		"day_one": func(f *Facts, v int) { f.DayOneEpisodes = v }, "finale_night": func(f *Facts, v int) { f.FinaleNights = v },
		"first_anime": func(f *Facts, v int) { f.AnimeFinished = v }, "anime": func(f *Facts, v int) { f.AnimeFinished = v },
		"anime_episodes": func(f *Facts, v int) { f.AnimeEpisodes = v },
		"first_book":     func(f *Facts, v int) { f.BooksFinished = v }, "books": func(f *Facts, v int) { f.BooksFinished = v },
		"pages": func(f *Facts, v int) { f.PagesRead = v }, "doorstopper": func(f *Facts, v int) { f.LongBooksFinished = v },
		"chapter_a_day": func(f *Facts, v int) { f.LongestBookRun = v },
		"first_listen":  func(f *Facts, v int) { f.Listens = v }, "listens": func(f *Facts, v int) { f.Listens = v },
		"artists": func(f *Facts, v int) { f.Artists = v }, "albums": func(f *Facts, v int) { f.AlbumsFinished = v },
		"first_rating": func(f *Facts, v int) { f.Ratings = v }, "ratings": func(f *Facts, v int) { f.Ratings = v },
		"perfect_ten": func(f *Facts, v int) { f.PerfectTens = v }, "notes": func(f *Facts, v int) { f.Notes = v },
		"first_list": func(f *Facts, v int) { f.Lists = v }, "lists": func(f *Facts, v int) { f.Lists = v },
		"first_shelf": func(f *Facts, v int) { f.Shelves = v }, "collector": func(f *Facts, v int) { f.Owned = v },
		"first_import": func(f *Facts, v int) { f.ImportsApplied = v },
		"genres":       func(f *Facts, v int) { f.Genres = v }, "decades": func(f *Facts, v int) { f.Decades = v },
		"networks": func(f *Facts, v int) { f.Networks = v },
		"streak":   func(f *Facts, v int) { f.LongestStreak = v }, "night_owl": func(f *Facts, v int) { f.NightOwlWrites = v },
		"first_friend": func(f *Facts, v int) { f.Friends = v }, "friends": func(f *Facts, v int) { f.Friends = v },
		"ambassador": func(f *Facts, v int) { f.InvitesRedeemed = v },
		"tastemaker": func(f *Facts, v int) { f.RecommendationsSent = v },
		"good_call":  func(f *Facts, v int) { f.RecommendationsAdded = v },
		"applause":   func(f *Facts, v int) { f.Reactions = v }, "watch_party": func(f *Facts, v int) { f.WatchParties = v },
	}
	m["tough_crowd"] = func(f *Facts, v int) {
		f.Ratings = 24
		if v >= 1 {
			f.Ratings = 25
		}
		mean := 4.5
		f.RatingMean = &mean
	}
	m["all_rounder"] = func(f *Facts, v int) {
		f.FilmsFinished, f.ShowsFinished, f.AnimeFinished, f.BooksFinished = 1, 1, 1, 1
		f.AlbumsFinished = boolInt(v >= 1)
	}
	m["comeback"] = func(f *Facts, v int) { f.Comeback = v >= 1 }
	m["sources"] = func(f *Facts, v int) {
		f.ImportSources = map[string]bool{}
		for _, stamp := range Stamps[:min(max(v, 0), len(Stamps))] {
			f.ImportSources[stamp.Sources[0]] = true
		}
	}
	for _, stamp := range Stamps {
		m["stamp_"+stamp.ID] = func(f *Facts, v int) {
			f.ImportSources = map[string]bool{}
			if v >= 1 {
				for _, src := range stamp.Sources {
					f.ImportSources[src] = true
				}
			}
		}
	}
	return m
}

func TestEveryBadgeHasARuleTest(t *testing.T) {
	set := setters()
	ids := map[string]bool{}
	hidden := 0
	for _, d := range Catalog {
		assert.Contains(t, set, d.ID)
		assert.False(t, ids[d.ID], "ids are unique: %s", d.ID)
		ids[d.ID] = true
		if d.Hidden {
			hidden++
		}
	}
	assert.Len(t, Catalog, 62)
	assert.Equal(t, 9, hidden)
	assert.Less(t, float64(hidden)/float64(len(Catalog)), 0.2, "about 15% hidden")
}

func TestEachTierStartsExactlyAtItsThreshold(t *testing.T) {
	set := setters()
	for _, d := range Catalog {
		t.Run(d.ID, func(t *testing.T) {
			apply := set[d.ID]
			require.NotNil(t, apply)
			for i, threshold := range d.Thresholds {
				var below, reached Facts
				apply(&below, threshold-1)
				assert.Equal(t, i, d.Tier(below), "%s at %d", d.ID, threshold-1)
				apply(&reached, threshold)
				assert.Equal(t, i+1, d.Tier(reached), "%s at %d", d.ID, threshold)
			}
			assert.Equal(t, 0, d.Tier(Facts{}), "with nothing")
		})
	}
}

func TestOnlyNotesAndOwnedBadgesArePrivate(t *testing.T) {
	var private []string
	for _, d := range Catalog {
		if d.Private {
			private = append(private, d.ID)
		}
	}
	assert.ElementsMatch(t, []string{"notes", "collector"}, private)
}

func TestBadgeCopy(t *testing.T) {
	assert.Equal(t, "Finish 1,000 films", ByID["films"].Describe(1000))
	assert.Equal(t, "Read 100,000 pages", ByID["pages"].Describe(100_000))
	assert.Equal(t, "Keep a 7 day streak", ByID["streak"].Describe(7))
	assert.Equal(t, "Join 1 watch party", ByID["watch_party"].Describe(1))
	assert.Equal(t, "Pogdesign CAT stamp", ByID["stamp_cat"].Name)
	assert.Equal(t, "Import from Pogdesign CAT", ByID["stamp_cat"].Describe(1))
}

func TestWriteFactsTicksComeFromTheInverse(t *testing.T) {
	item := uuid.New()
	two := core.EpisodeKey{Season: 1, Episode: 2}
	// Asked to watch 1 and 2; 1 was already watched, so the inverse unwatches only 2.
	facts := NewWriteFacts("episode")
	facts.Episodes(item, []core.EpisodeKey{two}, nil)
	assert.Equal(t, map[uuid.UUID][]core.EpisodeKey{item: {two}}, facts.Ticked)
	assert.Empty(t, facts.Unticked)
}

func TestWriteFactsFieldsAndKinds(t *testing.T) {
	item := uuid.New()
	ten, twenty := 10, 20
	before := ProgressFields{Status: core.StatusInProgress, BookPage: &ten}
	after := ProgressFields{Status: core.StatusFinished, BookPage: &twenty}

	finished := NewWriteFacts("update")
	finished.Fields(item, after, before)
	assert.True(t, finished.Finished[item])
	assert.True(t, finished.BookForward[item])

	undone := NewWriteFacts("undo")
	undone.Fields(item, before, after)
	assert.True(t, undone.Unfinished[item])

	imported := NewWriteFacts("import")
	imported.Fields(item, after, before)
	assert.True(t, imported.IsEmpty(), "imports and plans derive nothing")

	restored := NewWriteFacts("undo")
	restored.Inserted(item, core.StatusFinished)
	assert.True(t, restored.IsEmpty(), "an undo restoring a finished item is no finish")
}

func TestLevelsArePureFunctionsOfTotal(t *testing.T) {
	for _, c := range [][2]int{{-5, 1}, {0, 1}, {99, 1}, {100, 2}, {299, 2}, {300, 3}, {599, 3}, {600, 4}, {1000, 5}, {4500, 10}, {4499, 9}} {
		assert.Equal(t, c[1], LevelFor(c[0]), "%d", c[0])
		assert.LessOrEqual(t, LevelThreshold(c[1]), max(c[0], 0))
	}
}

func TestISOWeeks(t *testing.T) {
	assert.Equal(t, ISOWeek{Name: "2026-W43", From: "2026-10-19", Until: "2026-10-25"}, WeekContaining("2026-10-22"))
	assert.Equal(t, "2026-W01", WeekContaining("2026-01-01").Name)
	assert.Equal(t, "2026-W53", WeekContaining("2027-01-01").Name)
	assert.Equal(t, "2027-W01", WeekContaining("2027-01-04").Name)
	week, ok := WeekNamed("2026-W43")
	assert.True(t, ok)
	assert.Equal(t, "2026-10-19", week.From)
	_, ok = WeekNamed("2025-W53")
	assert.False(t, ok, "2025 has 52 weeks")
	_, ok = WeekNamed("nonsense")
	assert.False(t, ok)
}

func TestRootsCarryUppercaseIDs(t *testing.T) {
	title := uuid.MustParse("6f1c1b2e-0000-4000-8000-00000000abcd")
	assert.Equal(t, "ep:6F1C1B2E-0000-4000-8000-00000000ABCD:1:2", EpisodeRoot(title, core.EpisodeKey{Season: 1, Episode: 2}))
	a, b := uuid.New(), uuid.New()
	assert.Equal(t, FriendRoot(a, b), FriendRoot(b, a))
	assert.Equal(t, fmt.Sprintf("streak:%s:%d", "2026-10-01", 7), StreakRoot("2026-10-01", 7))
}
