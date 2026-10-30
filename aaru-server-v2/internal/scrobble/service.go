package scrobble

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/provider"
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/google/uuid"
)

// Outcome is what a playback report did to the library.
type Outcome string

// The outcomes, as the scrobble route names them.
const (
	// Recorded: session opened or updated; nothing written to the library.
	Recorded Outcome = "recorded"
	// Watched: stopped past the threshold and written (an episode ticked or a movie finished).
	Watched Outcome = "watched"
	// StoppedWithoutChange: stopped, but short of the threshold, already watched, or a repeat of a stop.
	StoppedWithoutChange Outcome = "stopped"
	// Unmatched: the player's id matched nothing Aaru knows; kept as an unmatched watch event.
	Unmatched Outcome = "unmatched"
)

const (
	// WatchedThreshold is Aaru's own threshold, documented in ARCHITECTURE.md.
	WatchedThreshold = 80.0
	// RepeatWindow: a second `stop` for the same item this soon after the first is a repeat, not a rewatch.
	RepeatWindow = 10 * time.Minute
)

// Service is ScrobbleService (SCR-001): turns player reports into watch events, and a `stop` at 80%
// or more into a library write through the same library path a tap uses, journaled with the caller's
// agent token. `start` and `pause` never change progress.
type Service struct {
	Store   *Store
	Library *library.Service
	Catalog *catalog.Kit
	// Listens keeps a music video heard long enough (SCR-011).
	Listens *music.Service
	// Notifier is nil when no APNs key is configured: no Live Activity pushes (SCR-008, SCR-009).
	Notifier *Notifier
	Log      *slog.Logger
	// Now defaults to time.Now.
	Now func() time.Time
}

// NowTime is the service's clock.
func (s *Service) NowTime() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

func (s *Service) log() *slog.Logger {
	if s.Log == nil {
		return slog.Default()
	}
	return s.Log
}

func (s *Service) sync(ctx context.Context, user uuid.UUID, now time.Time, ticked []uuid.UUID) {
	if s.Notifier != nil {
		s.Notifier.Sync(ctx, user, now, ticked)
	}
}

// Report records a report and says what it did.
func (s *Service) Report(ctx context.Context, r Report, caller auth.AgentCaller) (Outcome, error) {
	outcome, _, err := s.Record(ctx, r, caller)
	return outcome, err
}

// Record is Report, also naming the title it matched, so a player can show what Aaru heard (SCR-007).
func (s *Service) Record(ctx context.Context, r Report, caller auth.AgentCaller) (Outcome, *core.Title, error) {
	metrics.Scrobbles.WithLabelValues(string(r.Source), string(r.Action)).Inc()
	now := s.NowTime()
	user := caller.UserID
	if r.Action == ActionStop {
		repeat, err := s.Store.StoppedRecently(ctx, user, r.Source, r.ExternalRef, now.Add(-RepeatWindow))
		if err != nil {
			return "", nil, err
		}
		if repeat {
			return StoppedWithoutChange, nil, nil
		}
	}
	title, err := s.resolveReport(ctx, r)
	if err != nil {
		return "", nil, err
	}
	var ticked []uuid.UUID
	if r.Action == ActionStart {
		source := r.Source
		open, err := s.Store.OpenSessions(ctx, user, &source, 10)
		if err != nil {
			return "", nil, err
		}
		for _, previous := range open {
			if previous.ExternalRef == r.ExternalRef {
				continue
			}
			moved, err := s.moveOn(ctx, previous, caller, now)
			if err != nil {
				return "", nil, err
			}
			if moved {
				ticked = append(ticked, previous.ID)
			}
		}
	}
	var titleID *uuid.UUID
	if title != nil {
		titleID = &title.ID
	}
	tokenID := caller.Token.ID
	session, err := s.Store.Record(ctx, r, titleID, user, &tokenID, now)
	if err != nil {
		return "", nil, err
	}
	if r.Action != ActionStop {
		s.sync(ctx, user, now, ticked)
		if title == nil {
			return Unmatched, nil, nil
		}
		return Recorded, title, nil
	}
	if err := s.Store.Close(ctx, session.ID, now); err != nil {
		return "", nil, err
	}
	outcome, err := s.stop(ctx, session, title, r, caller)
	if err != nil {
		return "", nil, err
	}
	var justTicked []uuid.UUID
	if outcome == Watched {
		justTicked = []uuid.UUID{session.ID}
	}
	s.sync(ctx, user, now, justTicked)
	return outcome, title, nil
}

// stop is what a `stop` writes: the episode ticked or the movie finished at 80% or more.
func (s *Service) stop(ctx context.Context, session Session, title *core.Title, r Report, caller auth.AgentCaller) (Outcome, error) {
	if title == nil {
		s.log().InfoContext(ctx, "Unmatched scrobble", "source", string(r.Source), "agentToken", caller.Token.ID.String())
		return Unmatched, nil
	}
	progress, known := session.Progress()
	if !known || progress < WatchedThreshold {
		return StoppedWithoutChange, nil
	}
	episodes, err := s.episodes(ctx, *title, r)
	if err != nil {
		return "", err
	}
	wrote, err := s.MarkWatched(ctx, *title, episodes, caller)
	if err != nil || !wrote {
		return StoppedWithoutChange, err
	}
	return Watched, nil
}

// moveOn: the player started something else without stopping previous (Stremio's next episode): it
// closes, and ticks when the player last reported it at 80% or more. Only the reported position
// counts, so a player closed mid-episode never fakes a watch. Returns whether it ticked.
func (s *Service) moveOn(ctx context.Context, previous OpenSession, caller auth.AgentCaller, now time.Time) (bool, error) {
	if err := s.Store.Close(ctx, previous.ID, now); err != nil {
		return false, err
	}
	progress, known := previous.ReportedProgress()
	if !known || progress < WatchedThreshold {
		return false, nil
	}
	title, err := s.Catalog.Store.Title(ctx, previous.TitleID)
	if err != nil || title == nil {
		return false, err
	}
	var episodes []core.EpisodeKey
	if previous.Episode != nil {
		episodes = []core.EpisodeKey{*previous.Episode}
	}
	return s.MarkWatched(ctx, *title, episodes, caller)
}

// NowPlaying is what a player is playing for the user now (SCR-008), or nil.
func (s *Service) NowPlaying(ctx context.Context, user uuid.UUID) (*NowPlaying, error) {
	sessions, err := s.Store.OpenSessions(ctx, user, nil, 5)
	if err != nil {
		return nil, err
	}
	live := Pick(sessions, s.NowTime())
	if live == nil {
		return nil, nil //nolint:nilnil // nothing plays
	}
	title, err := s.Catalog.Store.Title(ctx, live.TitleID)
	if err != nil || title == nil {
		return nil, err
	}
	return &NowPlaying{Session: *live, Title: *title}, nil
}

// PlayingNow is everything playing for the user now, in the activity's order.
func (s *Service) PlayingNow(ctx context.Context, user uuid.UUID) ([]Entry, error) {
	return LoadLiveSet(ctx, s.Store, s.Catalog.Store, user, s.NowTime())
}

// resolveReport is the title a report names. A report with no id names its title instead (SCR-007):
// matched only when exactly one catalog entry has the name.
func (s *Service) resolveReport(ctx context.Context, r Report) (*core.Title, error) {
	if r.TitleID != nil || !r.IDs.IsEmpty() || r.Title == nil {
		return s.Resolve(ctx, core.MediaRef{TitleID: r.TitleID, Type: r.Type, IDs: r.IDs})
	}
	if r.Year != nil {
		return s.Resolve(ctx, core.MediaRef{Type: r.Type, Title: r.Title, Year: r.Year})
	}
	return unlessUnknown(func() (core.Title, error) {
		return s.Catalog.Resolver().ResolveNamed(ctx, *r.Title, r.Type, nil, nil)
	})
}

// Resolve is the title a ref names, hydrating it from the catalog when Aaru has not seen it yet; nil
// when nothing matches.
func (s *Service) Resolve(ctx context.Context, ref core.MediaRef) (*core.Title, error) {
	return unlessUnknown(func() (core.Title, error) { return s.Catalog.Resolver().Resolve(ctx, ref, nil) })
}

// unlessUnknown is nil when the catalog does not know the title, or knows more than one by that name.
func unlessUnknown(body func() (core.Title, error)) (*core.Title, error) {
	t, err := body()
	if err == nil {
		return &t, nil
	}
	if _, ok := catalog.IsResolutionError(err); ok {
		return nil, nil //nolint:nilnil // unknown
	}
	var pe *provider.Error
	if errors.As(err, &pe) && pe.Kind == provider.KindNotFound {
		return nil, nil //nolint:nilnil // unknown
	}
	return nil, err
}

// episodes is the episode a stop ticks: the number the player gave, else the one its name matches.
func (s *Service) episodes(ctx context.Context, title core.Title, r Report) ([]core.EpisodeKey, error) {
	if r.Episode != nil {
		return []core.EpisodeKey{*r.Episode}, nil
	}
	if r.EpisodeName == nil {
		return nil, nil
	}
	return s.Catalog.Resolver().EpisodesNamed(ctx, title, []catalog.NamedEpisode{*r.EpisodeName})
}

// MarkWatched ticks the episodes (one action), or finishes the movie. A title not in the library is
// added first (in progress for a show, finished for a movie). Returns whether anything was written. A
// show with no episodes named writes nothing.
func (s *Service) MarkWatched(ctx context.Context, title core.Title, episodes []core.EpisodeKey, caller auth.AgentCaller) (bool, error) {
	agent := library.AgentCaller(caller.Token)
	ref := core.MediaRef{TitleID: &title.ID, Type: title.Type}
	existing, err := s.Library.ItemForTitle(ctx, caller.UserID, title.ID)
	if err != nil {
		return false, err
	}
	if title.Type == core.MediaShow {
		if len(episodes) == 0 {
			return false, nil
		}
		var id uuid.UUID
		if existing != nil {
			id = existing.Item.ID
		} else {
			status := core.StatusInProgress
			added, err := s.Library.Add(ctx, ref, &status, caller.UserID, agent)
			if err != nil {
				return false, err
			}
			id = added.Item.ID
		}
		entry, err := s.Library.SetEpisodes(ctx, id, caller.UserID, episodes, true, agent)
		return entry != nil, err
	}
	if title.Type != core.MediaMovie {
		return false, nil
	}
	finished := core.StatusFinished
	if existing == nil {
		_, err := s.Library.Add(ctx, ref, &finished, caller.UserID, agent)
		return err == nil, err
	}
	if existing.Item.Status == core.StatusFinished {
		return false, nil
	}
	_, err = s.Library.Patch(ctx, existing.Item.ID, caller.UserID, library.ItemPatch{Status: &finished}, agent)
	return err == nil, err
}

// MARK: Plays (SCR-009, SCR-011)

// Play is a connection playing p: a track's `playing_now`, or a video's report.
func (s *Service) Play(ctx context.Context, p LivePlay, caller auth.AgentCaller) error {
	metrics.Scrobbles.WithLabelValues(string(p.Source), string(p.State)).Inc()
	if err := s.Store.SavePlay(ctx, p, caller.UserID, caller.Token.ID); err != nil {
		return err
	}
	s.sync(ctx, caller.UserID, s.NowTime(), nil)
	return nil
}

// Heard is SCR-011: a music video heard long enough. Every report past that point sends it again;
// the log keeps one per video per play, and one if a music scrobbler heard the same video.
func (s *Service) Heard(ctx context.Context, l music.NewListen, caller auth.AgentCaller) error {
	if s.Listens == nil {
		return nil
	}
	_, err := s.Listens.Submit(ctx, []music.NewListen{l}, caller)
	return err
}

// StopPlay is the connection having stopped its kind of play: a video's `stop`.
func (s *Service) StopPlay(ctx context.Context, kind PlayKind, caller auth.AgentCaller) error {
	if err := s.Store.RemovePlay(ctx, kind, caller.UserID, caller.Token.ID); err != nil {
		return err
	}
	s.sync(ctx, caller.UserID, s.NowTime(), nil)
	return nil
}

// MARK: The sweep

// SweepInterval is how often the sweep runs.
const SweepInterval = 15 * time.Second

// SweepWorker is LiveActivitySweepService: looks again at users whose "Now playing" activity is due
// to change with no report to say so (SCR-009): a song that ended, a tab closed on a video, an
// episode past its end, a "Watched" row done lingering. Each user's check is claimed, so two
// replicas never push the same change.
type SweepWorker struct {
	Notifier *Notifier
	Log      *slog.Logger
	Interval time.Duration
	Now      func() time.Time
}

// Name names the worker in logs.
func (w *SweepWorker) Name() string { return "live-activity-sweep" }

// Run sweeps until ctx is cancelled.
func (w *SweepWorker) Run(ctx context.Context) error {
	interval := w.Interval
	if interval == 0 {
		interval = SweepInterval
	}
	for {
		if err := w.Sweep(ctx); err != nil && ctx.Err() == nil {
			log := w.Log
			if log == nil {
				log = slog.Default()
			}
			log.Error("Live Activity sweep failed", "error", err.Error())
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(interval):
		}
	}
}

// Sweep is one pass.
func (w *SweepWorker) Sweep(ctx context.Context) error {
	now := time.Now()
	if w.Now != nil {
		now = w.Now()
	}
	users, err := w.Notifier.Store.ClaimDueLiveActivityChecks(ctx, now, 100)
	if err != nil {
		return err
	}
	for _, user := range users {
		w.Notifier.Sync(ctx, user, now, nil)
	}
	return nil
}
