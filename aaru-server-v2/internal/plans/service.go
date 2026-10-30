package plans

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/telemetry"
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// Lifetime is how long a plan nobody decided on waits before it expires.
	Lifetime = 24 * time.Hour
	// MaxPendingPerToken is how many plans one token may have waiting at once.
	MaxPendingPerToken = 20
	// listLimit is how many plans a list returns.
	listLimit = 50
)

// Service is the plan rules (PlanService).
type Service struct {
	pool *pgxpool.Pool
	q    *sqlc.Queries
	// Library works out and applies the writes.
	Library *library.Service
	// Push tells the user a plan is waiting; nil sends nothing.
	Push *push.UserPush
	// Gamification hears about an approved plan as a batch; nil skips it.
	Gamification *gamification.Service
	Log          *slog.Logger
	// Now defaults to time.Now.
	Now func() time.Time
}

// NewService builds the plan service over a pool.
func NewService(pool *pgxpool.Pool, lib *library.Service, userPush *push.UserPush, game *gamification.Service, log *slog.Logger) *Service {
	return &Service{pool: pool, q: sqlc.New(pool), Library: lib, Push: userPush, Gamification: game, Log: log, Now: time.Now}
}

func (s *Service) now() time.Time {
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

// Propose works out changes against the library as it is and stores them as a pending plan.
// Changes that would do nothing are dropped; when none are left it is a ToolError.
func (s *Service) Propose(ctx context.Context, changes []AgentChange, caller auth.AgentCaller) (Plan, error) {
	now := s.now()
	tokenID := caller.Token.ID
	pending, err := s.q.PlanPendingCount(ctx, sqlc.PlanPendingCountParams{AgentTokenID: &tokenID, Now: now})
	if err != nil {
		return Plan{}, err
	}
	if pending >= MaxPendingPerToken {
		return Plan{}, &ToolError{Message: strconv.Itoa(int(pending)) +
			" changes from this connection are already waiting for the user. Ask them to review those in Aaru first."}
	}
	writes, err := s.prepare(ctx, changes, caller)
	if err != nil {
		return Plan{}, err
	}
	if len(writes) == 0 {
		return Plan{}, &ToolError{Message: "Nothing to change: the library already looks like that."}
	}
	var touched, absent []uuid.UUID
	ops := make([]library.Op, len(writes))
	lines := make([]Change, len(writes))
	for i, w := range writes {
		if w.Adds {
			absent = append(absent, w.Title.ID)
		} else {
			touched = append(touched, w.ItemID)
		}
		ops[i] = w.Op
		lines[i] = changeLine(w)
	}
	versions, err := itemVersions(ctx, s.q, touched, caller.UserID, false)
	if err != nil {
		return Plan{}, err
	}
	if absent == nil {
		absent = []uuid.UUID{}
	}
	plan := Plan{
		ID: uuid.New(), AgentTokenID: &tokenID, AgentName: caller.Token.Name, Status: StatusPending,
		Summary: Summary(writes), Changes: lines, Counts: CountsOf(writes), Op: library.Batch(ops...),
		Basis: Basis{Items: versions, AbsentTitles: absent}, CreatedAt: now, ExpiresAt: now.Add(Lifetime),
	}
	if err := s.create(ctx, plan, caller.UserID); err != nil {
		return Plan{}, err
	}
	s.Push.Send(ctx, Message(plan), caller.UserID)
	return plan, nil
}

// Plans are the user's plans, newest first: only pending ones (expired ones excluded), or all.
func (s *Service) Plans(ctx context.Context, user uuid.UUID, pendingOnly bool) ([]Plan, error) {
	return s.list(ctx, user, pendingOnly, s.now(), listLimit)
}

func noSuchPlan() *apperr.Error { return apperr.NotFound("No such plan.") }

func alreadyDecidedError() *apperr.Error {
	return apperr.New(http.StatusConflict, "plan_decided", "This request was already decided.")
}

// Plan is one of the user's plans; 404 when they have no such plan.
func (s *Service) Plan(ctx context.Context, id, user uuid.UUID) (Plan, error) {
	p, err := s.find(ctx, id, user)
	if err != nil {
		return Plan{}, err
	}
	if p == nil {
		return Plan{}, noSuchPlan()
	}
	return *p, nil
}

// Approve applies a pending plan as one action journaled as the agent that asked. A plan whose
// library moved is stale, one past its expiry expired; both write nothing (409).
func (s *Service) Approve(ctx context.Context, id, user uuid.UUID) (Plan, library.ActionRecord, error) {
	d, err := s.approveTx(ctx, id, user, s.now())
	if err != nil {
		return Plan{}, library.ActionRecord{}, err
	}
	if d == nil {
		return Plan{}, library.ActionRecord{}, noSuchPlan()
	}
	switch d.kind {
	case decidedApplied:
		telemetry.Capture(telemetry.AgentPlanDecided, user, map[string]string{"decision": "approved"})
		// Episodes for added shows, as a tap's add fetches them. Best effort.
		for _, c := range d.plan.Changes {
			if c.Type == core.MediaShow && c.LibraryItemID == nil && s.Library != nil && s.Library.Catalog != nil {
				if _, err := s.Library.Catalog.Service.Detail(ctx, c.TitleID); err != nil {
					s.log().DebugContext(ctx, "episodes after plan", "title", c.TitleID, "error", err)
				}
			}
		}
		if s.Gamification != nil {
			actionID := d.action.ID
			s.Gamification.BatchApplied(ctx, user, &actionID, false)
		}
		return d.plan, d.action, nil
	case decidedStale:
		return Plan{}, library.ActionRecord{}, apperr.New(http.StatusConflict, "plan_stale",
			"Your library changed since "+d.plan.AgentName+" asked, so nothing was applied. Ask it again.")
	case decidedExpired:
		return Plan{}, library.ActionRecord{}, apperr.New(http.StatusConflict, "plan_expired", "This request expired. Ask again.")
	default:
		return Plan{}, library.ActionRecord{}, alreadyDecidedError()
	}
}

// Deny decides a pending plan without writing anything.
func (s *Service) Deny(ctx context.Context, id, user uuid.UUID) (Plan, error) {
	d, err := s.denyTx(ctx, id, user, s.now())
	if err != nil {
		return Plan{}, err
	}
	if d == nil {
		return Plan{}, noSuchPlan()
	}
	if d.kind != decidedDenied {
		return Plan{}, alreadyDecidedError()
	}
	telemetry.Capture(telemetry.AgentPlanDecided, user, map[string]string{"decision": "denied"})
	return d.plan, nil
}

// MARK: Working out a plan

// prepare is each change as the write a tap would make now. Changes that would do nothing are dropped.
func (s *Service) prepare(ctx context.Context, changes []AgentChange, caller auth.AgentCaller) ([]library.PreparedWrite, error) {
	user := caller.UserID
	agent := library.AgentCaller(caller.Token)
	lib := s.Library
	var writes []library.PreparedWrite
	adding := map[uuid.UUID]bool{}
	for _, c := range changes {
		switch c.Kind {
		case ChangeAdd:
			title, err := lib.Catalog.Resolver().Resolve(ctx, c.Ref, nil)
			if err != nil {
				return nil, err
			}
			existing, err := lib.ItemForTitle(ctx, user, title.ID)
			if err != nil {
				return nil, err
			}
			if existing != nil || adding[title.ID] {
				continue
			}
			adding[title.ID] = true
			writes = append(writes, lib.PrepareAdd(title, c.Status, agent))
		case ChangeUpdate:
			current, err := lib.Entry(ctx, c.Item, user)
			if err != nil {
				return nil, err
			}
			w, err := lib.PreparePatch(current, c.Patch, agent)
			if err != nil {
				return nil, err
			}
			if w != nil {
				writes = append(writes, *w)
			}
		case ChangeEpisodes:
			show, err := lib.ShowContext(ctx, c.Item, user)
			if err != nil {
				return nil, err
			}
			if c.Season != nil {
				w, err := lib.PrepareSeason(ctx, show, *c.Season)
				if err != nil {
					return nil, err
				}
				writes = append(writes, w)
			} else {
				w, err := lib.PrepareEpisodes(ctx, show, c.Keys, c.Watched)
				if err != nil {
					return nil, err
				}
				if w != nil {
					writes = append(writes, *w)
				}
			}
		case ChangeRemove:
			current, err := lib.Entry(ctx, c.Item, user)
			if err != nil {
				return nil, err
			}
			writes = append(writes, lib.PrepareDelete(current))
		}
	}
	return writes, nil
}

func changeLine(w library.PreparedWrite) Change {
	c := Change{Text: w.Summary, TitleID: w.Title.ID, Title: w.Title.Title, Type: w.Title.Type, PosterURL: w.Title.PosterURL}
	if !w.Adds {
		id := w.ItemID
		c.LibraryItemID = &id
	}
	return c
}

// CountsOf counts the writes by kind.
func CountsOf(writes []library.PreparedWrite) Counts {
	var c Counts
	for _, w := range writes {
		switch w.Kind {
		case "add":
			c.Adds++
		case "remove":
			c.Removes++
		case "episode", "season":
			c.Episodes += w.Episodes
		default:
			c.Updates++
		}
	}
	return c
}

// Summary is "Mark 18 episodes of Andor watched", or "Add 2 titles, mark 6 episodes" for several.
func Summary(writes []library.PreparedWrite) string {
	if len(writes) == 1 {
		return writes[0].Summary
	}
	c := CountsOf(writes)
	var parts []string
	if c.Adds > 0 {
		parts = append(parts, "add "+plural(c.Adds, "title"))
	}
	if c.Episodes > 0 {
		parts = append(parts, "mark "+plural(c.Episodes, "episode"))
	}
	if c.Updates > 0 {
		parts = append(parts, "update "+plural(c.Updates, "item"))
	}
	if c.Removes > 0 {
		parts = append(parts, "remove "+plural(c.Removes, "title"))
	}
	joined := strings.Join(parts, ", ")
	if joined == "" {
		return ""
	}
	return strings.ToUpper(joined[:1]) + joined[1:]
}

func plural(n int, noun string) string {
	if n == 1 {
		return "1 " + noun
	}
	return strconv.Itoa(n) + " " + noun + "s"
}

// Message is the push that tells the user a plan is waiting.
func Message(p Plan) push.Message {
	return push.Message{
		Title:   p.AgentName + " wants to change your library",
		Body:    p.Summary,
		Payload: map[string]string{"planId": strings.ToLower(p.ID.String())},
	}
}
