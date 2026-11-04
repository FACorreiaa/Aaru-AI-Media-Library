package agent

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Chat turn states. Only an agent turn is ever TurnStreaming.
const (
	TurnStreaming = "streaming"
	TurnDone      = "done"
	TurnFailed    = "failed"
	TurnStopped   = "stopped"
)

// StaleTurnAfter is how long an agent turn may stream before BeginTurn counts its process as lost.
const StaleTurnAfter = 5 * time.Minute

// ErrChatBusy is BeginTurn on a chat whose agent turn is still streaming.
var ErrChatBusy = errors.New("chat is busy")

// ErrChatNotFound is a chat that is missing or another user's.
var ErrChatNotFound = errors.New("chat not found")

// Chat is one user's thread with Aaru.
type Chat struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Title     *string
	CreatedAt time.Time
	UpdatedAt time.Time
}

// ChatTurn is one user or Aaru entry in a chat.
type ChatTurn struct {
	ID         uuid.UUID
	ChatID     uuid.UUID
	Role       string
	Body       string
	Components json.RawMessage
	State      string
	CreatedAt  time.Time
}

// ChatWithTurns is a chat and its turns, oldest first.
type ChatWithTurns struct {
	Chat
	Turns []ChatTurn
}

// ChatStore is the data layer of chats (`chats`, `chat_turns`).
type ChatStore struct {
	Q *sqlc.Queries
}

// CreateChat starts an empty chat for the user.
func (s *ChatStore) CreateChat(ctx context.Context, user uuid.UUID) (uuid.UUID, error) {
	id := uuid.New()
	if err := s.Q.CreateChat(ctx, sqlc.CreateChatParams{ID: id, UserID: user}); err != nil {
		return uuid.Nil, fmt.Errorf("create chat: %w", err)
	}
	return id, nil
}

// Chat is the user's chat, or nil when it is missing or someone else's.
func (s *ChatStore) Chat(ctx context.Context, id, user uuid.UUID) (*Chat, error) {
	row, err := s.Q.GetChat(ctx, sqlc.GetChatParams{ID: id, UserID: user})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil is "not yours or not there", by design
	}
	if err != nil {
		return nil, fmt.Errorf("get chat: %w", err)
	}
	c := chatOf(row)
	return &c, nil
}

// BeginTurn stores the user's turn as done and Aaru's as streaming, in one statement. A turn that
// streamed past StaleTurnAfter is failed first; one still streaming is ErrChatBusy and nothing is
// stored. A chat that is not the user's is ErrChatNotFound.
func (s *ChatStore) BeginTurn(ctx context.Context, chat, user uuid.UUID, body string, now time.Time) (userTurn, agentTurn uuid.UUID, err error) {
	if err := s.Q.FailStaleChatTurns(ctx, sqlc.FailStaleChatTurnsParams{
		ChatID: chat, Cutoff: now.Add(-StaleTurnAfter), Now: now,
	}); err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("fail stale chat turns: %w", err)
	}
	userTurn, agentTurn = uuid.New(), uuid.New()
	stored, err := s.Q.BeginChatTurn(ctx, sqlc.BeginChatTurnParams{
		ChatID: chat, UserID: user, UserTurn: userTurn, AgentTurn: agentTurn, Body: body, Now: now,
	})
	if db.IsUniqueViolation(err, "chat_turns_one_streaming") {
		return uuid.Nil, uuid.Nil, ErrChatBusy
	}
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("begin chat turn: %w", err)
	}
	if stored == 0 {
		return uuid.Nil, uuid.Nil, ErrChatNotFound
	}
	return userTurn, agentTurn, nil
}

// FinishTurn settles a streaming agent turn. A turn that is no longer streaming (failed as stale,
// say) keeps its state: the late finish is dropped.
func (s *ChatStore) FinishTurn(ctx context.Context, turn uuid.UUID, state, body string, components json.RawMessage, now time.Time) error {
	if state == TurnStreaming {
		return fmt.Errorf("finish chat turn: %q is not a final state", state)
	}
	if _, err := s.Q.FinishChatTurn(ctx, sqlc.FinishChatTurnParams{
		ID: turn, State: state, Body: body, Components: components, Now: now,
	}); err != nil {
		return fmt.Errorf("finish chat turn: %w", err)
	}
	return nil
}

// SetTitle names a chat that has no name yet.
func (s *ChatStore) SetTitle(ctx context.Context, chat uuid.UUID, title string) error {
	if err := s.Q.SetChatTitle(ctx, sqlc.SetChatTitleParams{ID: chat, Title: title}); err != nil {
		return fmt.Errorf("set chat title: %w", err)
	}
	return nil
}

// RecentTurns is the chat's newest limit turns, oldest first.
func (s *ChatStore) RecentTurns(ctx context.Context, chat uuid.UUID, limit int) ([]ChatTurn, error) {
	rows, err := s.Q.RecentChatTurns(ctx, sqlc.RecentChatTurnsParams{ChatID: chat, Limit: int32(limit)}) //nolint:gosec // a small page size
	if err != nil {
		return nil, fmt.Errorf("recent chat turns: %w", err)
	}
	out := make([]ChatTurn, 0, len(rows))
	for _, r := range rows {
		out = append(out, ChatTurn{
			ID: r.ID, ChatID: r.ChatID, Role: r.Role, Body: r.Body, Components: r.Components,
			State: r.State, CreatedAt: r.CreatedAt.Time,
		})
	}
	return out, nil
}

// RepliesToday counts the UTC day's replies the 30-a-day cap covers: `@aaru` replies plus chat turns.
func (s *ChatStore) RepliesToday(ctx context.Context, user uuid.UUID, now time.Time) (int, error) {
	y, m, d := now.UTC().Date()
	n, err := s.Q.ChatRepliesToday(ctx, sqlc.ChatRepliesTodayParams{
		UserID: user, DayStart: time.Date(y, m, d, 0, 0, 0, 0, time.UTC),
	})
	if err != nil {
		return 0, fmt.Errorf("chat replies today: %w", err)
	}
	return int(n), nil
}

// DeleteAll removes every chat of the user, turns with them.
func (s *ChatStore) DeleteAll(ctx context.Context, user uuid.UUID) error {
	if err := s.Q.DeleteAllChats(ctx, user); err != nil {
		return fmt.Errorf("delete chats: %w", err)
	}
	return nil
}

// ForExport is all of the user's chats with their turns, oldest first.
func (s *ChatStore) ForExport(ctx context.Context, user uuid.UUID) ([]ChatWithTurns, error) {
	chats, err := s.Q.ChatsForExport(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("export chats: %w", err)
	}
	turns, err := s.Q.ChatTurnsForExport(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("export chat turns: %w", err)
	}
	out := make([]ChatWithTurns, 0, len(chats))
	at := make(map[uuid.UUID]int, len(chats))
	for _, c := range chats {
		at[c.ID] = len(out)
		out = append(out, ChatWithTurns{Chat: chatOf(c), Turns: []ChatTurn{}})
	}
	for _, t := range turns {
		if i, ok := at[t.ChatID]; ok {
			out[i].Turns = append(out[i].Turns, ChatTurn{
				ID: t.ID, ChatID: t.ChatID, Role: t.Role, Body: t.Body, Components: t.Components,
				State: t.State, CreatedAt: t.CreatedAt.Time,
			})
		}
	}
	return out, nil
}

func chatOf(c sqlc.Chat) Chat {
	return Chat{ID: c.ID, UserID: c.UserID, Title: c.Title, CreatedAt: c.CreatedAt.Time, UpdatedAt: c.UpdatedAt.Time}
}
