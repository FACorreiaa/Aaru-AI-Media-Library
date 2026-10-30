// Package imports is file and account imports (Imports/*.swift): upload or connect → a leased job
// matches every row and builds a plan → the user approves → the plan is written as one journaled,
// undoable action (IMP-001, IMP-004, IMP-005). Nothing touches the library before the approval.
//
// The API other areas call:
//
//   - Service.CreateCSVImport / CreateCATImport / CreateAniListImport / CreateTraktImport /
//     CreateCapture / CreateListen*Import: start a job (the agent's import tools call these too).
//   - Service.Jobs / Detail / Delete / Apply / ResolveRow / UndoListens: the job's life.
//   - Service.RunNext: the worker's step (Worker runs it in IMPORTS_WORKERS loops).
//   - Service.ApplyFromMAL: SCR-010's read-back, merged and written at once.
//   - Decide / Merged: the merge rules (CLAUDE.md "Merging sources").
package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/telemetry"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
)

// The limits Swift's ImportService kept.
const (
	// MaxUploadBytes is the largest upload read; larger ones are refused before they are read in full.
	MaxUploadBytes = 5 * 1024 * 1024
	// MaxAttempts is the tries a job gets before it fails for good.
	MaxAttempts = 3
	// Lease is how long a worker holds a job before another may take it.
	Lease = 30 * time.Minute
)

// TraktSource is Trakt's connection and reader (internal/trakt). nil when Trakt is not configured.
type TraktSource interface {
	// Connected is whether the user has a live Trakt connection.
	Connected(ctx context.Context, user uuid.UUID) (bool, error)
	// AccessToken is a fresh access token, refreshed if needed; nil when not connected.
	AccessToken(ctx context.Context, user uuid.UUID) (*string, error)
	// Rows reads the user's Trakt library as import rows.
	Rows(ctx context.Context, token string) ([]Row, error)
	// DeleteConnection forgets the user's tokens (a revoked connection).
	DeleteConnection(ctx context.Context, user uuid.UUID) error
}

// AniListLists reads a public AniList list by username as import rows (IMP-014).
type AniListLists interface {
	ListRows(ctx context.Context, userName string) ([]Row, error)
}

// PushSender sends one alert to a user's devices (push.UserPush).
type PushSender interface {
	Send(ctx context.Context, msg push.Message, user uuid.UUID)
}

// Service is ImportService.
type Service struct {
	Store    *Store
	Catalog  *catalog.Kit
	Library  *library.Store
	Game     *gamification.Service
	Log      *slog.Logger
	resolver *catalog.Resolver

	// Trakt is nil when Trakt is not configured.
	Trakt TraktSource
	// AniListLists is nil when the catalog has no AniList (tests).
	AniListLists AniListLists
	// Stremio is Stremio's account API and Cinemeta, for history imports (IMP-016).
	Stremio StremioAccount
	// CATFeed reads the user's CAT calendar by its link (IMP-010).
	CATFeed CATFeed
	// Capture is the capture inputs and extractor (AG-006); see capture.go.
	Capture CaptureDeps
	// ListenHistory reads listening history by username (MUS-004), by source.
	ListenHistory map[core.ImportSource]ListenHistoryReader
	// Listens writes imported listens into the listening log (MUS-004).
	Listens ListenLog
	// Push says a capture's plan is ready. nil sends nothing.
	Push PushSender
	// Now is the clock; tests pin it.
	Now func() time.Time
}

// NewService builds the service over the job store, the catalog and the library.
func NewService(store *Store, kit *catalog.Kit, lib *library.Store, game *gamification.Service, log *slog.Logger) *Service {
	return &Service{Store: store, Catalog: kit, Library: lib, Game: game, Log: log}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now().UTC()
	}
	return time.Now().UTC()
}

func (s *Service) log() *slog.Logger {
	if s.Log != nil {
		return s.Log
	}
	return slog.Default()
}

// Resolver is the catalog's resolver (a value; tests may swap it with SetResolver).
func (s *Service) Resolver() catalog.Resolver {
	if s.resolver != nil {
		return *s.resolver
	}
	return s.Catalog.Resolver()
}

// SetResolver pins the resolver (tests that count provider calls).
func (s *Service) SetResolver(r catalog.Resolver) { s.resolver = &r }

func validationFailed(field, message string) *apperr.Error { return apperr.Validation(field, message) }

func newJob(user uuid.UUID, source core.ImportSource, filename *string, now time.Time) core.ImportJob {
	return core.ImportJob{
		ID: uuid.New(), UserID: user, Source: source, State: core.JobQueued, Filename: filename,
		CreatedAt: now, UpdatedAt: now,
	}
}

// MARK: Requests

// CreateCSVImport parses the file now (fast, bounded) and queues the matching (slow, provider calls).
func (s *Service) CreateCSVImport(ctx context.Context, user uuid.UUID, source core.ImportSource, filename *string, text string) (core.ImportJob, error) {
	rows, err := Parse(text, source, filename)
	if err != nil {
		var format *FormatError
		if errors.As(err, &format) {
			return core.ImportJob{}, validationFailed("file", format.Message)
		}
		return core.ImportJob{}, err
	}
	if len(rows) == 0 {
		return core.ImportJob{}, apperr.Validation("file", "That file has no rows to import.").
			WithDetails(map[string]string{"file": "No rows."})
	}
	job := newJob(user, source, filename, s.now())
	job.RowsTotal = len(rows)
	if err := s.Store.Insert(ctx, job, rows); err != nil {
		return core.ImportJob{}, err
	}
	return job, nil
}

// Jobs are the user's 50 latest imports.
func (s *Service) Jobs(ctx context.Context, user uuid.UUID) ([]core.ImportJob, error) {
	return s.Store.Jobs(ctx, user, 50)
}

// Detail is one job and its rows.
func (s *Service) Detail(ctx context.Context, id, user uuid.UUID) (core.ImportJob, []PlannedRow, error) {
	job, err := s.Store.Job(ctx, id, user)
	if err != nil {
		return core.ImportJob{}, nil, err
	}
	if job == nil {
		return core.ImportJob{}, nil, apperr.NotFound()
	}
	rows, err := s.Store.Rows(ctx, id)
	if err != nil {
		return core.ImportJob{}, nil, err
	}
	return *job, rows, nil
}

// Delete removes a job that is not being matched right now. A capture's input goes with it.
func (s *Service) Delete(ctx context.Context, id, user uuid.UUID) error {
	job, err := s.Store.Job(ctx, id, user)
	if err != nil {
		return err
	}
	if job == nil {
		return apperr.NotFound()
	}
	if job.State == core.JobRunning {
		return apperr.New(http.StatusConflict, "import_running",
			"This import is being matched right now. Try again when it has a plan.")
	}
	if _, err := s.Store.Delete(ctx, id, user); err != nil {
		return err
	}
	if job.Source == core.SourceCapture {
		if err := s.deleteCaptureInput(ctx, id); err != nil {
			return err
		}
		if job.State == core.JobPlanned {
			telemetry.Capture(telemetry.CapturePlanDecided, user, map[string]string{"decision": "denied"})
		}
	}
	return nil
}

// MARK: The worker's step

// RunNext leases one job and plans it. It returns false when there was nothing to do. The worker
// passes no user; tests pass theirs so parallel tests never take each other's jobs.
func (s *Service) RunNext(ctx context.Context, owner *uuid.UUID) (bool, error) {
	claimed, err := s.Store.ClaimNext(ctx, s.now(), Lease, owner)
	if err != nil || claimed == nil {
		return false, err
	}
	job := claimed.Job
	if err := s.runClaimed(ctx, &job, claimed.Attempts); err != nil {
		// A shutdown is not the job's failure: hand it back untouched, attempt uncounted, for the
		// next worker (whatever the provider client turned the cancellation into).
		if ctx.Err() != nil || errors.Is(err, context.Canceled) {
			if rerr := s.Store.Release(context.WithoutCancel(ctx), job.ID, s.now()); rerr != nil {
				s.log().Error("release import job", "error", rerr)
			}
			return true, context.Canceled
		}
		summary := failureSummary(err, job.Source.IsListens())
		if claimed.Attempts < MaxAttempts {
			// Back off: 30 s, then 60 s. A provider outage usually passes.
			wait := time.Duration(30*claimed.Attempts) * time.Second
			return true, s.Store.Retry(ctx, job.ID, summary, s.now().Add(wait), s.now())
		}
		job.State = core.JobFailed
		job.ErrorSummary = &summary
		job.UpdatedAt = s.now()
		if err := s.Store.Update(ctx, job); err != nil {
			return true, err
		}
		count(job)
		if job.Source == core.SourceCapture {
			if err := s.deleteCaptureInput(ctx, job.ID); err != nil {
				s.log().Error("delete capture input", "error", err)
			}
		}
	}
	return true, nil
}

// runClaimed plans one leased job. An error is the attempt's failure.
func (s *Service) runClaimed(ctx context.Context, job *core.ImportJob, attempts int) error {
	if job.Source.IsListens() {
		return s.planListens(ctx, job)
	}
	stored, err := s.rowsToPlan(ctx, job)
	if err != nil {
		return err
	}
	if stored == nil {
		count(*job)
		return nil
	}
	jobID := job.ID
	// The last try plans without AniList if it is still down: the rest of the file is not held
	// hostage by one provider's outage.
	lastTry := attempts >= MaxAttempts
	rows, err := s.Plan(ctx, stored, job.UserID, lastTry, func(matched int) error {
		return s.Store.Progress(ctx, jobID, matched, s.now().Add(Lease))
	})
	if err != nil {
		return err
	}
	job.State = core.JobPlanned
	job.Stats = Stats(rows)
	job.ErrorSummary = nil
	job.UpdatedAt = s.now()
	if err := s.Store.SavePlan(ctx, *job, rows); err != nil {
		return err
	}
	count(*job)
	if job.Source == core.SourceCapture && s.Push != nil {
		s.Push.Send(ctx, capturePlanned(*job), job.UserID)
	}
	return nil
}

// rowsToPlan is the rows a job plans: its file's, or what its source gives when there is no file.
// nil (and no error) when fetching failed the job for good.
func (s *Service) rowsToPlan(ctx context.Context, job *core.ImportJob) ([]PlannedRow, error) {
	stored, err := s.Store.Rows(ctx, job.ID)
	if err != nil {
		return nil, err
	}
	if len(stored) == 0 && (job.Source == core.SourceTrakt || job.Source == core.SourceAniList || job.Source == core.SourceCapture) {
		var fetched []Row
		switch job.Source {
		case core.SourceTrakt:
			fetched, err = s.fetchTrakt(ctx, job)
		case core.SourceAniList:
			fetched, err = s.fetchAniList(ctx, job)
		default:
			fetched, err = s.fetchCapture(ctx, job)
		}
		if err != nil || fetched == nil {
			return nil, err
		}
		if err := s.Store.AppendRows(ctx, fetched, job.ID); err != nil {
			return nil, err
		}
		if stored, err = s.Store.Rows(ctx, job.ID); err != nil {
			return nil, err
		}
	}
	if job.Source == core.SourceStremio {
		return s.expandStremioWatched(ctx, stored)
	}
	return stored, nil
}

// count records one finished job in `aaru_imports_total` and as a product event: planned, or
// failed for good. A retry is neither.
func count(job core.ImportJob) {
	if job.State != core.JobPlanned && job.State != core.JobFailed {
		return
	}
	metrics.Imports.WithLabelValues(string(job.Source), string(job.State)).Inc()
	telemetry.Capture(telemetry.ImportCompleted, job.UserID, map[string]string{
		"source": string(job.Source), "result": string(job.State),
	})
}

// fail fails a job for good with a message the person can act on.
func (s *Service) fail(ctx context.Context, job *core.ImportJob, summary string) error {
	job.State = core.JobFailed
	job.ErrorSummary = &summary
	job.UpdatedAt = s.now()
	return s.Store.Update(ctx, *job)
}

// listOps are Goodreads custom shelves as lists: one per shelf name, reusing a list of that name.
func (s *Service) listOps(ctx context.Context, members map[string][]uuid.UUID, user uuid.UUID) ([]library.Op, error) {
	if len(members) == 0 {
		return nil, nil
	}
	existing, err := s.Library.Lists(ctx, user)
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(members))
	for name := range members {
		names = append(names, name)
	}
	sort.Strings(names)
	ops := make([]library.Op, 0, len(names))
	for _, name := range names {
		titles := members[name]
		var found *core.AaruList
		for i := range existing {
			if strings.EqualFold(existing[i].Name, name) {
				found = &existing[i]
				break
			}
		}
		if found != nil {
			merged := append([]uuid.UUID{}, found.TitleIDs...)
			for _, t := range titles {
				if !containsID(merged, t) {
					merged = append(merged, t)
				}
			}
			ops = append(ops, library.SetListMembers(found.ID, merged))
			continue
		}
		var unique []uuid.UUID
		for _, t := range titles {
			if !containsID(unique, t) {
				unique = append(unique, t)
			}
		}
		if unique == nil {
			unique = []uuid.UUID{}
		}
		ops = append(ops, library.InsertList(library.ListSnapshot{ID: uuid.New(), Name: name, CreatedAt: s.now(), Members: unique}))
	}
	return ops, nil
}

func containsID(ids []uuid.UUID, id uuid.UUID) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

// MARK: Helpers

// Stats counts a plan's outcomes.
func Stats(rows []PlannedRow) core.ImportStats {
	var st core.ImportStats
	for _, r := range rows {
		switch r.Outcome {
		case OutcomeCreate:
			st.Created++
		case OutcomeUpdate:
			st.Updated++
		case OutcomeSkip:
			st.Skipped++
		case OutcomeUnmatched:
			st.Unmatched++
		case OutcomePending:
		}
	}
	return st
}

// rating is a source's rating if it is a valid Aaru rating.
func rating(value *float64) *float64 {
	if value == nil {
		return nil
	}
	r, err := core.NewRating(*value)
	if err != nil {
		return nil
	}
	v := r.Value()
	return &v
}

// summary is the journal's line for an applied import.
func summary(source core.ImportSource, stats core.ImportStats) string {
	return fmt.Sprintf("Imported %d new and updated %d from %s", stats.Created, stats.Updated, SourceName(source))
}

// SourceName is the site an import came from, as the journal's summary names it.
func SourceName(source core.ImportSource) string {
	switch source {
	case core.SourceIMDbCSV:
		return "IMDb"
	case core.SourceLetterboxdCSV:
		return "Letterboxd"
	case core.SourceGoodreadsCSV:
		return "Goodreads"
	case core.SourceTrakt:
		return "Trakt"
	case core.SourceStremio:
		return "Stremio"
	case core.SourceCATList, core.SourceCATICS:
		return "Pogdesign CAT"
	case core.SourceNetflixCSV:
		return "Netflix"
	case core.SourceTVTimeCSV:
		return "TV Time"
	case core.SourceMALXML:
		return "MyAnimeList"
	case core.SourceAniList:
		return "AniList"
	case core.SourceGenericCSV:
		return "CSV"
	case core.SourceCapture:
		return "a capture"
	case core.SourceLastFM:
		return "Last.fm"
	case core.SourceListenBrainz:
		return "ListenBrainz"
	case core.SourceSpotifyJSON:
		return "Spotify"
	case core.SourceYouTubeTakeout:
		return "YouTube"
	}
	return string(source)
}

// failureSummary is a failed attempt as the person reads it.
func failureSummary(err error, listens bool) string {
	if p, ok := provider.AsError(err); ok {
		doing := "matching titles"
		if listens {
			doing = "reading listens"
		}
		return p.DisplayName() + " could not be reached while " + doing + "."
	}
	var modelErr *model.ProviderError
	if errors.As(err, &modelErr) {
		return "Aaru could not read the capture just now. Send it again in a bit."
	}
	text := err.Error()
	if r := []rune(text); len(r) > 200 {
		text = string(r[:200])
	}
	return "Matching stopped: " + text
}

// MARK: Trakt (IMP-003)

// CreateTraktImport queues a Trakt import. Its rows are read from Trakt by the worker, not now.
func (s *Service) CreateTraktImport(ctx context.Context, user uuid.UUID) (core.ImportJob, error) {
	connected := false
	if s.Trakt != nil {
		var err error
		if connected, err = s.Trakt.Connected(ctx, user); err != nil {
			return core.ImportJob{}, err
		}
	}
	if !connected {
		return core.ImportJob{}, apperr.New(http.StatusConflict, "trakt_not_connected", "Connect Trakt first.")
	}
	job := newJob(user, core.SourceTrakt, nil, s.now())
	if err := s.Store.Insert(ctx, job, nil); err != nil {
		return core.ImportJob{}, err
	}
	return job, nil
}

// fetchTrakt reads the user's Trakt library. A revoked connection fails the job at once (no
// retry) and forgets the dead tokens, so Settings shows "Connect Trakt" again. Trakt's account
// answers (420 over a limit, 423 locked) fail at once too: retrying gets the same answer.
func (s *Service) fetchTrakt(ctx context.Context, job *core.ImportJob) ([]Row, error) {
	if s.Trakt == nil {
		return nil, s.fail(ctx, job, "Trakt is not connected. Connect it in Settings, then import again.")
	}
	token, err := s.Trakt.AccessToken(ctx, job.UserID)
	if err == nil && token == nil {
		return nil, s.fail(ctx, job, "Trakt is not connected. Connect it in Settings, then import again.")
	}
	var rows []Row
	if err == nil {
		rows, err = s.Trakt.Rows(ctx, *token)
	}
	if err == nil {
		if rows == nil {
			rows = []Row{}
		}
		return rows, nil
	}
	p, ok := provider.AsError(err)
	switch {
	case ok && p.Kind == provider.KindUnauthorized:
		if derr := s.Trakt.DeleteConnection(ctx, job.UserID); derr != nil {
			return nil, derr
		}
		return nil, s.fail(ctx, job, "Trakt access was revoked or expired. Connect Trakt again, then import.")
	case ok && p.Kind == provider.KindRefused && p.Status == 420:
		return nil, s.fail(ctx, job, "Your Trakt account is over one of Trakt's limits, so Trakt refused the import.")
	case ok && p.Kind == provider.KindRefused && p.Status == 423:
		return nil, s.fail(ctx, job, "Trakt has locked this account. Sort it out on trakt.tv, then import again.")
	}
	return nil, err
}

// MARK: AniList (IMP-014)

// ValidAniListName is an AniList username: 2–20 letters, digits or underscores.
func ValidAniListName(name string) bool {
	n := len([]rune(name))
	if n < 2 || n > 20 {
		return false
	}
	for _, r := range name {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '_' {
			return false
		}
	}
	return true
}

// CreateAniListImport queues an AniList import. Its rows are read from AniList by the worker, not
// now. The username is kept in the job's filename, which is what the import list shows.
func (s *Service) CreateAniListImport(ctx context.Context, user uuid.UUID, username string) (core.ImportJob, error) {
	name := strings.Trim(strings.TrimSpace(username), "@")
	if !ValidAniListName(name) {
		return core.ImportJob{}, validationFailed("username", "Enter your AniList username: 2–20 letters, digits or underscores.")
	}
	job := newJob(user, core.SourceAniList, &name, s.now())
	if err := s.Store.Insert(ctx, job, nil); err != nil {
		return core.ImportJob{}, err
	}
	return job, nil
}

// fetchAniList reads the public list. A private list or unknown user fails the job at once, with a
// message the person can act on, instead of retrying.
func (s *Service) fetchAniList(ctx context.Context, job *core.ImportJob) ([]Row, error) {
	if s.AniListLists == nil || job.Filename == nil {
		return nil, s.fail(ctx, job, "AniList import is not available right now.")
	}
	name := *job.Filename
	rows, err := s.AniListLists.ListRows(ctx, name)
	if provider.IsNotFound(err) {
		return nil, s.fail(ctx, job, "AniList has no public list for “"+name+"”. Check the username, or make the list public "+
			"in AniList's settings, then import again.")
	}
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, s.fail(ctx, job, name+"'s AniList anime and manga lists are empty.")
	}
	return rows, nil
}
