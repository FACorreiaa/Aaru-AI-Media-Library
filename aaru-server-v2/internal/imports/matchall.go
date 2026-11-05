package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/safe"
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Match all (IMP-021). The searches run outside any transaction, a few at a time and only for a few
// seconds a call, which is why the client calls again: Open Library asks for about 3 requests a
// second, and the API's requests stop at 30 seconds. The plan is saved under the job's lock.
const (
	matchAllSearches = 3
	matchAllBudget   = 15 * time.Second
)

// MatchAllResult is one call's work.
type MatchAllResult struct {
	Job core.ImportJob
	// Rows are the rows this call changed.
	Rows []PlannedRow
	// Remaining is how many unmatched rows are still to try.
	Remaining int
}

// Guessable is whether Match all has yet to try this row.
func Guessable(r PlannedRow) bool {
	return r.Outcome == OutcomeUnmatched && r.Row.Unsupported == nil && !isTrue(r.Row.GuessTried) &&
		strings.TrimSpace(r.Row.Title) != ""
}

// MatchAll looks for a best guess for the plan's unmatched rows. A guess joins the plan as a pick
// does, and nothing reaches the library until the person approves.
func (s *Service) MatchAll(ctx context.Context, id, user uuid.UUID) (MatchAllResult, error) {
	stored, err := s.Store.Job(ctx, id, user)
	if err != nil {
		return MatchAllResult{}, err
	}
	if stored == nil {
		return MatchAllResult{}, apperr.NotFound()
	}
	if err := notPlanned(stored.State); err != nil {
		return MatchAllResult{}, err
	}
	rows, err := s.Store.Rows(ctx, id)
	if err != nil {
		return MatchAllResult{}, err
	}
	found := s.guessRows(ctx, rows)

	var result MatchAllResult
	err = pgx.BeginFunc(ctx, s.Store.Pool, func(tx pgx.Tx) error {
		if err := s.lockPlanned(ctx, tx, id, user); err != nil {
			return err
		}
		store := &Store{Q: s.Store.Q.WithTx(tx)}
		locked, err := store.Job(ctx, id, user)
		if err != nil {
			return err
		}
		if locked == nil {
			return apperr.NotFound()
		}
		now, err := store.Rows(ctx, id)
		if err != nil {
			return err
		}
		touched := map[int]bool{}
		for i, row := range now {
			// A row the person matched while this searched stays theirs.
			if guessed, ok := found[row.Index]; ok && row.Outcome == OutcomeUnmatched {
				now[i] = guessed
				touched[row.Index] = true
			}
		}
		decided := now
		if len(touched) > 0 {
			if decided, err = s.Decided(ctx, now, user); err != nil {
				return err
			}
		}
		result.Job = *locked
		for i := range decided {
			before := now[i]
			if touched[decided[i].Index] || before.Outcome != decided[i].Outcome || !equalReason(before.Reason, decided[i].Reason) {
				result.Rows = append(result.Rows, decided[i])
			}
			if Guessable(decided[i]) {
				result.Remaining++
			}
		}
		if len(result.Rows) == 0 {
			return nil
		}
		result.Job.Stats = Stats(decided)
		result.Job.UpdatedAt = s.now()
		return s.Store.SavePlanTx(ctx, tx, result.Job, result.Rows)
	})
	if err != nil {
		return MatchAllResult{}, err
	}
	return result, nil
}

// guessRows tries as many rows as the budget allows and answers those it finished, by index. A row
// whose search failed is left out, to be tried again.
func (s *Service) guessRows(ctx context.Context, rows []PlannedRow) map[int]PlannedRow {
	budget, cancel := context.WithTimeout(ctx, matchAllBudget)
	defer cancel()
	resolver := s.Resolver()
	var mu sync.Mutex
	found := map[int]PlannedRow{}
	g, gctx := safe.WithContext(budget)
	g.SetLimit(matchAllSearches)
	for _, row := range rows {
		if !Guessable(row) {
			continue
		}
		g.Go(func() error {
			if gctx.Err() != nil {
				return nil
			}
			row.Row.GuessTried = ptr(true)
			guess, err := resolver.Guess(gctx, row.Row.Type, row.Row.Title, row.Row.Author, row.Row.Year)
			if err == nil && guess != nil {
				titleID := guess.Title.ID
				row.TitleID = &titleID
				row.Row.Type = guess.Title.Type
				row.Row.Guess = &RowGuess{Title: guess.Title.Title, Byline: guess.Byline, PosterURL: guess.PosterURL}
				row.Outcome = OutcomePending
				err = numberNamedEpisodes(gctx, &row.Row, guess.Title, resolver)
			}
			if err != nil {
				if !errors.Is(err, context.DeadlineExceeded) && !errors.Is(err, context.Canceled) {
					s.log().Warn("Match all could not guess a row", "error", err)
				}
				return nil
			}
			mu.Lock()
			found[row.Index] = row
			mu.Unlock()
			return nil
		})
	}
	// Each step answers nil: a failed row must not stop the others.
	_ = g.Wait()
	return found
}
