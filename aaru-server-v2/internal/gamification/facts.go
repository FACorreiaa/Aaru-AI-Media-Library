package gamification

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"

	"github.com/google/uuid"
)

// facts gathers badge facts for one user (PostgresGamificationStore+Facts): library milestones
// (imports count), music, imports, social, then the ledger and streak days (live only).
func (s store) facts(ctx context.Context, userID uuid.UUID) (Facts, error) {
	var f Facts
	lib, err := s.q.GamificationLibraryFacts(ctx, userID)
	if err != nil {
		return f, fmt.Errorf("library facts: %w", err)
	}
	f.FilmsFinished, f.FilmsBefore1960 = int(lib.FilmsFinished), int(lib.FilmsBefore1960)
	f.ShowsFinished, f.AnimeFinished = int(lib.ShowsFinished), int(lib.AnimeFinished)
	f.BooksFinished, f.PagesRead, f.LongBooksFinished = int(lib.BooksFinished), int(lib.PagesRead), int(lib.LongBooksFinished)
	f.AlbumsFinished, f.Ratings, f.PerfectTens = int(lib.AlbumsFinished), int(lib.Ratings), int(lib.PerfectTens)
	if lib.HasRatingMean {
		mean := lib.RatingMean
		f.RatingMean = &mean
	}
	f.Notes, f.Owned, f.Decades = int(lib.Notes), int(lib.Owned), int(lib.Decades)

	spread, err := s.q.GamificationSpreadFacts(ctx, userID)
	if err != nil {
		return f, fmt.Errorf("spread facts: %w", err)
	}
	f.Genres, f.Networks = int(spread.Genres), int(spread.Networks)

	shows, err := s.q.GamificationShowFacts(ctx, userID)
	if err != nil {
		return f, fmt.Errorf("show facts: %w", err)
	}
	f.EpisodesTicked, f.AnimeEpisodes = int(shows.Episodes), int(shows.AnimeEpisodes)
	f.SeasonsComplete, f.EndedShowsComplete, f.LongShowsComplete = int(shows.Seasons), int(shows.EndedComplete), int(shows.LongComplete)

	other, err := s.q.GamificationOtherFacts(ctx, userID)
	if err != nil {
		return f, fmt.Errorf("other facts: %w", err)
	}
	f.Lists, f.Shelves, f.Listens, f.Artists = int(other.Lists), int(other.Shelves), int(other.Listens), int(other.Artists)
	f.Friends, f.InvitesRedeemed = int(other.Friends), int(other.InvitesRedeemed)
	f.RecommendationsSent, f.RecommendationsAdded = int(other.RecommendationsSent), int(other.RecommendationsAdded)
	f.Reactions = int(other.Reactions)

	sources, err := s.q.GamificationImportSources(ctx, userID)
	if err != nil {
		return f, fmt.Errorf("import sources: %w", err)
	}
	f.ImportSources = map[string]bool{}
	for _, src := range sources {
		f.ImportSources[src] = true
	}
	if len(sources) > 0 {
		f.ImportsApplied = 1
	}

	ledger, err := s.q.GamificationLedgerFacts(ctx, sqlc.GamificationLedgerFactsParams{StreakKinds: streakKinds(), UserID: userID})
	if err != nil {
		return f, fmt.Errorf("ledger facts: %w", err)
	}
	f.DoubleFeatureDays, f.MarathonDays, f.NightOwlWrites = int(ledger.DoubleFeatureDays), int(ledger.MarathonDays), int(ledger.NightOwl)
	f.WatchParties, f.DayOneEpisodes, f.FinaleNights, f.BingedSeasons = int(ledger.Parties), int(ledger.DayOne), int(ledger.Finales), int(ledger.Binged)

	bookDays, err := s.q.GamificationBookDays(ctx, userID)
	if err != nil {
		return f, fmt.Errorf("book days: %w", err)
	}
	days := make([]core.StreakDay, len(bookDays))
	for i, d := range bookDays {
		days[i] = core.StreakDay{Date: d}
	}
	for _, run := range core.StreakRuns(days) {
		f.LongestBookRun = max(f.LongestBookRun, run.Days)
	}

	streak, err := s.streakDays(ctx, userID)
	if err != nil {
		return f, err
	}
	runs := core.StreakRuns(streak)
	firstLong := -1
	for i, run := range runs {
		f.LongestStreak = max(f.LongestStreak, run.Days)
		if firstLong < 0 && run.Days >= 7 {
			firstLong = i
		}
	}
	if firstLong >= 0 {
		for _, run := range runs[firstLong+1:] {
			if run.Days >= 7 {
				f.Comeback = true
			}
		}
	}
	return f, nil
}
