// Package shares is SHR-002's share links (Sources/App/Shares/ShareService.swift): a public,
// reusable link to one title, sport event or concert. Anyone can open it; only the sender and
// their friends see who sent it and the note, never across a block. Titles are resolved when the
// link is made, so opening one reads the catalog row; events go through the shared sports and
// concert caches. Nothing about an event is stored.
package shares

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/social"
	"aaru-go-api/internal/sports"
	"aaru-go-api/internal/telemetry"
	"context"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
)

// Limits.
const (
	CodeLength = social.CodeLength
	MaxNote    = 140
	// CreatesPerHour is per sender.
	CreatesPerHour = 60
	// PreviewsPerHour is per client address: high enough for one link opened by a whole group
	// chat; the caches carry the provider cost.
	PreviewsPerHour = 600
)

// Kind is what a link points at.
type Kind string

// The kinds.
const (
	KindTitle      Kind = "title"
	KindSportEvent Kind = "sport_event"
	KindConcert    Kind = "concert"
)

// Target is what a share link points at: one catalog title, or one provider event by its id.
type Target struct {
	Kind Kind
	// TitleID is set for KindTitle.
	TitleID uuid.UUID
	// EventID is TheSportsDB's (KindSportEvent) or Ticketmaster's (KindConcert) event id.
	EventID string
}

// Share is one share link: public and reusable. Sender is nil once their account is gone.
type Share struct {
	Code      string
	Sender    *uuid.UUID
	Target    Target
	Note      *string
	CreatedAt time.Time
}

// Request is what a link is asked to point at, before the title is resolved.
type Request struct {
	Kind Kind
	// Ref is set for KindTitle.
	Ref core.MediaRef
	// ID is set for events.
	ID string
}

// Sender is who sent a link, shown to the sender and their friends only.
type Sender struct {
	User social.User
	Note *string
}

// Preview is what a link shows. The content is public; From is there only for the sender and
// their friends.
type Preview struct {
	Share      Share
	Title      *catalog.TitleDetail
	SportEvent *sports.Event
	Concert    *concerts.Concert
	// Unavailable: the provider could not give the event right now; the content is then nil.
	Unavailable bool
	From        *Sender
	// ViewerItem is the signed-in viewer's own item for a shared title.
	ViewerItem *library.Entry
}

// ErrNoSuchShare is the one 404.
var ErrNoSuchShare = apperr.NotFound("This link doesn't work anymore.")

var errRateLimited = apperr.RateLimited("Too many links. Try again later.")

// Invalid is the 422 every bad target and note answers.
func Invalid(message string) *apperr.Error {
	return apperr.New(http.StatusUnprocessableEntity, "validation_failed", message)
}

// Service makes and opens share links.
type Service struct {
	Q        *sqlc.Queries
	Social   *social.Service
	Catalog  *catalog.Kit
	Library  *library.Store
	Sports   *sports.Service
	Concerts *concerts.Service
	// WebBaseURL is the web origin a link opens on; the apps claim the same paths.
	WebBaseURL string
	Now        func() time.Time

	createLimiter  *ratelimit.FixedWindow
	previewLimiter *ratelimit.FixedWindow
}

// New builds the service; its limiters live as long as it does.
func New(q *sqlc.Queries, soc *social.Service, kit *catalog.Kit, lib *library.Store, sp *sports.Service, co *concerts.Service, webBaseURL string) *Service {
	return &Service{
		Q: q, Social: soc, Catalog: kit, Library: lib, Sports: sp, Concerts: co,
		WebBaseURL: strings.TrimSuffix(webBaseURL, "/"), Now: time.Now,
		createLimiter:  ratelimit.New(CreatesPerHour, time.Hour),
		previewLimiter: ratelimit.New(PreviewsPerHour, time.Hour),
	}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// URL is the link to share.
func (s *Service) URL(share Share) string { return s.WebBaseURL + "/s/" + share.Code }

// Create makes a link, or gives back the sender's link to the same target with the same note.
func (s *Service) Create(ctx context.Context, viewer uuid.UUID, req Request, note *string) (Share, error) {
	if !s.createLimiter.Allow(viewer.String(), s.now()) {
		return Share{}, errRateLimited
	}
	kept, err := ValidNote(note)
	if err != nil {
		return Share{}, err
	}
	target := Target{Kind: req.Kind}
	switch req.Kind {
	case KindTitle:
		if s.Catalog == nil {
			return Share{}, errors.New("shares: no catalog")
		}
		title, err := s.Catalog.Resolver().Resolve(ctx, req.Ref, nil)
		if err != nil {
			return Share{}, err
		}
		target.TitleID = title.ID
	case KindSportEvent:
		if target.EventID, err = s.knownSportEvent(ctx, req.ID); err != nil {
			return Share{}, err
		}
	case KindConcert:
		if target.EventID, err = s.knownConcert(ctx, req.ID); err != nil {
			return Share{}, err
		}
	}
	existing, err := s.existing(ctx, viewer, target, kept)
	if err != nil {
		return Share{}, err
	}
	if existing != nil {
		return *existing, nil
	}
	for range 3 {
		sender := viewer
		share := Share{Code: social.NewCode(), Sender: &sender, Target: target, Note: kept, CreatedAt: s.now()}
		err := s.Save(ctx, share)
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && strings.HasPrefix(pgErr.Code, "23") {
			continue
		}
		if err != nil {
			return Share{}, err
		}
		telemetry.Capture(telemetry.ShareCreated, viewer, map[string]string{"kind": string(target.Kind)})
		return share, nil
	}
	return Share{}, apperr.New(http.StatusInternalServerError, "internal", "Couldn't make a link. Try again.")
}

// Preview is what the link shows. viewer is nil when the person opening it is signed out.
func (s *Service) Preview(ctx context.Context, code string, viewer *uuid.UUID, clientAddress string) (Preview, error) {
	if !s.previewLimiter.Allow(clientAddress, s.now()) {
		return Preview{}, errRateLimited
	}
	share, err := s.Share(ctx, code)
	if err != nil {
		return Preview{}, err
	}
	if share == nil {
		return Preview{}, ErrNoSuchShare
	}
	preview := Preview{Share: *share}
	switch share.Target.Kind {
	case KindTitle:
		// The catalog row only: a public page never hydrates episodes or tracks (SHR-002), so a
		// provider outage or a burst of opens costs nothing and fails nothing.
		if s.Catalog == nil {
			return Preview{}, ErrNoSuchShare
		}
		title, err := s.Catalog.Store.Title(ctx, share.Target.TitleID)
		if err != nil {
			return Preview{}, err
		}
		state, err := s.Catalog.Store.State(ctx, share.Target.TitleID)
		if err != nil {
			return Preview{}, err
		}
		if title == nil || state == nil {
			return Preview{}, ErrNoSuchShare
		}
		preview.Title = &catalog.TitleDetail{Title: *title, Status: state.Status, RuntimeMinutes: state.RuntimeMinutes}
		if viewer != nil && s.Library != nil {
			if preview.ViewerItem, err = s.Library.EntryForTitle(ctx, *viewer, title.ID, s.now()); err != nil {
				return Preview{}, err
			}
		}
	case KindSportEvent:
		if s.Sports != nil {
			event, err := s.Sports.PublicEvent(ctx, share.Target.EventID)
			if err == nil {
				preview.SportEvent = event
			}
		}
		preview.Unavailable = preview.SportEvent == nil
	case KindConcert:
		if s.Concerts != nil {
			preview.Concert = s.Concerts.Concert(ctx, share.Target.EventID)
		}
		preview.Unavailable = preview.Concert == nil
	}
	if share.Sender != nil {
		if viewer != nil {
			known, err := s.mayKnowSender(ctx, *viewer, *share.Sender)
			if err != nil {
				return Preview{}, err
			}
			if known {
				user, err := s.Social.Store.User(ctx, *share.Sender)
				if err != nil {
					return Preview{}, err
				}
				if user != nil {
					preview.From = &Sender{User: *user, Note: share.Note}
				}
			}
		}
		telemetry.Capture(telemetry.ShareOpened, *share.Sender, map[string]string{"kind": string(share.Target.Kind)})
	}
	return preview, nil
}

// mayKnowSender: the sender and their friends see who sent it. A block either way hides it, and
// only it: the content stays public.
func (s *Service) mayKnowSender(ctx context.Context, viewer, sender uuid.UUID) (bool, error) {
	rel, err := s.Social.Relationship(ctx, viewer, sender)
	if apperr.From(err) != nil {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return rel == social.RelationshipSelf || rel == social.RelationshipFriend, nil
}

// knownSportEvent is a match the provider knows; validating here keeps junk ids from costing
// calls later.
func (s *Service) knownSportEvent(ctx context.Context, id string) (string, error) {
	id, err := ValidSportID(id)
	if err != nil {
		return "", err
	}
	var event *sports.Event
	if s.Sports != nil {
		event, _ = s.Sports.PublicEvent(ctx, id)
	}
	if event == nil {
		return "", Invalid("That match isn't available to share.")
	}
	return id, nil
}

// knownConcert is a concert the provider knows, for the same reason.
func (s *Service) knownConcert(ctx context.Context, id string) (string, error) {
	id, err := ValidConcertID(id)
	if err != nil {
		return "", err
	}
	if s.Concerts == nil || s.Concerts.Concert(ctx, id) == nil {
		return "", Invalid("That concert isn't available to share.")
	}
	return id, nil
}

// ValidNote is the note trimmed; blank is none. Counted in Unicode scalars, as Postgres's
// char_length counts them: an emoji with a skin tone is two.
func ValidNote(note *string) (*string, error) {
	if note == nil {
		return nil, nil //nolint:nilnil // no note
	}
	trimmed := strings.TrimSpace(*note)
	if trimmed == "" {
		return nil, nil //nolint:nilnil // blank is none
	}
	if core.Length(trimmed) > MaxNote {
		return nil, Invalid(fmt.Sprintf("A note is at most %d characters.", MaxNote))
	}
	return &trimmed, nil
}

// ValidSportID is 1–40 ASCII digits.
func ValidSportID(id string) (string, error) {
	n := core.Length(id)
	if n < 1 || n > 40 || strings.IndexFunc(id, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return "", Invalid("That isn't a sports event.")
	}
	return id, nil
}

var concertID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// ValidConcertID is 1–64 of [A-Za-z0-9_-].
func ValidConcertID(id string) (string, error) {
	if !concertID.MatchString(id) {
		return "", Invalid("That isn't a concert.")
	}
	return id, nil
}

// MARK: Store (PostgresShareStore.swift)

func columns(t Target) (title *uuid.UUID, sport, concert *string) {
	switch t.Kind {
	case KindTitle:
		id := t.TitleID
		return &id, nil, nil
	case KindSportEvent:
		id := t.EventID
		return nil, &id, nil
	default:
		id := t.EventID
		return nil, nil, &id
	}
}

func shareOf(r sqlc.Share) *Share {
	out := Share{Code: r.Code, Sender: r.SenderID, Note: r.Note, CreatedAt: r.CreatedAt, Target: Target{Kind: Kind(r.Kind)}}
	switch out.Target.Kind {
	case KindTitle:
		if r.TitleID == nil {
			return nil
		}
		out.Target.TitleID = *r.TitleID
	case KindSportEvent:
		if r.SportEventID == nil {
			return nil
		}
		out.Target.EventID = *r.SportEventID
	case KindConcert:
		if r.ConcertID == nil {
			return nil
		}
		out.Target.EventID = *r.ConcertID
	default:
		return nil
	}
	return &out
}

// Save inserts a link. A taken code is a constraint failure the caller retries.
func (s *Service) Save(ctx context.Context, share Share) error {
	title, sport, concert := columns(share.Target)
	err := s.Q.ShareCreate(ctx, sqlc.ShareCreateParams{
		Code: share.Code, SenderID: share.Sender, Kind: string(share.Target.Kind), TitleID: title, SportEventID: sport,
		ConcertID: concert, Note: share.Note, CreatedAt: share.CreatedAt,
	})
	if err != nil {
		return fmt.Errorf("create share: %w", err)
	}
	return nil
}

// Share is the link with this code, or nil.
func (s *Service) Share(ctx context.Context, code string) (*Share, error) {
	row, err := s.Q.ShareByCode(ctx, code)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none
	}
	if err != nil {
		return nil, fmt.Errorf("share: %w", err)
	}
	return shareOf(row), nil
}

// existing is the sender's newest link to this target with exactly this note (nil matches nil).
func (s *Service) existing(ctx context.Context, sender uuid.UUID, target Target, note *string) (*Share, error) {
	title, sport, concert := columns(target)
	row, err := s.Q.ShareExisting(ctx, sqlc.ShareExistingParams{
		SenderID: sender, Kind: string(target.Kind), TitleID: title, SportEventID: sport, ConcertID: concert, Note: note,
	})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none
	}
	if err != nil {
		return nil, fmt.Errorf("existing share: %w", err)
	}
	return shareOf(row), nil
}
