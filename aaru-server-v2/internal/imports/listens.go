package imports

// MARK: Listening history (MUS-004) — ImportService+Listens.swift
//
// A listening import's plays wait in `import_listens` until the user applies them, then go to the
// listening log as `import` listens of the job. A listen is not a library write, so nothing is
// journaled: undoing the job deletes its listens. They count in Insights and the Recap on their own
// day, earn no points, and count toward music badges (decisions 2026-10-27).

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/provider"
	"context"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/google/uuid"
)

// MaxListenUploadBytes is the largest listening file read: a Spotify history file holds years of
// plays; library exports stay at 5 MB.
const MaxListenUploadBytes = 24 * 1024 * 1024

// listenFileGate lets one listening file be parsed at a time, so two large uploads never share the
// server's memory.
var listenFileGate sync.Mutex

// ListenLog is what listening imports need of the listening log (ListenStore's MUS-004 part).
type ListenLog interface {
	// Stage adds plays to a job's staging, numbered from index.
	Stage(ctx context.Context, listens []NewListen, jobID uuid.UUID, index int) error
	// ClearStaged empties a job's staging, so a retried fetch starts over.
	ClearStaged(ctx context.Context, jobID uuid.UUID) error
	// CountNew is how many staged plays applying would keep: those outside every stored listen's
	// duplicate window and outside the window of the play before them of the same track.
	CountNew(ctx context.Context, jobID, user uuid.UUID) (int, error)
	// ApplyStaged writes the plays CountNew counts as the job's `import` listens, then empties its
	// staging. It returns how many were written.
	ApplyStaged(ctx context.Context, jobID, user uuid.UUID) (int, error)
	// DeleteImported deletes the listens a job wrote and returns how many.
	DeleteImported(ctx context.Context, jobID, user uuid.UUID) (int, error)
	// NewestImported is the newest listen an applied import of this source and account wrote, so
	// the next import of it reads only what came after.
	NewestImported(ctx context.Context, user uuid.UUID, source core.ImportSource, account string) (*time.Time, error)
}

var _ ListenLog = (*music.Store)(nil)

// listenLog is the store listening imports use: the one set, else the listening log over the job
// store's pool.
func (s *Service) listenLog() ListenLog {
	if s.Listens != nil {
		return s.Listens
	}
	return music.NewStore(s.Store.Pool)
}

// CreateListenFileImport parses the file now and stages its plays; the worker counts which are new.
// source nil detects it from the file.
func (s *Service) CreateListenFileImport(ctx context.Context, user uuid.UUID, source *core.ImportSource, filename *string, data []byte) (core.ImportJob, error) {
	resolved, page, err := s.parseListenFile(source, data)
	if err != nil {
		var format *FormatError
		if errors.As(err, &format) {
			return core.ImportJob{}, validationFailed("file", format.Message)
		}
		return core.ImportJob{}, err
	}
	if len(page.Listens) == 0 {
		return core.ImportJob{}, validationFailed("file", "That file has no music plays to import.")
	}
	job := newJob(user, resolved, filename, s.now())
	job.Stats = core.ImportStats{Ignored: page.Ignored}
	job.RowsTotal = len(page.Listens)
	if err := s.Store.Insert(ctx, job, nil); err != nil {
		return core.ImportJob{}, err
	}
	if err := s.listenLog().Stage(ctx, page.Listens, job.ID, 0); err != nil {
		return core.ImportJob{}, err
	}
	return job, nil
}

func (s *Service) parseListenFile(source *core.ImportSource, data []byte) (core.ImportSource, ListenHistoryPage, error) {
	listenFileGate.Lock()
	defer listenFileGate.Unlock()
	var resolved core.ImportSource
	if source != nil {
		resolved = *source
	} else {
		detected, err := DetectListenFile(data)
		if err != nil {
			return "", ListenHistoryPage{}, err
		}
		resolved = detected
	}
	page, err := ParseListenFile(data, resolved, s.now())
	return resolved, page, err
}

// CreateListenAccountImport queues a Last.fm or ListenBrainz import. The worker reads the account;
// the username is kept in the job's filename, which is what the import list shows.
func (s *Service) CreateListenAccountImport(ctx context.Context, user uuid.UUID, source core.ImportSource, username string) (core.ImportJob, error) {
	if s.ListenHistory[source] == nil {
		return core.ImportJob{}, apperr.Unavailable(string(source)+"_unavailable",
			SourceName(source)+" import is not set up on this server yet.")
	}
	name := strings.Trim(strings.TrimSpace(username), "@")
	control := strings.ContainsFunc(name, func(r rune) bool { return r < 32 || unicode.In(r, unicode.Zl, unicode.Zp) || r == '\u0085' })
	if n := core.Length(name); n < 1 || n > 64 || control {
		return core.ImportJob{}, validationFailed("username", "Enter your "+SourceName(source)+" username.")
	}
	job := newJob(user, source, &name, s.now())
	if err := s.Store.Insert(ctx, job, nil); err != nil {
		return core.ImportJob{}, err
	}
	return job, nil
}

// planListens is the worker's plan for a listening import: an account is read into staging first,
// renewing the lease each page; then the staged plays are split into new and already in the log.
func (s *Service) planListens(ctx context.Context, job *core.ImportJob) error {
	defer func() { count(*job) }()
	if job.Source == core.SourceLastFM || job.Source == core.SourceListenBrainz {
		ok, err := s.fetchListens(ctx, job)
		if err != nil || !ok {
			return err
		}
	}
	if job.RowsTotal <= 0 {
		return s.fail(ctx, job, "That import has no plays left. Import the file again.")
	}
	fresh, err := s.listenLog().CountNew(ctx, job.ID, job.UserID)
	if err != nil {
		return err
	}
	job.Stats.Created = fresh
	job.Stats.Skipped = job.RowsTotal - fresh
	job.State = core.JobPlanned
	job.ErrorSummary = nil
	job.UpdatedAt = s.now()
	if err := s.Store.Progress(ctx, job.ID, job.RowsTotal, s.now().Add(Lease)); err != nil {
		return err
	}
	return s.Store.Update(ctx, *job)
}

// fetchListens reads the account's history into staging. False when the job failed for good: an
// unknown user, private listening, or nothing to read.
func (s *Service) fetchListens(ctx context.Context, job *core.ImportJob) (bool, error) {
	service := SourceName(job.Source)
	reader := s.ListenHistory[job.Source]
	if reader == nil || job.Filename == nil {
		return false, s.fail(ctx, job, service+" import is not available right now.")
	}
	name := *job.Filename
	jobID := job.ID
	log := s.listenLog()
	if err := log.ClearStaged(ctx, jobID); err != nil {
		return false, err
	}
	since, err := log.NewestImported(ctx, job.UserID, job.Source, name)
	if err != nil {
		return false, err
	}
	staged, ignored := 0, 0
	err = reader.Read(ctx, name, since, s.now(), func(page ListenHistoryPage) error {
		if err := log.Stage(ctx, page.Listens, jobID, staged); err != nil {
			return err
		}
		staged += len(page.Listens)
		ignored += page.Ignored
		return s.Store.Progress(ctx, jobID, staged, s.now().Add(Lease))
	})
	switch {
	case provider.IsNotFound(err):
		return false, s.fail(ctx, job, service+" has no user “"+name+"”. Check the username, then import again.")
	case IsLastFMPrivate(err):
		return false, s.fail(ctx, job, name+" hides their recent listening on Last.fm. Turn off “Hide recent listening” in Last.fm's "+
			"privacy settings, then import again.")
	case err != nil:
		return false, err
	}
	if staged == 0 {
		message := "Nothing new on " + service + " since your last import of " + name + "."
		if since == nil {
			message = name + " has no listens on " + service + " yet."
		}
		return false, s.fail(ctx, job, message)
	}
	job.RowsTotal = staged
	job.Stats.Ignored = ignored
	return true, nil
}

// applyListens writes the new plays to the listening log. No points, however recent: a backlog is
// not a day's listening.
func (s *Service) applyListens(ctx context.Context, job core.ImportJob) (core.ImportJob, error) {
	written, err := s.listenLog().ApplyStaged(ctx, job.ID, job.UserID)
	if err != nil {
		return core.ImportJob{}, err
	}
	job.Stats.Created = written
	job.Stats.Skipped = max(0, job.RowsTotal-written)
	job.State = core.JobSucceeded
	job.UpdatedAt = s.now()
	if err := s.Store.Update(ctx, job); err != nil {
		return core.ImportJob{}, err
	}
	if s.Game != nil {
		s.Game.ListensImported(ctx, job.UserID)
	}
	return job, nil
}

// UndoListens undoes an applied listening import in one step: its listens, the music badges only
// they held, and the job itself go.
func (s *Service) UndoListens(ctx context.Context, id, user uuid.UUID) error {
	job, err := s.Store.Job(ctx, id, user)
	if err != nil {
		return err
	}
	if job == nil {
		return apperr.NotFound()
	}
	if !job.Source.IsListens() {
		return apperr.New(http.StatusConflict, "import_not_listens",
			"This import changed your library. Undo it from its action instead.")
	}
	if job.State != core.JobSucceeded {
		return apperr.New(http.StatusConflict, "import_not_applied",
			"This import was not applied, so there is nothing to undo. Delete it instead.")
	}
	if _, err := s.listenLog().DeleteImported(ctx, id, user); err != nil {
		return err
	}
	if _, err := s.Store.Delete(ctx, id, user); err != nil {
		return err
	}
	if s.Game != nil {
		s.Game.ListensUndone(ctx, user)
	}
	return nil
}
