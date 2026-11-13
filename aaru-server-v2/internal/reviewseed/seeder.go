// Package reviewseed fills App Review's account (REL-008): `aaru --seed-review`, a one-off Job.
// The review account (REVIEW_EMAIL, its fixed code) gets a library, a friend who cannot sign in,
// a Board post with comments, and a group with messages, so a reviewer has content to look at
// and someone else's content to report and block.
//
// Everything goes through the services the handlers call, as the two people's own taps would, so
// the journal, points and word filter apply as in the app. A second run changes nothing: each step
// looks for what it would make (the email identity, the handles, the library item for the title,
// the post and comment bodies, the group by name, the messages by client nonce) and skips what is
// there. It never deletes, and touches no account but these two.
package reviewseed

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/boards"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/social"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Seeder holds the services the seed writes through.
type Seeder struct {
	Auth    *auth.Service
	Social  *social.Service
	Library *library.Service
	Boards  *boards.Service
	Groups  *groups.Service
	Log     *slog.Logger
	Now     func() time.Time
}

// New builds the services as the API does, minus push and sockets: nobody is told of the seed.
func New(pool *pgxpool.Pool, kit *catalog.Kit, log *slog.Logger) *Seeder {
	game := gamification.New(pool, log)
	lib := library.NewService(library.NewStore(pool), kit, game, log)
	authStore := auth.NewStore(pool)
	return &Seeder{
		Auth:    auth.NewService(authStore, nil, nil, nil),
		Social:  social.New(social.NewStore(pool), authStore, kit, lib, game, ""),
		Library: lib,
		Boards:  boards.New(sqlc.New(pool), kit.Resolver(), lib),
		Groups:  groups.New(groups.NewStore(pool), kit, lib, game, log),
		Log:     log,
		Now:     time.Now,
	}
}

// Counts is what one step made, found already there, or could not make.
type Counts struct {
	Added, Kept, Failed int
}

// Report is what a run did.
type Report struct {
	Reviewer, Friend               uuid.UUID
	ReviewerCreated, FriendCreated bool
	ReviewerLibrary, FriendLibrary Counts
	// Blocked: one of the two blocked the other, so nothing social was touched.
	Blocked                   bool
	FriendshipMade            bool
	PostCreated               bool
	Comments                  Counts
	GroupCreated, GroupJoined bool
	Messages                  Counts
}

// Run seeds the account email signs in to. A title that does not resolve is logged and skipped;
// anything else that fails ends the run with its error.
func (s *Seeder) Run(ctx context.Context, email string) (Report, error) {
	var r Report
	start := s.Now()
	var err error
	if r.Reviewer, r.ReviewerCreated, err = s.reviewer(ctx, email); err != nil {
		return r, err
	}
	if r.Friend, r.FriendCreated, err = s.friend(ctx); err != nil {
		return r, err
	}
	titles := map[string]core.Title{}
	r.ReviewerLibrary = s.library(ctx, "reviewer", r.Reviewer, ReviewLibrary, titles)
	r.FriendLibrary = s.library(ctx, "friend", r.Friend, FriendLibrary, titles)

	if r.Blocked, err = s.Social.Store.IsBlocked(ctx, r.Reviewer, r.Friend); err != nil {
		return r, err
	}
	if r.Blocked {
		// The reviewer blocked her (or the reverse): that choice stands, and nothing is made around it.
		s.Log.InfoContext(ctx, "Review seed: social steps skipped, the two accounts are blocked")
		return r, nil
	}
	if r.FriendshipMade, err = s.friendship(ctx, r.Reviewer, r.Friend); err != nil {
		return r, err
	}
	if r.PostCreated, r.Comments, err = s.board(ctx, r.Reviewer, r.Friend, titles); err != nil {
		return r, err
	}
	if r.GroupCreated, r.GroupJoined, r.Messages, err = s.group(ctx, r.Reviewer, r.Friend, start); err != nil {
		return r, err
	}
	return r, nil
}

// reviewer is the review account, made as the first magic-link sign-in makes it, with its handle,
// names and first run finished. AI sharing stays unanswered: the reviewer must see the ask.
func (s *Seeder) reviewer(ctx context.Context, email string) (uuid.UUID, bool, error) {
	id, created, err := s.Auth.EnsureEmailUser(ctx, email)
	if err != nil {
		return uuid.Nil, false, fmt.Errorf("review account: %w", err)
	}
	named, err := s.profile(ctx, id, ReviewHandle, ReviewFirstName, ReviewLastName)
	if err != nil {
		return uuid.Nil, false, fmt.Errorf("review account profile: %w", err)
	}
	if err := s.Auth.Store.FinishOnboarding(ctx, id, false); err != nil {
		return uuid.Nil, false, err
	}
	s.Log.InfoContext(ctx, "Review seed: review account", "created", created, "handleSet", named)
	return id, created, nil
}

// friend is Mira: an account with no sign-in identity, found by her handle. A holder of that
// handle who can sign in is a real person, and the run stops rather than write to their account.
func (s *Seeder) friend(ctx context.Context) (uuid.UUID, bool, error) {
	holder, err := s.Social.Store.UserByHandle(ctx, FriendHandle)
	if err != nil {
		return uuid.Nil, false, err
	}
	created := false
	var id uuid.UUID
	if holder != nil {
		signsIn, err := s.Auth.Store.HasSignIn(ctx, holder.ID)
		if err != nil {
			return uuid.Nil, false, err
		}
		if signsIn {
			return uuid.Nil, false, fmt.Errorf("the handle %s belongs to an account that signs in; not seeding it", FriendHandle)
		}
		id = holder.ID
	} else {
		first := FriendFirstName
		if id, err = s.Auth.Store.CreateUserWithoutSignIn(ctx, &first, nil); err != nil {
			return uuid.Nil, false, err
		}
		created = true
		if _, err := s.profile(ctx, id, FriendHandle, FriendFirstName, ""); err != nil {
			return uuid.Nil, false, fmt.Errorf("friend profile: %w", err)
		}
	}
	if err := s.Auth.Store.FinishOnboarding(ctx, id, false); err != nil {
		return uuid.Nil, false, err
	}
	s.Log.InfoContext(ctx, "Review seed: friend account", "handle", FriendHandle, "created", created)
	return id, created, nil
}

// profile claims handle and sets the names through the profile edit a client makes, unless the
// account has a handle already (a later run, or one the reviewer chose): then it is left alone.
func (s *Seeder) profile(ctx context.Context, id uuid.UUID, handle, first, last string) (bool, error) {
	current, found, err := s.Auth.Store.Profile(ctx, id)
	if err != nil {
		return false, err
	}
	if !found {
		return false, errors.New("account vanished")
	}
	if current.Handle != nil {
		return false, nil
	}
	change := social.ProfileChange{Handle: &handle, FirstName: &first}
	if last != "" {
		change.LastName = &last
	}
	if _, err := s.Social.SaveProfile(ctx, id, change); err != nil {
		return false, err
	}
	return true, nil
}

// library adds each seed the account does not have yet, as the account's own tap, then its
// rating, note, chapter and ticks. An item already there is left as it is. titles collects every
// resolved title by its name, for the Board post.
func (s *Seeder) library(ctx context.Context, who string, user uuid.UUID, seeds []Seed, titles map[string]core.Title) Counts {
	var c Counts
	resolver := s.Library.Catalog.Resolver()
	for _, seed := range seeds {
		title, err := resolver.Resolve(ctx, seed.Ref, nil)
		if err != nil {
			c.Failed++
			s.Log.WarnContext(ctx, "Review seed: title not resolved", "account", who, "title", seed.Name, "error", err.Error())
			continue
		}
		titles[seed.Name] = title
		existing, err := s.Library.ItemForTitle(ctx, user, title.ID)
		if err != nil {
			c.Failed++
			s.Log.WarnContext(ctx, "Review seed: library read", "account", who, "title", seed.Name, "error", err.Error())
			continue
		}
		if existing != nil {
			c.Kept++
			continue
		}
		if err := s.add(ctx, user, title, seed); err != nil {
			c.Failed++
			s.Log.WarnContext(ctx, "Review seed: library write", "account", who, "title", seed.Name, "error", err.Error())
			continue
		}
		c.Added++
	}
	s.Log.InfoContext(ctx, "Review seed: library", "account", who, "added", c.Added, "kept", c.Kept, "failed", c.Failed)
	return c
}

func (s *Seeder) add(ctx context.Context, user uuid.UUID, title core.Title, seed Seed) error {
	id := title.ID
	ref := core.MediaRef{TitleID: &id, Type: title.Type}
	status := seed.Status
	entry, err := s.Library.Add(ctx, ref, &status, user, library.UserCaller)
	if err != nil {
		return err
	}
	if seed.Episodes > 0 {
		if err := s.tick(ctx, user, entry.Item.ID, seed.Episodes); err != nil {
			return fmt.Errorf("ticks: %w", err)
		}
	}
	patch := library.ItemPatch{Rating: seed.Rating, Notes: seed.Notes, MangaChapter: seed.MangaChapter}
	if patch.Rating != nil || patch.Notes != nil || patch.MangaChapter != nil {
		if _, err := s.Library.Patch(ctx, entry.Item.ID, user, patch, library.UserCaller); err != nil {
			return fmt.Errorf("patch: %w", err)
		}
	}
	return nil
}

// tick marks the show's first count aired episodes watched, in one action.
func (s *Seeder) tick(ctx context.Context, user, item uuid.UUID, count int) error {
	show, err := s.Library.ShowContext(ctx, item, user)
	if err != nil {
		return err
	}
	now := s.Now()
	aired := make([]catalog.Episode, 0, len(show.Episodes))
	for _, ep := range show.Episodes {
		if ep.Season > 0 && library.HasAired(ep, show.Status, now) {
			aired = append(aired, ep)
		}
	}
	sort.Slice(aired, func(i, j int) bool {
		if aired[i].Season != aired[j].Season {
			return aired[i].Season < aired[j].Season
		}
		return aired[i].Episode < aired[j].Episode
	})
	if len(aired) == 0 {
		return errors.New("no aired episodes known")
	}
	keys := make([]core.EpisodeKey, 0, count)
	for _, ep := range aired[:min(count, len(aired))] {
		key, err := core.NewEpisodeKey(ep.Season, ep.Episode)
		if err != nil {
			return err
		}
		keys = append(keys, key)
	}
	_, err = s.Library.SetEpisodes(ctx, item, user, keys, true, library.UserCaller)
	return err
}

// friendship makes the two friends the way two people do: she asks, he asks back (which accepts).
func (s *Seeder) friendship(ctx context.Context, reviewer, friend uuid.UUID) (bool, error) {
	already, err := s.Social.Store.AreFriends(ctx, reviewer, friend)
	if err != nil || already {
		s.Log.InfoContext(ctx, "Review seed: friendship", "made", false)
		return false, err
	}
	reviewerUser, err := s.Social.RequireHandle(ctx, reviewer)
	if err != nil {
		return false, err
	}
	if _, _, err := s.Social.SendRequest(ctx, friend, reviewerUser.Handle); err != nil {
		return false, fmt.Errorf("friend request: %w", err)
	}
	_, rel, err := s.Social.SendRequest(ctx, reviewer, FriendHandle)
	if err != nil {
		return false, fmt.Errorf("accept friend request: %w", err)
	}
	if rel != social.RelationshipFriend {
		return false, fmt.Errorf("friendship not made: %s", rel)
	}
	s.Log.InfoContext(ctx, "Review seed: friendship", "made", true)
	return true, nil
}

// board is Mira's post about PostTitle with her rating, her comment, and the reviewer's.
func (s *Seeder) board(ctx context.Context, reviewer, friend uuid.UUID, titles map[string]core.Title) (bool, Counts, error) {
	var c Counts
	limit := boards.MaxPageSize
	feed, err := s.Boards.Feed(ctx, boards.SortRecent, nil, &limit, friend)
	if err != nil {
		return false, c, err
	}
	var post *boards.Post
	for i := range feed.Posts {
		if feed.Posts[i].Author.ID == friend && feed.Posts[i].Body == PostBody {
			post = &feed.Posts[i]
			break
		}
	}
	created := false
	if post == nil {
		var ref *core.MediaRef
		var rating *float64
		if title, ok := titles["Paddington 2"]; ok {
			id := title.ID
			ref = &core.MediaRef{TitleID: &id, Type: title.Type}
			value := PostRating
			rating = &value
		}
		made, err := s.Boards.Create(ctx, PostBody, ref, rating, groups.SpoilerChoice{Kind: groups.SpoilerFree}, friend)
		if err != nil {
			return false, c, fmt.Errorf("board post: %w", err)
		}
		post, created = &made, true
	}
	commentLimit := boards.MaxCommentPageSize
	existing, err := s.Boards.Comments(ctx, post.ID, nil, &commentLimit, friend)
	if err != nil {
		return created, c, err
	}
	for _, want := range []struct {
		author uuid.UUID
		body   string
	}{{friend, FriendCommentBody}, {reviewer, ReviewCommentBody}} {
		found := false
		for _, have := range existing.Items {
			if have.Author != nil && have.Author.ID == want.author && have.Body == want.body {
				found = true
				break
			}
		}
		if found {
			c.Kept++
			continue
		}
		if _, err := s.Boards.AddComment(ctx, post.ID, want.body, nil, want.author); err != nil {
			return created, c, fmt.Errorf("board comment: %w", err)
		}
		c.Added++
	}
	s.Log.InfoContext(ctx, "Review seed: board", "postCreated", created, "commentsAdded", c.Added, "commentsKept", c.Kept)
	return created, c, nil
}

// group is Mira's "Film club" with the reviewer in it and a few #general messages. A message is
// posted with a fixed client nonce: posting it again returns the first, so nothing doubles.
func (s *Seeder) group(ctx context.Context, reviewer, friend uuid.UUID, start time.Time) (bool, bool, Counts, error) {
	var c Counts
	owned, err := s.Groups.Groups(ctx, friend)
	if err != nil {
		return false, false, c, err
	}
	var club *groups.Summary
	for i := range owned {
		if owned[i].Name == GroupName && owned[i].Role == groups.RoleOwner {
			club = &owned[i]
			break
		}
	}
	created := false
	if club == nil {
		detail, err := s.Groups.Create(ctx, GroupName, friend)
		if err != nil {
			return false, false, c, fmt.Errorf("group: %w", err)
		}
		club, created = &detail.Summary, true
	}
	joined, err := s.join(ctx, club.ID, reviewer, friend)
	if err != nil {
		return created, false, c, err
	}
	for _, m := range GroupMessages {
		author := friend
		if m.ByReviewer {
			author = reviewer
		}
		nonce := m.Nonce
		posted, err := s.Groups.Post(ctx, club.ID, club.DefaultChannelID, m.Body, &nonce, groups.SpoilerChoice{Kind: groups.SpoilerFree}, author)
		if err != nil {
			return created, joined, c, fmt.Errorf("group message: %w", err)
		}
		if posted.CreatedAt.Before(start) {
			c.Kept++
		} else {
			c.Added++
		}
	}
	s.Log.InfoContext(ctx, "Review seed: group", "created", created, "reviewerJoined", joined,
		"messagesAdded", c.Added, "messagesKept", c.Kept)
	return created, joined, c, nil
}

// join invites the reviewer and accepts for them, unless they are in the group already.
func (s *Seeder) join(ctx context.Context, group, reviewer, friend uuid.UUID) (bool, error) {
	mine, err := s.Groups.Groups(ctx, reviewer)
	if err != nil {
		return false, err
	}
	for _, g := range mine {
		if g.ID == group {
			return false, nil
		}
	}
	if err := s.Groups.Invite(ctx, group, reviewer, friend); err != nil {
		return false, fmt.Errorf("group invite: %w", err)
	}
	invites, err := s.Groups.Invites(ctx, reviewer)
	if err != nil {
		return false, err
	}
	for _, inv := range invites {
		if inv.GroupID == group {
			if _, err := s.Groups.Accept(ctx, inv.ID, reviewer); err != nil {
				return false, fmt.Errorf("group accept: %w", err)
			}
			return true, nil
		}
	}
	return false, errors.New("group invite not found")
}
