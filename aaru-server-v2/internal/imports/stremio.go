package imports

// Stremio history (IMP-016): ImportService+Stremio.swift and StremioLibraryMapper.swift.

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/stremioapi"
	"context"
	"errors"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
)

// StremioAccount is Stremio's account API and Cinemeta, for history imports (IMP-016);
// *stremioapi.Account in production. nil answers the link routes with 503.
type StremioAccount interface {
	CreateLink(ctx context.Context) (stremioapi.LinkCode, error)
	ReadLink(ctx context.Context, code string) (*string, error)
	Library(ctx context.Context, authKey string) ([]stremioapi.LibraryItem, error)
	Logout(ctx context.Context, authKey string)
	Series(ctx context.Context, imdb string) (stremioapi.Series, error)
}

// StremioLinkStart is a link code for the user to approve on stremio.com.
type StremioLinkStart struct {
	Code      string
	Link      string
	QRCode    string
	ExpiresAt time.Time
}

// StartStremioLink asks Stremio for a code and keeps its deadline.
func (s *Service) StartStremioLink(ctx context.Context, user uuid.UUID) (StremioLinkStart, error) {
	stremio, err := s.stremioAccount()
	if err != nil {
		return StremioLinkStart{}, err
	}
	code, err := stremio.CreateLink(ctx)
	if err != nil {
		return StremioLinkStart{}, stremioError(err)
	}
	now := s.now()
	expiresAt := now.Add(stremioapi.LinkLifetime)
	if err := s.createStremioLink(ctx, code.Code, user, expiresAt, now); err != nil {
		return StremioLinkStart{}, err
	}
	return StremioLinkStart{Code: code.Code, Link: code.Link, QRCode: code.QRCode, ExpiresAt: expiresAt}, nil
}

// PollStremioLink answers nil while the code is pending. Once approved, it reads the library in
// this request (one call), logs the session out and forgets its key, and queues the import.
// Matching is the worker's job, as for every import.
func (s *Service) PollStremioLink(ctx context.Context, code string, user uuid.UUID) (*core.ImportJob, error) {
	stremio, err := s.stremioAccount()
	if err != nil {
		return nil, err
	}
	expiries, err := s.Store.Q.StremioLinkExpiry(ctx, sqlc.StremioLinkExpiryParams{Code: code, UserID: user})
	if err != nil {
		return nil, err
	}
	if len(expiries) == 0 {
		return nil, apperr.NotFound()
	}
	if !expiries[0].After(s.now()) {
		if _, err := s.consumeStremioLink(ctx, code, user); err != nil {
			return nil, err
		}
		return nil, apperr.New(http.StatusGone, "stremio_link_expired",
			"That Stremio code expired. Start again to get a new one.")
	}
	authKey, err := stremio.ReadLink(ctx, code)
	if err != nil {
		return nil, stremioError(err)
	}
	if authKey == nil {
		return nil, nil //nolint:nilnil // nil is "not approved yet"
	}
	// Logging out is best effort and must happen even when the caller has gone.
	logout := func() { stremio.Logout(context.WithoutCancel(ctx), *authKey) }
	// Single use: a second poll racing this one finds nothing to import.
	consumed, err := s.consumeStremioLink(ctx, code, user)
	if err != nil {
		return nil, err
	}
	if !consumed {
		logout()
		return nil, apperr.NotFound()
	}
	items, err := stremio.Library(ctx, *authKey)
	logout()
	if err != nil {
		return nil, stremioError(err)
	}
	rows := StremioRows(items)
	if len(rows) == 0 {
		return nil, apperr.Validation("library", "Your Stremio library has no movies or shows to import.").
			WithDetails(map[string]string{"library": "Empty."})
	}
	job := newJob(user, core.SourceStremio, nil, s.now())
	if err := s.Store.Insert(ctx, job, rows); err != nil {
		return nil, err
	}
	return &job, nil
}

// StremioLinkExpiry is a code's deadline for this user; nil when there is none.
func (s *Service) StremioLinkExpiry(ctx context.Context, code string, user uuid.UUID) (*time.Time, error) {
	expiries, err := s.Store.Q.StremioLinkExpiry(ctx, sqlc.StremioLinkExpiryParams{Code: code, UserID: user})
	if err != nil || len(expiries) == 0 {
		return nil, err
	}
	return &expiries[0], nil
}

func (s *Service) createStremioLink(ctx context.Context, code string, user uuid.UUID, expiresAt, now time.Time) error {
	tx, err := s.Store.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()
	q := s.Store.Q.WithTx(tx)
	if err := q.StremioLinkSweep(ctx, now); err != nil {
		return err
	}
	if err := q.StremioLinkCreate(ctx, sqlc.StremioLinkCreateParams{Code: code, UserID: user, ExpiresAt: expiresAt}); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) consumeStremioLink(ctx context.Context, code string, user uuid.UUID) (bool, error) {
	deleted, err := s.Store.Q.StremioLinkConsume(ctx, sqlc.StremioLinkConsumeParams{Code: code, UserID: user})
	return len(deleted) > 0, err
}

func (s *Service) stremioAccount() (StremioAccount, error) {
	if s.Stremio == nil {
		return nil, apperr.New(http.StatusServiceUnavailable, "stremio_unavailable",
			"Stremio import is not available right now.")
	}
	return s.Stremio, nil
}

// stremioError makes Stremio's own failures read as Stremio's, not as "the catalog".
func stremioError(err error) error {
	var apiErr *stremioapi.APIError
	if _, ok := provider.AsError(err); ok || errors.As(err, &apiErr) {
		return apperr.New(http.StatusBadGateway, "provider_unavailable", "Stremio did not answer. Try again in a minute.")
	}
	return err
}

// expandStremioWatched is the worker's step before matching: it lays each show's watched
// bitfield over its Cinemeta episode list. A show Cinemeta does not know keeps its status and
// gets no ticks.
//
// The show is found by Cinemeta's TVDB id first, as the addon's events are: TMDB answers some
// IMDb series with a near-empty entry of their own (Bleach: Thousand-Year Blood War,
// `tt14986406`), while TVDB's id is the show Aaru tracks. Ticks of another IMDb series are put on
// that show's episodes by release day; one that cannot be placed is left out.
func (s *Service) expandStremioWatched(ctx context.Context, rows []PlannedRow) ([]PlannedRow, error) {
	if s.Stremio == nil {
		return rows, nil
	}
	expanded := slices.Clone(rows)
	for i := range expanded {
		row := &expanded[i].Row
		if row.StremioWatched == nil || row.IDs.IMDB == "" {
			continue
		}
		imdb := row.IDs.IMDB
		series, err := s.Stremio.Series(ctx, imdb)
		if err != nil {
			return nil, err
		}
		if series.Videos == nil {
			series.Videos = []stremioapi.Video{}
		}
		ticks := stremioapi.Episodes(*row.StremioWatched, series.Videos)
		if title := s.stremioShow(ctx, series.TVDB); title != nil {
			row.IDs = title.IDs
			if title.IDs.IMDB != imdb && len(ticks) > 0 {
				var episodes []catalog.Episode
				list, err := s.Resolver().Providers.TMDB.Episodes(ctx, title.IDs)
				if err != nil {
					return nil, err
				}
				if list != nil {
					episodes = list.Episodes
				}
				placed := make([]core.EpisodeKey, 0, len(ticks))
				for _, key := range ticks {
					if p := stremioapi.Place(key, imdb, *title, episodes, series.Videos); p != nil {
						placed = append(placed, *p)
					}
				}
				ticks = placed
			}
		}
		row.Watched = nil
		if len(ticks) > 0 {
			row.Watched = uniqueSortedKeys(ticks)
		}
		row.StremioWatched = nil
	}
	return expanded, nil
}

// stremioShow is the show TVDB's id names, when there is one and the catalog knows it.
func (s *Service) stremioShow(ctx context.Context, tvdb string) *core.Title {
	if tvdb == "" {
		return nil
	}
	title, err := s.Resolver().Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{TVDB: tvdb}}, nil)
	if err != nil {
		return nil
	}
	return &title
}

func uniqueSortedKeys(keys []core.EpisodeKey) []core.EpisodeKey {
	out := slices.Clone(keys)
	slices.SortFunc(out, func(a, b core.EpisodeKey) int {
		switch {
		case a.Less(b):
			return -1
		case b.Less(a):
			return 1
		}
		return 0
	})
	return slices.Compact(out)
}

// MARK: The mapper

// StremioRows turns a Stremio library into import rows (StremioLibraryMapper). Shared by the
// link-code import and the export-file fallback, so both read Stremio the same way.
func StremioRows(items []stremioapi.LibraryItem) []Row {
	rows := []Row{}
	for _, item := range items {
		if row := StremioRow(item); row != nil {
			rows = append(rows, *row)
		}
	}
	return rows
}

// StremioRow is one library item as a row; nil when it does not come in.
func StremioRow(item stremioapi.LibraryItem) *Row {
	var mediaType core.MediaType
	switch item.Type {
	case "movie":
		mediaType = core.MediaMovie
	case "series":
		mediaType = core.MediaShow
	default:
		return nil
	}
	state := stremioapi.LibraryState{}
	if item.State != nil {
		state = *item.State
	}
	positive := func(n *int) bool { return n != nil && *n > 0 }
	watchedOnce := positive(state.TimesWatched) || positive(state.FlaggedWatched)
	started := positive(state.TimeOffset)
	ticks := state.Watched != nil && *state.Watched != ""
	temp := isTrue(item.Temp)
	// Removed by hand: the user took it out of Stremio, so it does not come in.
	if isTrue(item.Removed) && !temp {
		return nil
	}
	// Opened once and never played.
	if temp && !watchedOnce && !started && !ticks {
		return nil
	}

	row := Row{SourceKey: ptr(item.ID), Type: mediaType, Title: item.Name, Lists: []string{}}
	if stremioapi.IsIMDbID(item.ID, false) {
		row.IDs.IMDB = item.ID
	} else {
		prefix, _, _ := strings.Cut(item.ID, ":")
		row.Unsupported = ptr("Stremio lists this under an add-on's own id (" + prefix + "), not an IMDb id. Add it by hand.")
	}
	switch {
	case mediaType == core.MediaMovie && watchedOnce:
		row.Status = ptr(core.StatusFinished)
		if state.LastWatched != nil {
			row.FinishedAt = stremioapi.ParseDate(*state.LastWatched)
		}
	case mediaType == core.MediaMovie && started:
		row.Status = ptr(core.StatusInProgress)
	case mediaType == core.MediaShow && (watchedOnce || started || ticks):
		row.Status = ptr(core.StatusInProgress)
		if ticks {
			row.StremioWatched = state.Watched
		}
	default:
		row.Status = ptr(core.StatusWishlist)
	}
	return &row
}
