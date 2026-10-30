package groups

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is groups, members, invites, channels, messages and the kind data
// (PostgresGroupStore*.swift). It answers what is asked and keeps multi-row changes in one
// transaction; the rules live in Service.
type Store struct {
	Q    *sqlc.Queries
	Pool *pgxpool.Pool
}

// NewStore is a store over the pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{Q: sqlc.New(pool), Pool: pool} }

func coreStatus(s string) *core.LibraryStatus {
	status := core.LibraryStatus(s)
	if !status.Valid() {
		return nil
	}
	return &status
}

func user(id uuid.UUID, handle string, display *string, avatar *int64) User {
	return User{ID: id, Handle: handle, DisplayName: display, AvatarVersion: avatar}
}

// optionalUser is a user from a LEFT JOIN: nil when the account or its handle is gone.
func optionalUser(id *uuid.UUID, handle, display *string, avatar *int64) *User {
	if id == nil || handle == nil {
		return nil
	}
	u := user(*id, *handle, display, avatar)
	return &u
}

// isUniqueViolation is Postgres's 23505.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// MARK: Groups

// Summaries are the viewer's groups, in the order they joined them.
func (s *Store) Summaries(ctx context.Context, viewer uuid.UUID) ([]Summary, error) {
	return s.summaries(ctx, viewer, nil)
}

// Summary is one of the viewer's groups; nil when they are not a member.
func (s *Store) Summary(ctx context.Context, group, viewer uuid.UUID) (*Summary, error) {
	found, err := s.summaries(ctx, viewer, &group)
	if err != nil || len(found) == 0 {
		return nil, err
	}
	return &found[0], nil
}

func (s *Store) summaries(ctx context.Context, viewer uuid.UUID, group *uuid.UUID) ([]Summary, error) {
	rows, err := s.Q.GroupSummaries(ctx, sqlc.GroupSummariesParams{Viewer: viewer, OnlyGroup: group})
	if err != nil {
		return nil, fmt.Errorf("group summaries: %w", err)
	}
	out := make([]Summary, len(rows))
	for i, r := range rows {
		out[i] = Summary{
			ID: r.ID, Name: r.Name, Role: parseRole(r.Role), DefaultChannelID: r.DefaultChannelID,
			Unread: int(r.Unread), Mentions: int(r.Mentions), ShareProgress: r.ShareProgress, Muted: r.Muted,
		}
	}
	return out, nil
}

// OwnedCount is how many groups the user owns.
func (s *Store) OwnedCount(ctx context.Context, user uuid.UUID) (int, error) {
	n, err := s.Q.GroupOwnedCount(ctx, user)
	if err != nil {
		return 0, fmt.Errorf("owned groups: %w", err)
	}
	return int(n), nil
}

// CreateGroup inserts the group, its owner and its default text channel together.
func (s *Store) CreateGroup(ctx context.Context, id uuid.UUID, name string, owner uuid.UUID, general Channel, now time.Time) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.InsertGroup(ctx, sqlc.InsertGroupParams{ID: id, Name: name, CreatedAt: now}); err != nil {
			return fmt.Errorf("insert group: %w", err)
		}
		if err := q.InsertGroupMember(ctx, sqlc.InsertGroupMemberParams{
			GroupID: id, UserID: owner, Role: string(RoleOwner), JoinedAt: now,
		}); err != nil {
			return fmt.Errorf("insert owner: %w", err)
		}
		return insertChannel(ctx, q, general)
	})
}

// RenameGroup renames a group.
func (s *Store) RenameGroup(ctx context.Context, group uuid.UUID, name string, now time.Time) error {
	if err := s.Q.RenameGroup(ctx, sqlc.RenameGroupParams{ID: group, Name: name, UpdatedAt: now}); err != nil {
		return fmt.Errorf("rename group: %w", err)
	}
	return nil
}

// DeleteGroup deletes a group and, by cascade, everything in it.
func (s *Store) DeleteGroup(ctx context.Context, group uuid.UUID) error {
	if err := s.Q.DeleteGroup(ctx, group); err != nil {
		return fmt.Errorf("delete group: %w", err)
	}
	return nil
}

// MARK: Members

// Members are a group's members, in the order they joined.
func (s *Store) Members(ctx context.Context, group uuid.UUID) ([]Member, error) {
	rows, err := s.Q.GroupMembers(ctx, group)
	if err != nil {
		return nil, fmt.Errorf("group members: %w", err)
	}
	out := make([]Member, len(rows))
	for i, r := range rows {
		out[i] = Member{
			User: user(r.UserID, r.Handle, r.DisplayName, r.AvatarVersion), Role: parseRole(r.Role),
			JoinedAt: r.JoinedAt, ShareProgress: r.ShareProgress,
		}
	}
	return out, nil
}

// Role is the user's role in the group, or nil when they are not in it.
func (s *Store) Role(ctx context.Context, group, user uuid.UUID) (*Role, error) {
	raw, err := s.Q.GroupRole(ctx, sqlc.GroupRoleParams{GroupID: group, UserID: user})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // not a member, as Swift's optional
	}
	if err != nil {
		return nil, fmt.Errorf("group role: %w", err)
	}
	role := parseRole(raw)
	return &role, nil
}

// SetRole changes a member's role.
func (s *Store) SetRole(ctx context.Context, group, user uuid.UUID, role Role) error {
	if err := s.Q.SetGroupRole(ctx, sqlc.SetGroupRoleParams{GroupID: group, UserID: user, Role: string(role)}); err != nil {
		return fmt.Errorf("set role: %w", err)
	}
	return nil
}

// RemoveMember removes a member and their read state in the group.
func (s *Store) RemoveMember(ctx context.Context, group, user uuid.UUID) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		if err := q.DeleteGroupReadState(ctx, sqlc.DeleteGroupReadStateParams{GroupID: group, UserID: user}); err != nil {
			return fmt.Errorf("delete read state: %w", err)
		}
		if err := q.DeleteGroupMember(ctx, sqlc.DeleteGroupMemberParams{GroupID: group, UserID: user}); err != nil {
			return fmt.Errorf("delete member: %w", err)
		}
		return nil
	})
}

// TransferOwnership gives the new owner the role; the old owner becomes an admin.
func (s *Store) TransferOwnership(ctx context.Context, group, previous, next uuid.UUID) error {
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		// Demote first: one owner per group is a unique index.
		if err := q.SetGroupRole(ctx, sqlc.SetGroupRoleParams{GroupID: group, UserID: previous, Role: string(RoleAdmin)}); err != nil {
			return fmt.Errorf("demote owner: %w", err)
		}
		if err := q.SetGroupRole(ctx, sqlc.SetGroupRoleParams{GroupID: group, UserID: next, Role: string(RoleOwner)}); err != nil {
			return fmt.Errorf("promote owner: %w", err)
		}
		return nil
	})
}

// SetMuted silences or restores the group's mention alerts for one member.
func (s *Store) SetMuted(ctx context.Context, group, user uuid.UUID, muted bool) error {
	if err := s.Q.SetGroupMuted(ctx, sqlc.SetGroupMutedParams{GroupID: group, UserID: user, Muted: muted}); err != nil {
		return fmt.Errorf("set muted: %w", err)
	}
	return nil
}

// SetShareProgress shows or hides one member's progress in the group's title channels.
func (s *Store) SetShareProgress(ctx context.Context, group, user uuid.UUID, share bool) error {
	if err := s.Q.SetGroupShareProgress(ctx, sqlc.SetGroupShareProgressParams{GroupID: group, UserID: user, ShareProgress: share}); err != nil {
		return fmt.Errorf("set share progress: %w", err)
	}
	return nil
}

// MARK: Invites

// CreateInvite inserts an invite; a second invite to the same person is ignored. False when one
// was pending.
func (s *Store) CreateInvite(ctx context.Context, id, group, inviter, invitee uuid.UUID, now time.Time) (bool, error) {
	_, err := s.Q.InsertGroupInvite(ctx, sqlc.InsertGroupInviteParams{
		ID: id, GroupID: group, InviterID: inviter, InviteeID: invitee, CreatedAt: now,
	})
	if db.IsNoRows(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("insert invite: %w", err)
	}
	return true, nil
}

func (s *Store) invites(ctx context.Context, params sqlc.GroupInvitesParams) ([]Invite, error) {
	rows, err := s.Q.GroupInvites(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("group invites: %w", err)
	}
	out := make([]Invite, len(rows))
	for i, r := range rows {
		out[i] = Invite{
			ID: r.ID, GroupID: r.GroupID, GroupName: r.GroupName, CreatedAt: r.CreatedAt,
			Inviter: user(r.InviterID, r.InviterHandle, r.InviterDisplayName, r.InviterAvatarVersion),
			Invitee: user(r.InviteeID, r.InviteeHandle, r.InviteeDisplayName, r.InviteeAvatarVersion),
		}
	}
	return out, nil
}

// InvitesTo are the invites waiting for a user, newest first.
func (s *Store) InvitesTo(ctx context.Context, user uuid.UUID) ([]Invite, error) {
	return s.invites(ctx, sqlc.GroupInvitesParams{Invitee: &user})
}

// InvitesPending are a group's open invites, newest first.
func (s *Store) InvitesPending(ctx context.Context, group uuid.UUID) ([]Invite, error) {
	return s.invites(ctx, sqlc.GroupInvitesParams{InGroup: &group})
}

// AcceptInvite turns an invite to invitee into a membership, with every channel read up to now.
// Returns the group, or nil when no such invite is pending.
func (s *Store) AcceptInvite(ctx context.Context, id, invitee uuid.UUID, now time.Time) (*uuid.UUID, error) {
	var group *uuid.UUID
	err := pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		q := s.Q.WithTx(tx)
		g, err := q.TakeGroupInvite(ctx, sqlc.TakeGroupInviteParams{ID: id, InviteeID: invitee})
		if db.IsNoRows(err) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("take invite: %w", err)
		}
		if err := q.InsertGroupMember(ctx, sqlc.InsertGroupMemberParams{
			GroupID: g, UserID: invitee, Role: string(RoleMember), JoinedAt: now,
		}); err != nil {
			return fmt.Errorf("join group: %w", err)
		}
		if err := q.MarkGroupReadOnJoin(ctx, sqlc.MarkGroupReadOnJoinParams{UserID: invitee, Now: now, GroupID: g}); err != nil {
			return fmt.Errorf("read on join: %w", err)
		}
		group = &g
		return nil
	})
	return group, err
}

// DeleteInvite deletes an invite the invitee declines or the inviter cancels. Returns its group
// and invitee, or ok false when none was pending.
func (s *Store) DeleteInvite(ctx context.Context, id, party uuid.UUID) (group, invitee uuid.UUID, ok bool, err error) {
	row, err := s.Q.DeleteGroupInvite(ctx, sqlc.DeleteGroupInviteParams{ID: id, Party: party})
	if db.IsNoRows(err) {
		return uuid.Nil, uuid.Nil, false, nil
	}
	if err != nil {
		return uuid.Nil, uuid.Nil, false, fmt.Errorf("delete invite: %w", err)
	}
	return row.GroupID, row.InviteeID, true, nil
}

// MARK: Channels

func insertChannel(ctx context.Context, q *sqlc.Queries, c Channel) error {
	if err := q.InsertGroupChannel(ctx, sqlc.InsertGroupChannelParams{
		ID: c.ID, GroupID: c.GroupID, Kind: string(c.Kind), TitleID: c.TitleID, Name: c.Name, Topic: c.Topic,
		Position: int32(c.Position), IsDefault: c.IsDefault, CreatedAt: c.CreatedAt, //nolint:gosec // positions stay small
	}); err != nil {
		return fmt.Errorf("insert channel: %w", err)
	}
	return nil
}

// Channels are a group's channels by position, with the viewer's unread and mention counts.
func (s *Store) Channels(ctx context.Context, group, viewer uuid.UUID) ([]Channel, error) {
	rows, err := s.Q.GroupChannels(ctx, sqlc.GroupChannelsParams{Viewer: viewer, GroupID: group})
	if err != nil {
		return nil, fmt.Errorf("group channels: %w", err)
	}
	out := make([]Channel, len(rows))
	for i, r := range rows {
		out[i] = Channel{
			ID: r.ID, GroupID: r.GroupID, Kind: parseKind(r.Kind), TitleID: r.TitleID, Name: r.Name, Topic: r.Topic,
			Position: int(r.Position), IsDefault: r.IsDefault, CreatedAt: r.CreatedAt,
			Unread: int(r.Unread), Mentions: int(r.Mentions),
		}
	}
	return out, nil
}

// Channel is one channel in a group, or nil.
func (s *Store) Channel(ctx context.Context, id, group uuid.UUID) (*Channel, error) {
	r, err := s.Q.GroupChannel(ctx, sqlc.GroupChannelParams{ID: id, GroupID: group})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	if err != nil {
		return nil, fmt.Errorf("group channel: %w", err)
	}
	return &Channel{
		ID: r.ID, GroupID: r.GroupID, Kind: parseKind(r.Kind), TitleID: r.TitleID, Name: r.Name, Topic: r.Topic,
		Position: int(r.Position), IsDefault: r.IsDefault, CreatedAt: r.CreatedAt,
	}, nil
}

var errChannelNameTaken = apperr.Conflict("A channel already has that name.")

// CreateChannel adds a channel; 409 when the group already has one with that name.
func (s *Store) CreateChannel(ctx context.Context, c Channel) error {
	if err := insertChannel(ctx, s.Q, c); err != nil {
		if isUniqueViolation(err) {
			return errChannelNameTaken
		}
		return err
	}
	return nil
}

// UpdateChannel changes a channel. A nil name is left alone; setTopic replaces the topic with
// topic (nil clears it). 409 on a taken name.
func (s *Store) UpdateChannel(ctx context.Context, id uuid.UUID, name *string, setTopic bool, topic *string) error {
	err := s.Q.UpdateGroupChannel(ctx, sqlc.UpdateGroupChannelParams{Name: name, SetTopic: setTopic, Topic: topic, ID: id})
	if isUniqueViolation(err) {
		return errChannelNameTaken
	}
	if err != nil {
		return fmt.Errorf("update channel: %w", err)
	}
	return nil
}

// DeleteChannel deletes a channel and its messages. The default channel is never deleted.
func (s *Store) DeleteChannel(ctx context.Context, id uuid.UUID) (bool, error) {
	_, err := s.Q.DeleteGroupChannel(ctx, id)
	if db.IsNoRows(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("delete channel: %w", err)
	}
	return true, nil
}

// MARK: Messages

// componentJSON is a stored card: `{"type": "title", "titleId": "…"}`, ids uppercase as Swift wrote them.
type componentJSON struct {
	Type    string `json:"type"`
	TitleID string `json:"titleId"`
}

func componentsJSON(components []Component) json.RawMessage {
	if len(components) == 0 {
		return nil
	}
	items := make([]componentJSON, len(components))
	for i, c := range components {
		items[i] = componentJSON{Type: "title", TitleID: strings.ToUpper(c.TitleID.String())}
	}
	data, err := json.Marshal(items)
	if err != nil {
		return nil
	}
	return data
}

func parseComponents(raw json.RawMessage) []Component {
	if len(raw) == 0 {
		return nil
	}
	var items []map[string]any
	if json.Unmarshal(raw, &items) != nil {
		return nil
	}
	var out []Component
	for _, item := range items {
		s, ok := item["titleId"].(string)
		if !ok {
			continue
		}
		if id, err := uuid.Parse(s); err == nil {
			out = append(out, Component{TitleID: id})
		}
	}
	return out
}

func messageFromRow(r sqlc.GroupMessageRow) Message {
	m := Message{
		ID: r.ID, ChannelID: r.ChannelID, Author: optionalUser(r.AuthorID, r.AuthorHandle, r.AuthorDisplayName, r.AuthorAvatarVersion),
		Body: r.Body, Mentions: r.Mentions, MentionsAgent: r.MentionsAgent, CreatedAt: r.CreatedAt,
		EditedAt: r.EditedAt, DeletedAt: r.DeletedAt, ClientNonce: r.ClientNonce,
		FromAgent: r.AuthorKind == "agent", ReplyTo: r.ReplyTo, Components: parseComponents(r.Components),
	}
	if m.Mentions == nil {
		m.Mentions = []uuid.UUID{}
	}
	switch {
	case r.SpoilerEnding:
		m.Spoiler = EndingStamp()
	case r.SpoilerSeason != nil && r.SpoilerEpisode != nil:
		m.Spoiler = EpisodeStamp(EpisodePoint{Season: int(*r.SpoilerSeason), Episode: int(*r.SpoilerEpisode)})
	}
	return m
}

// Messages are up to limit messages in order, oldest first.
func (s *Store) Messages(ctx context.Context, channel uuid.UUID, cursor Cursor, limit int) ([]Message, error) {
	var rows []sqlc.GroupMessageRow
	var err error
	n := int32(limit) //nolint:gosec // limits are clamped to MaxPageSize
	switch cursor.Kind {
	case CursorBefore:
		var found []sqlc.GroupMessagesBeforeRow
		found, err = s.Q.GroupMessagesBefore(ctx, sqlc.GroupMessagesBeforeParams{ChannelID: channel, Anchor: cursor.ID, RowLimit: n})
		for _, r := range found {
			rows = append(rows, sqlc.GroupMessageRow(r))
		}
	case CursorAfter:
		var found []sqlc.GroupMessagesAfterRow
		found, err = s.Q.GroupMessagesAfter(ctx, sqlc.GroupMessagesAfterParams{ChannelID: channel, Anchor: cursor.ID, RowLimit: n})
		for _, r := range found {
			rows = append(rows, sqlc.GroupMessageRow(r))
		}
	default:
		var found []sqlc.GroupMessagesLatestRow
		found, err = s.Q.GroupMessagesLatest(ctx, sqlc.GroupMessagesLatestParams{ChannelID: channel, Limit: n})
		for _, r := range found {
			rows = append(rows, sqlc.GroupMessageRow(r))
		}
	}
	if err != nil {
		return nil, fmt.Errorf("messages: %w", err)
	}
	out := make([]Message, len(rows))
	for i, r := range rows {
		out[i] = messageFromRow(r)
	}
	if cursor.Kind != CursorAfter {
		slices.Reverse(out)
	}
	return out, nil
}

// Message is one message in a channel, or nil.
func (s *Store) Message(ctx context.Context, id, channel uuid.UUID) (*Message, error) {
	return s.message(ctx, id, &channel)
}

func (s *Store) message(ctx context.Context, id uuid.UUID, channel *uuid.UUID) (*Message, error) {
	r, err := s.Q.GroupMessage(ctx, sqlc.GroupMessageParams{ID: id, ChannelID: channel})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	if err != nil {
		return nil, fmt.Errorf("message: %w", err)
	}
	m := messageFromRow(r)
	return &m, nil
}

// PostMessage inserts a message. A retry with the same author and nonce returns the first one.
func (s *Store) PostMessage(ctx context.Context, m Message, nonce *string) (Message, error) {
	params := sqlc.InsertGroupMessageParams{
		ID: m.ID, ChannelID: m.ChannelID, Body: m.Body, Mentions: m.Mentions, MentionsAgent: m.MentionsAgent,
		ClientNonce: nonce, CreatedAt: m.CreatedAt, AuthorKind: "user", ReplyTo: m.ReplyTo,
		Components: componentsJSON(m.Components),
	}
	if params.Mentions == nil {
		params.Mentions = []uuid.UUID{}
	}
	if m.Author != nil {
		id := m.Author.ID
		params.AuthorID = &id
	}
	if m.FromAgent {
		params.AuthorKind = "agent"
	}
	if m.Spoiler != nil {
		params.SpoilerEnding = m.Spoiler.Ending
		if p := m.Spoiler.Episode; p != nil {
			season, episode := int32(p.Season), int32(p.Episode) //nolint:gosec // episode numbers are small
			params.SpoilerSeason, params.SpoilerEpisode = &season, &episode
		}
	}
	id, err := s.Q.InsertGroupMessage(ctx, params)
	if db.IsNoRows(err) {
		// A retry: answer with the message the first attempt stored, in this channel only.
		first, ferr := s.Q.GroupMessageByNonce(ctx, sqlc.GroupMessageByNonceParams{
			AuthorID: params.AuthorID, ClientNonce: nonce, ChannelID: m.ChannelID,
		})
		if db.IsNoRows(ferr) {
			return Message{}, apperr.Conflict("That message was not saved.")
		}
		if ferr != nil {
			return Message{}, fmt.Errorf("message by nonce: %w", ferr)
		}
		id, err = first, nil
	}
	if err != nil {
		return Message{}, fmt.Errorf("insert message: %w", err)
	}
	stored, err := s.message(ctx, id, nil)
	if err != nil {
		return Message{}, err
	}
	if stored == nil {
		return m, nil
	}
	return *stored, nil
}

// EditMessage replaces a live message's body and mentions.
func (s *Store) EditMessage(ctx context.Context, id uuid.UUID, body string, mentions []uuid.UUID, agent bool, now time.Time) error {
	if err := s.Q.EditGroupMessage(ctx, sqlc.EditGroupMessageParams{
		ID: id, Body: body, Mentions: mentions, MentionsAgent: agent, EditedAt: &now,
	}); err != nil {
		return fmt.Errorf("edit message: %w", err)
	}
	return nil
}

// DeleteMessage empties the body and mentions and stamps deletedAt.
func (s *Store) DeleteMessage(ctx context.Context, id uuid.UUID, now time.Time) error {
	if err := s.Q.DeleteGroupMessage(ctx, sqlc.DeleteGroupMessageParams{ID: id, DeletedAt: &now}); err != nil {
		return fmt.Errorf("delete message: %w", err)
	}
	return nil
}

// MarkRead moves the viewer's read point forward to that message; never backward.
func (s *Store) MarkRead(ctx context.Context, user, channel, message uuid.UUID) error {
	if err := s.Q.MarkGroupChannelRead(ctx, sqlc.MarkGroupChannelReadParams{UserID: user, MessageID: message, ChannelID: channel}); err != nil {
		return fmt.Errorf("mark read: %w", err)
	}
	return nil
}

// MARK: Shelf

// ShelfItems are a shelf's titles by position, with the viewer's own status for each.
func (s *Store) ShelfItems(ctx context.Context, channel, viewer uuid.UUID) ([]ShelfItem, error) {
	rows, err := s.Q.GroupShelfItems(ctx, sqlc.GroupShelfItemsParams{Viewer: viewer, ChannelID: channel})
	if err != nil {
		return nil, fmt.Errorf("shelf items: %w", err)
	}
	out := make([]ShelfItem, len(rows))
	for i, r := range rows {
		item := ShelfItem{
			TitleID: r.TitleID, AddedBy: optionalUser(r.AddedBy, r.Handle, r.DisplayName, r.AvatarVersion),
			AddedAt: r.AddedAt, Position: int(r.Position),
		}
		if r.MyStatus != nil {
			item.MyStatus = coreStatus(*r.MyStatus)
		}
		out[i] = item
	}
	return out, nil
}

// AddShelfItem adds a title at the end. False when it was already there.
func (s *Store) AddShelfItem(ctx context.Context, channel, title, by uuid.UUID, now time.Time) (bool, error) {
	_, err := s.Q.AddGroupShelfItem(ctx, sqlc.AddGroupShelfItemParams{ChannelID: channel, TitleID: title, AddedBy: by, Now: now})
	if db.IsNoRows(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("add shelf item: %w", err)
	}
	return true, nil
}

// RemoveShelfItem removes a title. False when it was not there.
func (s *Store) RemoveShelfItem(ctx context.Context, channel, title uuid.UUID) (bool, error) {
	_, err := s.Q.RemoveGroupShelfItem(ctx, sqlc.RemoveGroupShelfItemParams{ChannelID: channel, TitleID: title})
	if db.IsNoRows(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("remove shelf item: %w", err)
	}
	return true, nil
}

// MARK: Watch parties

// LatestParty is the channel's newest party, ended or not.
func (s *Store) LatestParty(ctx context.Context, channel uuid.UUID) (*WatchParty, error) {
	r, err := s.Q.LatestWatchParty(ctx, channel)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	if err != nil {
		return nil, fmt.Errorf("latest party: %w", err)
	}
	ready, err := s.Q.WatchPartyReady(ctx, r.ID)
	if err != nil {
		return nil, fmt.Errorf("party ready: %w", err)
	}
	party := &WatchParty{
		ID: r.ID, ChannelID: r.ChannelID, TitleID: r.TitleID,
		CreatedBy: optionalUser(r.CreatedBy, r.Handle, r.DisplayName, r.AvatarVersion),
		StartsAt:  r.StartsAt, EndedAt: r.EndedAt, CreatedAt: r.CreatedAt, Ready: make([]User, len(ready)),
	}
	if r.Season != nil && r.Episode != nil {
		party.Episode = &EpisodePoint{Season: int(*r.Season), Episode: int(*r.Episode)}
	}
	for i, u := range ready {
		party.Ready[i] = user(u.UserID, u.Handle, u.DisplayName, u.AvatarVersion)
	}
	return party, nil
}

// CreateParty opens a party; 409 when the channel already has an open one.
func (s *Store) CreateParty(ctx context.Context, p WatchParty) error {
	params := sqlc.InsertWatchPartyParams{ID: p.ID, ChannelID: p.ChannelID, TitleID: p.TitleID, CreatedAt: p.CreatedAt}
	if p.Episode != nil {
		season, episode := int32(p.Episode.Season), int32(p.Episode.Episode) //nolint:gosec // episode numbers are small
		params.Season, params.Episode = &season, &episode
	}
	if p.CreatedBy != nil {
		id := p.CreatedBy.ID
		params.CreatedBy = &id
	}
	if err := s.Q.InsertWatchParty(ctx, params); err != nil {
		if isUniqueViolation(err) {
			return apperr.Conflict("A watch party is already open here.")
		}
		return fmt.Errorf("insert party: %w", err)
	}
	return nil
}

// SetReady marks or unmarks a member ready.
func (s *Store) SetReady(ctx context.Context, session, user uuid.UUID, ready bool) error {
	var err error
	if ready {
		err = s.Q.SetWatchReady(ctx, sqlc.SetWatchReadyParams{SessionID: session, UserID: user})
	} else {
		err = s.Q.UnsetWatchReady(ctx, sqlc.UnsetWatchReadyParams{SessionID: session, UserID: user})
	}
	if err != nil {
		return fmt.Errorf("set ready: %w", err)
	}
	return nil
}

// StartParty sets the countdown's end.
func (s *Store) StartParty(ctx context.Context, session uuid.UUID, startsAt time.Time) error {
	if err := s.Q.StartWatchParty(ctx, sqlc.StartWatchPartyParams{ID: session, StartsAt: &startsAt}); err != nil {
		return fmt.Errorf("start party: %w", err)
	}
	return nil
}

// EndParty ends an open party.
func (s *Store) EndParty(ctx context.Context, session uuid.UUID, now time.Time) error {
	if err := s.Q.EndWatchParty(ctx, sqlc.EndWatchPartyParams{ID: session, EndedAt: &now}); err != nil {
		return fmt.Errorf("end party: %w", err)
	}
	return nil
}
