package social

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Reactions and recommendations (SOC-007, SOC-006; PostgresInteractionStore.swift) and favorites
// (FAV-001; PostgresFavoriteStore.swift).

// ActivityKey is one activity row: a person's title on one UTC day. Its id is
// `{owner}-{title}-{yyyy-MM-dd}`, the ids uppercase as Swift printed them.
type ActivityKey struct {
	Owner   uuid.UUID
	TitleID uuid.UUID
	Day     string
}

// ID is the row's wire id.
func (k ActivityKey) ID() string {
	return strings.ToUpper(k.Owner.String()) + "-" + strings.ToUpper(k.TitleID.String()) + "-" + k.Day
}

var dayPattern = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

// ParseActivityKey reads a row id; false for anything malformed.
func ParseActivityKey(id string) (ActivityKey, bool) {
	const uuidLength = 36
	if len(id) != uuidLength*2+12 {
		return ActivityKey{}, false
	}
	owner, err1 := uuid.Parse(id[:uuidLength])
	title, err2 := uuid.Parse(id[uuidLength+1 : uuidLength*2+1])
	day := id[len(id)-10:]
	if err1 != nil || err2 != nil || !dayPattern.MatchString(day) {
		return ActivityKey{}, false
	}
	return ActivityKey{Owner: owner, TitleID: title, Day: day}, true
}

// Reactions are the emoji Aaru offers, the only ones the table accepts.
var Reactions = []string{"❤️", "😂", "😮", "😭", "🔥", "👏"}

// ReactionOrder is where an emoji sits in the set, for a stable order between equal counts.
func ReactionOrder(emoji string) int {
	for i, e := range Reactions {
		if e == emoji {
			return i
		}
	}
	return len(Reactions)
}

// ReactionSummary is the reactions on one activity row: how many of each, and the viewer's own.
type ReactionSummary struct {
	Counts map[string]int
	Mine   *string
}

// Recommendation is a title one friend sent another, waiting to be added or dismissed.
type Recommendation struct {
	ID        uuid.UUID
	Sender    uuid.UUID
	Recipient uuid.UUID
	TitleID   uuid.UUID
	Note      *string
	CreatedAt time.Time
}

// ReactionsOn are the reactions on these rows, as the viewer sees them.
func (s *Store) ReactionsOn(ctx context.Context, rows []ActivityKey, viewer uuid.UUID) (map[ActivityKey]ReactionSummary, error) {
	out := map[ActivityKey]ReactionSummary{}
	if len(rows) == 0 {
		return out, nil
	}
	wanted := make(map[ActivityKey]bool, len(rows))
	params := sqlc.SocialReactionsParams{Viewer: viewer}
	for _, r := range rows {
		wanted[r] = true
		params.Owners = append(params.Owners, r.Owner)
		params.Titles = append(params.Titles, r.TitleID)
		params.Days = append(params.Days, r.Day)
	}
	found, err := s.Q.SocialReactions(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("reactions: %w", err)
	}
	for _, r := range found {
		key := ActivityKey{Owner: r.OwnerID, TitleID: r.TitleID, Day: r.Day}
		if !wanted[key] {
			continue
		}
		summary := out[key]
		if summary.Counts == nil {
			summary.Counts = map[string]int{}
		}
		summary.Counts[r.Emoji] = int(r.Count)
		if r.Mine {
			emoji := r.Emoji
			summary.Mine = &emoji
		}
		out[key] = summary
	}
	return out, nil
}

// React sets the user's reaction on a row, or removes it when emoji is nil.
func (s *Store) React(ctx context.Context, emoji *string, row ActivityKey, user uuid.UUID, now time.Time) error {
	var err error
	if emoji == nil {
		err = s.Q.SocialClearReaction(ctx, sqlc.SocialClearReactionParams{
			UserID: user, OwnerID: row.Owner, TitleID: row.TitleID, Day: row.Day,
		})
	} else {
		err = s.Q.SocialSetReaction(ctx, sqlc.SocialSetReactionParams{
			UserID: user, OwnerID: row.Owner, TitleID: row.TitleID, Day: row.Day, Emoji: *emoji, CreatedAt: now,
		})
	}
	if err != nil {
		return fmt.Errorf("react: %w", err)
	}
	return nil
}

// Recommend inserts recommendations; one already waiting for the same pair and title is left alone.
func (s *Store) Recommend(ctx context.Context, items []Recommendation) error {
	for _, item := range items {
		if err := s.Q.SocialRecommend(ctx, sqlc.SocialRecommendParams{
			ID: item.ID, FromUserID: item.Sender, ToUserID: item.Recipient, TitleID: item.TitleID, Note: item.Note,
			CreatedAt: item.CreatedAt,
		}); err != nil {
			return fmt.Errorf("recommend: %w", err)
		}
	}
	return nil
}

// Inbox is the waiting recommendations to user from people who are still their friends, newest first.
func (s *Store) Inbox(ctx context.Context, user uuid.UUID, limit int) ([]Recommendation, error) {
	rows, err := s.Q.SocialInbox(ctx, sqlc.SocialInboxParams{ToUserID: user, Limit: int32(limit)}) //nolint:gosec // a small constant
	if err != nil {
		return nil, fmt.Errorf("inbox: %w", err)
	}
	out := make([]Recommendation, 0, len(rows))
	for _, r := range rows {
		out = append(out, Recommendation{
			ID: r.ID, Sender: r.FromUserID, Recipient: r.ToUserID, TitleID: r.TitleID, Note: r.Note, CreatedAt: r.CreatedAt,
		})
	}
	return out, nil
}

// ResolveRecommendation marks a waiting recommendation to user added or dismissed. Nil when none
// was waiting.
func (s *Store) ResolveRecommendation(ctx context.Context, id, user uuid.UUID, added bool, now time.Time) (*Recommendation, error) {
	var (
		row sqlc.SocialMarkRecommendationAddedRow
		err error
	)
	if added {
		row, err = s.Q.SocialMarkRecommendationAdded(ctx, sqlc.SocialMarkRecommendationAddedParams{Now: &now, ID: id, UserID: user})
	} else {
		var dismissed sqlc.SocialMarkRecommendationDismissedRow
		dismissed, err = s.Q.SocialMarkRecommendationDismissed(ctx, sqlc.SocialMarkRecommendationDismissedParams{Now: &now, ID: id, UserID: user})
		row = sqlc.SocialMarkRecommendationAddedRow(dismissed)
	}
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none waiting
	}
	if err != nil {
		return nil, fmt.Errorf("resolve recommendation: %w", err)
	}
	return &Recommendation{
		ID: row.ID, Sender: row.FromUserID, Recipient: row.ToUserID, TitleID: row.TitleID, Note: row.Note, CreatedAt: row.CreatedAt,
	}, nil
}

// FavoriteIDs are every kind the user has favorites in, each in the user's order.
func (s *Store) FavoriteIDs(ctx context.Context, user uuid.UUID) (map[FavoriteKind][]uuid.UUID, error) {
	rows, err := s.Q.FavoritesOf(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("favorites: %w", err)
	}
	out := map[FavoriteKind][]uuid.UUID{}
	for _, r := range rows {
		kind := FavoriteKind(r.Kind)
		if !kind.Valid() {
			continue
		}
		out[kind] = append(out[kind], r.TitleID)
	}
	return out, nil
}

// ReplaceFavorites replaces one kind with these titles, in this order.
func (s *Store) ReplaceFavorites(ctx context.Context, titles []uuid.UUID, kind FavoriteKind, user uuid.UUID) error {
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.FavoritesClearKind(ctx, sqlc.FavoritesClearKindParams{UserID: user, Kind: string(kind)}); err != nil {
			return err
		}
		if len(titles) == 0 {
			return nil
		}
		return q.FavoritesInsertKind(ctx, sqlc.FavoritesInsertKindParams{UserID: user, Kind: string(kind), TitleIds: titles})
	})
	if err != nil {
		return fmt.Errorf("replace favorites: %w", err)
	}
	return nil
}
