package social

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/ratelimit"
	"aaru-go-api/internal/telemetry"
	"context"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Limits (SocialService.swift).
const (
	// MaxOutgoingRequests is how many pending requests a user may have out at once.
	MaxOutgoingRequests = 50
	// LookupsPerHour, RequestsPerHour and HandleChangesPerHour (SOC-008): handle lookups, friend
	// requests and handle changes a user may make per hour, counted apart, so nobody can walk
	// the handle space.
	LookupsPerHour       = 60
	RequestsPerHour      = 30
	HandleChangesPerHour = 10
	// MaxDisplayNameLength bounds a first or last name.
	MaxDisplayNameLength = 50
	// MaxAvatarBytes: apps send 512px at quality 0.85, far under this.
	MaxAvatarBytes = 1024 * 1024
)

// ReservedHandles are handles nobody may claim. `aaru` is how a group message tags the agent.
var ReservedHandles = map[string]bool{
	"aaru": true, "admin": true, "administrator": true, "everyone": true, "help": true, "here": true, "me": true,
	"moderator": true, "null": true, "official": true, "root": true, "staff": true, "support": true, "system": true,
	"undefined": true,
}

// ErrNoSuchUser is the one 404 for nobody, a stranger where a friend is needed, and a block.
var ErrNoSuchUser = apperr.NotFound("No one has that handle.")

// ErrNoAvatar is the one 404 for no avatar, an unknown user and a block.
var ErrNoAvatar = apperr.NotFound("No such avatar.")

var errRateLimited = apperr.RateLimited("Too many tries. Try again later.")

// ProfileReader reads a user's account (auth.Store).
type ProfileReader interface {
	Profile(ctx context.Context, id uuid.UUID) (auth.Profile, bool, error)
}

// Service is handles, friends, blocks, reports and avatars (SocialService.swift), friend views
// (FriendService.swift), invites (InviteService.swift), reactions and recommendations
// (InteractionService.swift) and favorites (FavoriteService.swift).
type Service struct {
	Store    *Store
	Profiles ProfileReader
	// Catalog resolves the titles invites, recommendations and favorites name, and reads them back.
	Catalog *catalog.Kit
	// Library adds an invite's or a recommendation's title exactly as a tap would.
	Library *library.Service
	// Gamification is nil-safe: nil awards nothing.
	Gamification *gamification.Service
	// WebBaseURL is the web origin an invite opens on; the apps claim the same paths.
	WebBaseURL string
	Now        func() time.Time

	lookupLimiter        *ratelimit.FixedWindow
	requestLimiter       *ratelimit.FixedWindow
	handleChangeLimiter  *ratelimit.FixedWindow
	invitePreviewLimiter *ratelimit.FixedWindow
	inviteRedeemLimiter  *ratelimit.FixedWindow
	recommendLimiter     *ratelimit.FixedWindow
}

// New builds the service. Its limiters live as long as it does: build one per process.
func New(store *Store, profiles ProfileReader, kit *catalog.Kit, lib *library.Service, gam *gamification.Service, webBaseURL string) *Service {
	return &Service{
		Store: store, Profiles: profiles, Catalog: kit, Library: lib, Gamification: gam,
		WebBaseURL: strings.TrimSuffix(webBaseURL, "/"), Now: time.Now,
		lookupLimiter:        ratelimit.New(LookupsPerHour, time.Hour),
		requestLimiter:       ratelimit.New(RequestsPerHour, time.Hour),
		handleChangeLimiter:  ratelimit.New(HandleChangesPerHour, time.Hour),
		invitePreviewLimiter: ratelimit.New(120, time.Hour),
		inviteRedeemLimiter:  ratelimit.New(20, time.Hour),
		recommendLimiter:     ratelimit.New(30, time.Hour),
	}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func invalid(field, message string) *apperr.Error { return apperr.Validation(field, message) }

// MARK: Profile

// ProfileChange is one edit of the profile. A field left nil keeps its saved value; an empty
// name clears it.
type ProfileChange struct {
	Handle    *string
	FirstName *string
	LastName  *string
	// DisplayName is what apps before SOC-001b send, every time, in place of the two names.
	DisplayName *string
}

func (s *Service) profile(ctx context.Context, id uuid.UUID) (auth.Profile, error) {
	p, found, err := s.Profiles.Profile(ctx, id)
	if err != nil {
		return auth.Profile{}, err
	}
	if !found {
		return auth.Profile{}, apperr.Unauthorized()
	}
	return p, nil
}

// SaveProfile saves a handle and names and returns the account.
func (s *Service) SaveProfile(ctx context.Context, user uuid.UUID, change ProfileChange) (auth.Profile, error) {
	var handle *string
	if change.Handle != nil {
		h, err := ValidHandle(*change.Handle)
		if err != nil {
			return auth.Profile{}, err
		}
		handle = &h
	}
	saved, err := s.profile(ctx, user)
	if err != nil {
		return auth.Profile{}, err
	}
	// A change counts before the store says "taken", which would otherwise answer who holds a
	// handle as fast as anyone asks. Resaving the current handle is free.
	if handle != nil && (saved.Handle == nil || *handle != *saved.Handle) {
		if !s.handleChangeLimiter.Allow(user.String(), s.now()) {
			return auth.Profile{}, errRateLimited
		}
	}
	current := Name{First: saved.FirstName, Last: saved.LastName}
	name, err := nameAfter(change, current)
	if err != nil {
		return auth.Profile{}, err
	}
	var write *Name
	if !sameName(name, current) {
		write = &name
	}
	if err := s.Store.SaveProfile(ctx, user, handle, write); err != nil {
		return auth.Profile{}, err
	}
	return s.profile(ctx, user)
}

// nameAfter is the names after a change. An older app sends its one name on every save, even
// when only the handle changed: the saved names joined is no change, anything else splits at
// the first space.
func nameAfter(change ProfileChange, saved Name) (Name, error) {
	if change.FirstName != nil || change.LastName != nil {
		out := saved
		if change.FirstName != nil {
			first, err := ValidName(change.FirstName, "firstName")
			if err != nil {
				return Name{}, err
			}
			out.First = first
		}
		if change.LastName != nil {
			last, err := ValidName(change.LastName, "lastName")
			if err != nil {
				return Name{}, err
			}
			out.Last = last
		}
		return out, nil
	}
	if change.DisplayName == nil {
		return saved, nil
	}
	name, err := ValidName(change.DisplayName, "displayName")
	if err != nil {
		return Name{}, err
	}
	if eqPtr(name, joinName(saved.First, saved.Last)) {
		return saved, nil
	}
	first, last := auth.SplitName(name)
	return Name{First: first, Last: last}, nil
}

func eqPtr(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func sameName(a, b Name) bool { return eqPtr(a.First, b.First) && eqPtr(a.Last, b.Last) }

var handlePattern = regexp.MustCompile(`^[a-z0-9_]{3,20}$`)

// ValidHandle is the handle trimmed and lowercased, or a 422.
func ValidHandle(raw string) (string, error) {
	handle := strings.ToLower(trimSpaces(raw))
	if !handlePattern.MatchString(handle) {
		return "", invalid("handle", "Use 3–20 letters, numbers or underscores.")
	}
	if ReservedHandles[handle] {
		return "", invalid("handle", "That handle is taken.")
	}
	return handle, nil
}

// ValidName is a first or last name trimmed; empty clears it.
func ValidName(raw *string, field string) (*string, error) {
	if raw == nil {
		return nil, nil //nolint:nilnil // no name
	}
	name := strings.TrimSpace(*raw)
	if name == "" {
		return nil, nil //nolint:nilnil // no name
	}
	if utf8.RuneCountInString(name) > MaxDisplayNameLength {
		return nil, invalid(field, fmt.Sprintf("Keep your name under %d characters.", MaxDisplayNameLength))
	}
	return &name, nil
}

// MARK: Lookup

// Lookup finds a user by handle. A friend or yourself costs nothing: the web opens a friend's
// profile through this lookup on every hover. Everything else counts, misses too, and past the
// budget all of it answers 429, so the limit itself tells nobody who exists.
func (s *Service) Lookup(ctx context.Context, handle string, viewer uuid.UUID) (User, Relationship, error) {
	user, rel, err := s.resolve(ctx, handle, viewer)
	if err != nil {
		if e := apperr.From(err); e != nil && e.Status == http.StatusNotFound {
			if !s.lookupLimiter.Allow(viewer.String(), s.now()) {
				return User{}, "", errRateLimited
			}
		}
		return User{}, "", err
	}
	if rel != RelationshipFriend && rel != RelationshipSelf {
		if !s.lookupLimiter.Allow(viewer.String(), s.now()) {
			return User{}, "", errRateLimited
		}
	}
	return user, rel, nil
}

func (s *Service) resolve(ctx context.Context, handle string, viewer uuid.UUID) (User, Relationship, error) {
	handle = strings.ToLower(trimSpaces(handle))
	user, err := s.Store.UserByHandle(ctx, handle)
	if err != nil {
		return User{}, "", err
	}
	if user == nil {
		return User{}, "", ErrNoSuchUser
	}
	rel, err := s.Relationship(ctx, viewer, user.ID)
	if err != nil {
		return User{}, "", err
	}
	return *user, rel, nil
}

// MARK: Requests

// SendRequest asks a user to be friends. Asking someone who already asked you accepts their
// request; asking a friend or asking twice changes nothing.
func (s *Service) SendRequest(ctx context.Context, viewer uuid.UUID, handle string) (User, Relationship, error) {
	if _, err := s.RequireHandle(ctx, viewer); err != nil {
		return User{}, "", err
	}
	// Every ask counts, no-ops too: walking handles is what the limit stops.
	if !s.requestLimiter.Allow(viewer.String(), s.now()) {
		return User{}, "", errRateLimited
	}
	target, current, err := s.resolve(ctx, handle, viewer)
	if err != nil {
		return User{}, "", err
	}
	switch current {
	case RelationshipSelf:
		return User{}, "", invalid("handle", "You can't add yourself.")
	case RelationshipFriend, RelationshipOutgoing:
		return target, current, nil
	case RelationshipIncoming:
		id, err := s.Store.PendingRequest(ctx, target.ID, viewer)
		if err != nil {
			return User{}, "", err
		}
		if id != nil {
			sender, err := s.Store.AcceptRequest(ctx, *id, viewer, s.now())
			if err != nil {
				return User{}, "", err
			}
			if sender != nil {
				s.friendAdded(ctx, viewer, target.ID)
			}
		}
		return target, RelationshipFriend, nil
	default:
		outgoing, err := s.Store.OutgoingRequests(ctx, viewer)
		if err != nil {
			return User{}, "", err
		}
		if len(outgoing) >= MaxOutgoingRequests {
			return User{}, "", invalid("handle", "You have too many requests waiting. Withdraw some first.")
		}
		if err := s.Store.CreateRequest(ctx, uuid.New(), viewer, target.ID, s.now()); err != nil {
			return User{}, "", err
		}
		return target, RelationshipOutgoing, nil
	}
}

// Requests are the viewer's incoming and outgoing requests.
func (s *Service) Requests(ctx context.Context, viewer uuid.UUID) (incoming, outgoing []FriendRequest, err error) {
	if incoming, err = s.Store.IncomingRequests(ctx, viewer); err != nil {
		return nil, nil, err
	}
	if outgoing, err = s.Store.OutgoingRequests(ctx, viewer); err != nil {
		return nil, nil, err
	}
	return incoming, outgoing, nil
}

var errNoSuchRequest = apperr.NotFound("No such request.")

// Accept accepts a request addressed to the viewer and returns the new friend.
func (s *Service) Accept(ctx context.Context, requestID, viewer uuid.UUID) (User, error) {
	sender, err := s.Store.AcceptRequest(ctx, requestID, viewer, s.now())
	if err != nil {
		return User{}, err
	}
	if sender == nil {
		return User{}, errNoSuchRequest
	}
	friend, err := s.Store.User(ctx, *sender)
	if err != nil {
		return User{}, err
	}
	if friend == nil {
		return User{}, errNoSuchRequest
	}
	telemetry.Capture(telemetry.FriendAdded, viewer, nil)
	s.friendAdded(ctx, viewer, *sender)
	return *friend, nil
}

// Withdraw declines a request to the viewer, or cancels one the viewer sent.
func (s *Service) Withdraw(ctx context.Context, requestID, viewer uuid.UUID) error {
	ok, err := s.Store.DeleteRequest(ctx, requestID, viewer)
	if err != nil {
		return err
	}
	if !ok {
		return errNoSuchRequest
	}
	return nil
}

// MARK: Friends and blocks

// Friends are the viewer's friends, by handle.
func (s *Service) Friends(ctx context.Context, viewer uuid.UUID) ([]User, error) {
	return s.Store.Friends(ctx, viewer)
}

// Unfriend ends a friendship.
func (s *Service) Unfriend(ctx context.Context, friend, viewer uuid.UUID) error {
	since, err := s.Store.FriendsSince(ctx, viewer, friend)
	if err != nil {
		return err
	}
	ended, err := s.Store.Unfriend(ctx, viewer, friend)
	if err != nil {
		return err
	}
	if !ended {
		return apperr.NotFound("Not a friend.")
	}
	if since != nil {
		s.friendEnded(ctx, viewer, friend, *since)
	}
	return nil
}

// Block blocks a user: any friendship and pending requests between them end.
func (s *Service) Block(ctx context.Context, target, viewer uuid.UUID) error {
	if target == viewer {
		return invalid("userId", "You can't block yourself.")
	}
	user, err := s.Store.User(ctx, target)
	if err != nil {
		return err
	}
	if user == nil {
		return ErrNoSuchUser
	}
	since, err := s.Store.FriendsSince(ctx, viewer, target)
	if err != nil {
		return err
	}
	if err := s.Store.Block(ctx, viewer, target, s.now()); err != nil {
		return err
	}
	if since != nil {
		s.friendEnded(ctx, viewer, target, *since)
	}
	return nil
}

// Unblock removes the viewer's block.
func (s *Service) Unblock(ctx context.Context, target, viewer uuid.UUID) error {
	ok, err := s.Store.Unblock(ctx, viewer, target)
	if err != nil {
		return err
	}
	if !ok {
		return apperr.NotFound("Not blocked.")
	}
	return nil
}

// Blocked are the users the viewer blocked.
func (s *Service) Blocked(ctx context.Context, viewer uuid.UUID) ([]User, error) {
	return s.Store.Blocked(ctx, viewer)
}

// Report reports a user to Aaru.
func (s *Service) Report(ctx context.Context, target uuid.UUID, reason ReportReason, note *string, viewer uuid.UUID) error {
	if target == viewer {
		return ErrNoSuchUser
	}
	user, err := s.Store.User(ctx, target)
	if err != nil {
		return err
	}
	if user == nil {
		return ErrNoSuchUser
	}
	var kept *string
	if note != nil {
		trimmed := strings.TrimSpace(*note)
		if utf8.RuneCountInString(trimmed) > 1000 {
			return invalid("note", "Keep the note under 1,000 characters.")
		}
		if trimmed != "" {
			kept = &trimmed
		}
	}
	return s.Store.SaveReport(ctx, Report{
		ID: uuid.New(), Reporter: viewer, Target: target, Reason: reason, Note: kept, CreatedAt: s.now(),
	})
}

// MARK: Rules

// RequireHandle is the viewer's social identity, or 422 `handle_required`.
func (s *Service) RequireHandle(ctx context.Context, viewer uuid.UUID) (User, error) {
	user, err := s.Store.User(ctx, viewer)
	if err != nil {
		return User{}, err
	}
	if user == nil {
		return User{}, apperr.New(http.StatusUnprocessableEntity, "handle_required",
			"Choose a handle first, so friends can see who you are.")
	}
	return *user, nil
}

// Relationship is where other stands with viewer. A block either way is ErrNoSuchUser.
func (s *Service) Relationship(ctx context.Context, viewer, other uuid.UUID) (Relationship, error) {
	if viewer == other {
		return RelationshipSelf, nil
	}
	blocked, err := s.Store.IsBlocked(ctx, viewer, other)
	if err != nil {
		return "", err
	}
	if blocked {
		return "", ErrNoSuchUser
	}
	friends, err := s.Store.AreFriends(ctx, viewer, other)
	if err != nil {
		return "", err
	}
	if friends {
		return RelationshipFriend, nil
	}
	out, err := s.Store.PendingRequest(ctx, viewer, other)
	if err != nil {
		return "", err
	}
	if out != nil {
		return RelationshipOutgoing, nil
	}
	in, err := s.Store.PendingRequest(ctx, other, viewer)
	if err != nil {
		return "", err
	}
	if in != nil {
		return RelationshipIncoming, nil
	}
	return RelationshipNone, nil
}

// isAppError reports an error a client would see (Swift's `catch is AppError`).
func isAppError(err error) bool {
	return apperr.From(err) != nil
}

func (s *Service) friendAdded(ctx context.Context, a, b uuid.UUID) {
	if s.Gamification != nil {
		s.Gamification.FriendAdded(ctx, a, b)
	}
}

func (s *Service) friendEnded(ctx context.Context, a, b uuid.UUID, since time.Time) {
	if s.Gamification != nil {
		s.Gamification.FriendEnded(ctx, a, b, since)
	}
}

// MARK: Avatars (SOC-001b)

// SaveAvatar replaces the user's avatar with one JPEG and returns the account.
func (s *Service) SaveAvatar(ctx context.Context, user uuid.UUID, image []byte) (auth.Profile, error) {
	if len(image) < 3 || image[0] != 0xFF || image[1] != 0xD8 || image[2] != 0xFF {
		return auth.Profile{}, apperr.New(http.StatusUnsupportedMediaType, "avatar_image_type", "Send the photo as a JPEG.")
	}
	if err := s.Store.SaveAvatar(ctx, user, image); err != nil {
		return auth.Profile{}, err
	}
	return s.profile(ctx, user)
}

// RemoveAvatar removes the user's avatar and returns the account.
func (s *Service) RemoveAvatar(ctx context.Context, user uuid.UUID) (auth.Profile, error) {
	if err := s.Store.DeleteAvatar(ctx, user); err != nil {
		return auth.Profile{}, err
	}
	return s.profile(ctx, user)
}

// Avatar is owner's avatar for viewer: a block either way is the same 404 as no avatar.
func (s *Service) Avatar(ctx context.Context, owner, viewer uuid.UUID) ([]byte, error) {
	if owner != viewer {
		blocked, err := s.Store.IsBlocked(ctx, viewer, owner)
		if err != nil {
			return nil, err
		}
		if blocked {
			return nil, ErrNoAvatar
		}
	}
	image, err := s.Store.Avatar(ctx, owner)
	if err != nil {
		return nil, err
	}
	if image == nil {
		return nil, ErrNoAvatar
	}
	return image, nil
}

// MARK: Titles

// titles reads titles by id, keyed by id.
func (s *Service) titles(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]core.Title, error) {
	out := map[uuid.UUID]core.Title{}
	unique := uniqueIDs(ids)
	if len(unique) == 0 || s.Catalog == nil {
		return out, nil
	}
	found, err := s.Catalog.Store.Titles(ctx, unique)
	if err != nil {
		return nil, err
	}
	for _, t := range found {
		if _, seen := out[t.ID]; !seen {
			out[t.ID] = t
		}
	}
	return out, nil
}

func (s *Service) title(ctx context.Context, id uuid.UUID) (*core.Title, error) {
	if s.Catalog == nil {
		return nil, nil //nolint:nilnil // no catalog
	}
	return s.Catalog.Store.Title(ctx, id)
}

func (s *Service) resolveTitle(ctx context.Context, ref core.MediaRef) (core.Title, error) {
	if s.Catalog == nil {
		return core.Title{}, errors.New("social: no catalog")
	}
	return s.Catalog.Resolver().Resolve(ctx, ref, nil)
}

// addToPlan adds a title to the user's Plan to watch as a tap would.
func (s *Service) addToPlan(ctx context.Context, title core.Title, user uuid.UUID) error {
	if s.Library == nil {
		return errors.New("social: no library")
	}
	id := title.ID
	status := core.StatusWishlist
	_, err := s.Library.Add(ctx, core.MediaRef{TitleID: &id, Type: title.Type}, &status, user, library.UserCaller)
	return err
}

func uniqueIDs(ids []uuid.UUID) []uuid.UUID {
	seen := map[uuid.UUID]bool{}
	out := make([]uuid.UUID, 0, len(ids))
	for _, id := range ids {
		if !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}
