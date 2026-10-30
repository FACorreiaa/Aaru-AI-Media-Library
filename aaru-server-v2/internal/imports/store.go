package imports

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is import jobs as a leased queue (JOB-001) plus their parsed rows (IMP-001)
// (PostgresImportJobStore).
type Store struct {
	Pool *pgxpool.Pool
	Q    *sqlc.Queries
}

// NewStore builds the store over a pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{Pool: pool, Q: sqlc.New(pool)} }

// insertChunk is rows per INSERT or UPDATE: a 2,000-row export is four round trips, not 2,000.
const insertChunk = 500

// ClaimedJob is a leased job and how many times it has been tried, this one included.
type ClaimedJob struct {
	Job      core.ImportJob
	Attempts int
}

// jobFields is the columns every job read selects.
type jobFields struct {
	id, userID             uuid.UUID
	source, state          string
	stats                  json.RawMessage
	errorSummary, filename *string
	createdAt, updatedAt   time.Time
	rowsMatched, rowsTotal int32
	listensStaged          int32
	actionID               *uuid.UUID
}

func (f jobFields) job() (core.ImportJob, bool) {
	source, state := core.ImportSource(f.source), core.ImportJobState(f.state)
	if !source.Valid() || !validState(state) {
		return core.ImportJob{}, false
	}
	var stats core.ImportStats
	if len(f.stats) > 0 {
		if err := json.Unmarshal(f.stats, &stats); err != nil {
			return core.ImportJob{}, false
		}
	}
	// A listening import's plays leave staging when applied (MUS-004); its counts stay.
	total := int(f.rowsTotal)
	if source.IsListens() {
		total = max(int(f.listensStaged), stats.Created+stats.Skipped)
	}
	return core.ImportJob{
		ID: f.id, UserID: f.userID, Source: source, State: state, Stats: stats, ErrorSummary: f.errorSummary,
		Filename: f.filename, CreatedAt: f.createdAt.UTC(), UpdatedAt: f.updatedAt.UTC(), RowsTotal: total,
		RowsMatched: int(f.rowsMatched), ActionID: f.actionID,
	}, true
}

func validState(s core.ImportJobState) bool {
	for _, known := range core.ImportJobStates {
		if s == known {
			return true
		}
	}
	return false
}

func statsJSON(s core.ImportStats) json.RawMessage {
	data, _ := json.Marshal(s) //nolint:errchkjson // plain ints
	return data
}

// Insert writes a job and its rows in one transaction.
func (s *Store) Insert(ctx context.Context, job core.ImportJob, rows []Row) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.ImportJobInsert(ctx, sqlc.ImportJobInsertParams{
			ID: job.ID, UserID: job.UserID, Source: string(job.Source), State: string(job.State),
			Stats: statsJSON(job.Stats), ErrorSummary: job.ErrorSummary, Filename: job.Filename,
			CreatedAt: job.CreatedAt, UpdatedAt: job.UpdatedAt,
		}); err != nil {
			return fmt.Errorf("insert import job: %w", err)
		}
		return insertRows(ctx, q, rows, job.ID)
	})
}

// AppendRows adds the rows a source gave (Trakt, AniList, a capture) to a job that had none.
func (s *Store) AppendRows(ctx context.Context, rows []Row, jobID uuid.UUID) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		return insertRows(ctx, s.Q.WithTx(tx), rows, jobID)
	})
}

func insertRows(ctx context.Context, q *sqlc.Queries, rows []Row, jobID uuid.UUID) error {
	for start := 0; start < len(rows); start += insertChunk {
		end := min(start+insertChunk, len(rows))
		idx := make([]int32, 0, end-start)
		data := make([]json.RawMessage, 0, end-start)
		for i := start; i < end; i++ {
			encoded, err := json.Marshal(rows[i])
			if err != nil {
				return fmt.Errorf("encode import row: %w", err)
			}
			idx = append(idx, int32(i)) //nolint:gosec // a row index
			data = append(data, encoded)
		}
		if err := q.ImportRowsInsert(ctx, sqlc.ImportRowsInsertParams{JobID: jobID, Idx: idx, Rows: data}); err != nil {
			return fmt.Errorf("insert import rows: %w", err)
		}
	}
	return nil
}

// Update saves a job's state, stats and error, and drops its lease.
func (s *Store) Update(ctx context.Context, job core.ImportJob) error {
	if err := s.Q.ImportJobUpdate(ctx, sqlc.ImportJobUpdateParams{
		State: string(job.State), Stats: statsJSON(job.Stats), ErrorSummary: job.ErrorSummary,
		UpdatedAt: job.UpdatedAt, ID: job.ID, UserID: job.UserID,
	}); err != nil {
		return fmt.Errorf("update import job: %w", err)
	}
	return nil
}

// Job is one of the user's jobs, nil when they have no such job.
func (s *Store) Job(ctx context.Context, id, user uuid.UUID) (*core.ImportJob, error) {
	r, err := s.Q.ImportJobGet(ctx, sqlc.ImportJobGetParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // no such job
	}
	if err != nil {
		return nil, fmt.Errorf("import job: %w", err)
	}
	job, ok := jobFields{
		r.ID, r.UserID, r.Source, r.State, r.Stats, r.ErrorSummary, r.Filename, r.CreatedAt, r.UpdatedAt,
		r.RowsMatched, r.RowsTotal, r.ListensStaged, r.ActionID,
	}.job()
	if !ok {
		return nil, nil //nolint:nilnil // no such job
	}
	return &job, nil
}

// Jobs are the user's latest jobs, newest first.
func (s *Store) Jobs(ctx context.Context, user uuid.UUID, limit int) ([]core.ImportJob, error) {
	rows, err := s.Q.ImportJobsByUser(ctx, sqlc.ImportJobsByUserParams{
		UserID: user, RowLimit: int32(max(1, min(limit, 100))), //nolint:gosec // clamped
	})
	if err != nil {
		return nil, fmt.Errorf("import jobs: %w", err)
	}
	out := make([]core.ImportJob, 0, len(rows))
	for _, r := range rows {
		if job, ok := (jobFields{
			r.ID, r.UserID, r.Source, r.State, r.Stats, r.ErrorSummary, r.Filename, r.CreatedAt, r.UpdatedAt,
			r.RowsMatched, r.RowsTotal, r.ListensStaged, r.ActionID,
		}).job(); ok {
			out = append(out, job)
		}
	}
	return out, nil
}

// ClaimNext leases the oldest runnable job (queued and due, or running past its lease). owner
// limits it to one user's jobs, for tests running side by side.
func (s *Store) ClaimNext(ctx context.Context, now time.Time, lease time.Duration, owner *uuid.UUID) (*ClaimedJob, error) {
	until := now.Add(lease)
	r, err := s.Q.ImportJobClaim(ctx, sqlc.ImportJobClaimParams{LockedUntil: &until, Now: now, Owner: owner})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // no such job
	}
	if err != nil {
		return nil, fmt.Errorf("claim import job: %w", err)
	}
	job, ok := jobFields{
		r.ID, r.UserID, r.Source, r.State, r.Stats, r.ErrorSummary, r.Filename, r.CreatedAt, r.UpdatedAt,
		r.RowsMatched, r.RowsTotal, r.ListensStaged, r.ActionID,
	}.job()
	if !ok {
		return nil, nil //nolint:nilnil // no such job
	}
	return &ClaimedJob{Job: job, Attempts: int(r.Attempts)}, nil
}

// Retry queues a failed attempt again, not before notBefore.
func (s *Store) Retry(ctx context.Context, id uuid.UUID, summary string, notBefore, now time.Time) error {
	if err := s.Q.ImportJobRetry(ctx, sqlc.ImportJobRetryParams{
		ErrorSummary: &summary, NotBefore: &notBefore, Now: now, ID: id,
	}); err != nil {
		return fmt.Errorf("retry import job: %w", err)
	}
	return nil
}

// Release hands a running job back untouched, its attempt uncounted (a shutdown).
func (s *Store) Release(ctx context.Context, id uuid.UUID, now time.Time) error {
	if err := s.Q.ImportJobRelease(ctx, sqlc.ImportJobReleaseParams{Now: now, ID: id}); err != nil {
		return fmt.Errorf("release import job: %w", err)
	}
	return nil
}

// Progress records rows matched so far and renews the lease (IMP-017).
func (s *Store) Progress(ctx context.Context, id uuid.UUID, matched int, lockedUntil time.Time) error {
	if err := s.Q.ImportJobProgress(ctx, sqlc.ImportJobProgressParams{
		RowsMatched: int32(matched), LockedUntil: &lockedUntil, ID: id, //nolint:gosec // a row count
	}); err != nil {
		return fmt.Errorf("import progress: %w", err)
	}
	return nil
}

// Rows are a job's rows with their plan, in file order.
func (s *Store) Rows(ctx context.Context, jobID uuid.UUID) ([]PlannedRow, error) {
	stored, err := s.Q.ImportRows(ctx, jobID)
	if err != nil {
		return nil, fmt.Errorf("import rows: %w", err)
	}
	out := make([]PlannedRow, 0, len(stored))
	for _, r := range stored {
		var row Row
		if err := json.Unmarshal(r.Row, &row); err != nil {
			return nil, fmt.Errorf("decode import row %d: %w", r.Idx, err)
		}
		outcome := Outcome(r.Outcome)
		switch outcome {
		case OutcomePending, OutcomeCreate, OutcomeUpdate, OutcomeSkip, OutcomeUnmatched:
		default:
			outcome = OutcomePending
		}
		out = append(out, PlannedRow{Index: int(r.Idx), Row: row, Outcome: outcome, Reason: r.Reason, TitleID: r.TitleID})
	}
	return out, nil
}

// SavePlan writes rows' outcomes (and their rows, which planning may have changed) and the job's
// state in one transaction.
//
// Written with pgx rather than sqlc: the bulk UPDATE … FROM unnest of five parallel arrays has
// nullable elements (reason, title id), which sqlc's array parameters cannot carry.
func (s *Store) SavePlan(ctx context.Context, job core.ImportJob, rows []PlannedRow) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		for start := 0; start < len(rows); start += insertChunk {
			chunk := rows[start:min(start+insertChunk, len(rows))]
			idx := make([]int32, len(chunk))
			outcomes := make([]string, len(chunk))
			reasons := make([]*string, len(chunk))
			titles := make([]*uuid.UUID, len(chunk))
			data := make([]string, len(chunk))
			for i, r := range chunk {
				encoded, err := json.Marshal(r.Row)
				if err != nil {
					return fmt.Errorf("encode import row: %w", err)
				}
				idx[i] = int32(r.Index) //nolint:gosec // a row index
				outcomes[i], reasons[i], titles[i], data[i] = string(r.Outcome), r.Reason, r.TitleID, string(encoded)
			}
			if _, err := tx.Exec(ctx, `
				UPDATE import_rows r SET outcome = v.outcome, reason = v.reason, title_id = v.title_id, row = v.row
				FROM unnest($2::int[], $3::text[], $4::text[], $5::uuid[], $6::jsonb[]) AS v(idx, outcome, reason, title_id, row)
				WHERE r.job_id = $1 AND r.idx = v.idx`,
				job.ID, idx, outcomes, reasons, titles, data,
			); err != nil {
				return fmt.Errorf("save import plan rows: %w", err)
			}
		}
		if err := s.Q.WithTx(tx).ImportJobSavePlan(ctx, sqlc.ImportJobSavePlanParams{
			State: string(job.State), Stats: statsJSON(job.Stats), ErrorSummary: job.ErrorSummary,
			UpdatedAt: job.UpdatedAt, ActionID: job.ActionID, ID: job.ID,
		}); err != nil {
			return fmt.Errorf("save import plan: %w", err)
		}
		return nil
	})
}

// Delete removes one of the user's jobs; false when there was none.
func (s *Store) Delete(ctx context.Context, id, user uuid.UUID) (bool, error) {
	_, err := s.Q.ImportJobDelete(ctx, sqlc.ImportJobDeleteParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("delete import job: %w", err)
	}
	return true, nil
}
