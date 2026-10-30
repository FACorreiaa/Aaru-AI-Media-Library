package social

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"time"

	"github.com/google/uuid"
)

// Friend invite links (SOC-002; InviteService.swift). One link per invite, spent by the first
// person who accepts it while it is live. Accepting makes both people friends at once: the
// inviter asked by sending it, the invitee by opening it.
//
// Every dead end reads the same: an unknown, expired, revoked or spent code, an inviter who
// left, and a block either way all answer one 404, so a link reveals nothing it shouldn't.

const (
	// InviteLifetime is how long a link stays open.
	InviteLifetime = 14 * 24 * time.Hour
	// MaxOpenInvites is how many open links one user may have.
	MaxOpenInvites = 20
	// CodeLength is an invite's (and a share link's) code length.
	CodeLength = 12
)

const codeAlphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

// ErrNoSuchInvite is the one dead end.
var ErrNoSuchInvite = apperr.NotFound("This invite isn't valid anymore.")

var errInviteRateLimited = apperr.RateLimited("Too many invite attempts. Try again later.")

// NewCode is a random code from [a-zA-Z0-9], CodeLength long.
func NewCode() string {
	out := make([]byte, CodeLength)
	limit := big.NewInt(int64(len(codeAlphabet)))
	for i := range out {
		n, err := rand.Int(rand.Reader, limit)
		if err != nil {
			panic(fmt.Sprintf("crypto/rand: %v", err))
		}
		out[i] = codeAlphabet[n.Int64()]
	}
	return string(out)
}

// InvitePreview is what an invite link shows before anyone signs in: who sent it and the title
// it carries. Never library data.
type InvitePreview struct {
	Invite  Invite
	Inviter User
	Title   *core.Title
	// Relationship is where the signed-in viewer stands with the inviter; nil when signed out.
	Relationship *Relationship
}

// InviteURL is the link to share.
func (s *Service) InviteURL(i Invite) string {
	return s.WebBaseURL + "/i/" + i.Code
}

// CreateInvite makes a link, optionally carrying one title. Needs the inviter's handle, so the
// person opening it sees who sent it.
func (s *Service) CreateInvite(ctx context.Context, viewer uuid.UUID, ref *core.MediaRef) (Invite, *core.Title, error) {
	if _, err := s.RequireHandle(ctx, viewer); err != nil {
		return Invite{}, nil, err
	}
	open, err := s.Store.OpenInvites(ctx, viewer, s.now())
	if err != nil {
		return Invite{}, nil, err
	}
	if len(open) >= MaxOpenInvites {
		return Invite{}, nil, apperr.New(http.StatusUnprocessableEntity, "too_many_invites",
			fmt.Sprintf("You have %d invites waiting. Revoke some first.", MaxOpenInvites))
	}
	var title *core.Title
	if ref != nil {
		t, err := s.resolveTitle(ctx, *ref)
		if err != nil {
			return Invite{}, nil, err
		}
		title = &t
	}
	created := s.now()
	for range 3 {
		invite := Invite{
			ID: uuid.New(), Code: NewCode(), Inviter: viewer, CreatedAt: created, ExpiresAt: created.Add(InviteLifetime),
		}
		if title != nil {
			id := title.ID
			invite.TitleID = &id
		}
		err := s.Store.CreateInvite(ctx, invite)
		var conflict errConflict
		if errors.As(err, &conflict) {
			continue
		}
		if err != nil {
			return Invite{}, nil, err
		}
		return invite, title, nil
	}
	return Invite{}, nil, apperr.New(http.StatusInternalServerError, "internal", "Couldn't make an invite. Try again.")
}

// OpenInvite is an open invite with the title it carries.
type OpenInvite struct {
	Invite Invite
	Title  *core.Title
}

// OpenInvites are the viewer's open invites, newest first.
func (s *Service) OpenInvites(ctx context.Context, viewer uuid.UUID) ([]OpenInvite, error) {
	invites, err := s.Store.OpenInvites(ctx, viewer, s.now())
	if err != nil {
		return nil, err
	}
	var ids []uuid.UUID
	for _, i := range invites {
		if i.TitleID != nil {
			ids = append(ids, *i.TitleID)
		}
	}
	titles, err := s.titles(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := make([]OpenInvite, 0, len(invites))
	for _, i := range invites {
		item := OpenInvite{Invite: i}
		if i.TitleID != nil {
			if t, ok := titles[*i.TitleID]; ok {
				item.Title = &t
			}
		}
		out = append(out, item)
	}
	return out, nil
}

// RevokeInvite revokes one of the viewer's open invites.
func (s *Service) RevokeInvite(ctx context.Context, code string, viewer uuid.UUID) error {
	ok, err := s.Store.RevokeInvite(ctx, code, viewer, s.now())
	if err != nil {
		return err
	}
	if !ok {
		return ErrNoSuchInvite
	}
	return nil
}

// openInvite is the live invite and its inviter, or ErrNoSuchInvite.
func (s *Service) openInvite(ctx context.Context, code string) (Invite, User, error) {
	invite, err := s.Store.Invite(ctx, code)
	if err != nil {
		return Invite{}, User{}, err
	}
	if invite == nil || !invite.IsOpen(s.now()) {
		return Invite{}, User{}, ErrNoSuchInvite
	}
	inviter, err := s.Store.User(ctx, invite.Inviter)
	if err != nil {
		return Invite{}, User{}, err
	}
	if inviter == nil {
		return Invite{}, User{}, ErrNoSuchInvite
	}
	return *invite, *inviter, nil
}

// PreviewInvite is what the link shows. viewer is nil when the person opening it is signed out.
// Previews are public, so they are limited per client address.
func (s *Service) PreviewInvite(ctx context.Context, code string, viewer *uuid.UUID, clientAddress string) (InvitePreview, error) {
	if !s.invitePreviewLimiter.Allow(clientAddress, s.now()) {
		return InvitePreview{}, errInviteRateLimited
	}
	invite, inviter, err := s.openInvite(ctx, code)
	if err != nil {
		return InvitePreview{}, err
	}
	preview := InvitePreview{Invite: invite, Inviter: inviter}
	if viewer != nil {
		rel, err := s.Relationship(ctx, *viewer, inviter.ID)
		if isAppError(err) {
			return InvitePreview{}, ErrNoSuchInvite
		}
		if err != nil {
			return InvitePreview{}, err
		}
		preview.Relationship = &rel
	}
	if invite.TitleID != nil {
		if preview.Title, err = s.title(ctx, *invite.TitleID); err != nil {
			return InvitePreview{}, err
		}
	}
	return preview, nil
}

// RedeemInvite accepts the invite: the two become friends and the link is spent. Already friends
// is a success that leaves the link unspent. addTitle puts the invite's title on the viewer's
// Plan to watch exactly as a tap would, and never touches a title they already have.
func (s *Service) RedeemInvite(ctx context.Context, code string, viewer uuid.UUID, addTitle bool) (User, bool, error) {
	if !s.inviteRedeemLimiter.Allow(viewer.String(), s.now()) {
		return User{}, false, errInviteRateLimited
	}
	if _, err := s.RequireHandle(ctx, viewer); err != nil {
		return User{}, false, err
	}
	invite, inviter, err := s.openInvite(ctx, code)
	if err != nil {
		return User{}, false, err
	}
	rel, err := s.Relationship(ctx, viewer, inviter.ID)
	if isAppError(err) {
		return User{}, false, ErrNoSuchInvite
	}
	if err != nil {
		return User{}, false, err
	}
	switch rel {
	case RelationshipSelf:
		return User{}, false, apperr.New(http.StatusConflict, "own_invite", "This is your own invite. Send it to a friend.")
	case RelationshipFriend:
	default:
		spent, err := s.Store.RedeemInvite(ctx, code, viewer, s.now())
		if err != nil {
			return User{}, false, err
		}
		if spent == nil {
			return User{}, false, ErrNoSuchInvite
		}
		s.friendAdded(ctx, viewer, inviter.ID)
	}
	titleAdded := false
	if addTitle && invite.TitleID != nil {
		title, err := s.title(ctx, *invite.TitleID)
		if err != nil {
			return User{}, false, err
		}
		if title != nil {
			has, err := s.Store.HasTitle(ctx, viewer, title.ID)
			if err != nil {
				return User{}, false, err
			}
			if !has {
				if err := s.addToPlan(ctx, *title, viewer); err != nil {
					return User{}, false, err
				}
				titleAdded = true
			}
		}
	}
	return inviter, titleAdded, nil
}
