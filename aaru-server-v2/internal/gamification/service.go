package gamification

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/reqctx"
	"cmp"
	"context"
	"fmt"
	"log/slog"
	"slices"
	"time"

	"github.com/google/uuid"
)

// FriendReversalWindow is how young a friendship must be to lose its points when it ends: a friendship ended sooner than this loses its points.
const FriendReversalWindow = 7 * 24 * time.Hour

// ListenWindow is how recent a listen must be to earn points: only listens from the last day earn points.
const ListenWindow = 24 * time.Hour

// Service is points, streaks, badges and the board (GamificationService). The after-write hooks
// are best effort: a failure logs and leaves the user dirty for the Worker, and never fails the
// write that triggered it. The caller's zone is reqctx.TimeZone(ctx).
type Service struct {
	// DB is the pool (or a transaction).
	DB  sqlc.DBTX
	Now func() time.Time
	Log *slog.Logger
}

// New builds the service over a pool.
func New(db sqlc.DBTX, log *slog.Logger) *Service {
	return &Service{DB: db, Now: time.Now, Log: log}
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

func (s *Service) store() store {
	return newStore(s.DB)
}

func (s *Service) zone(ctx context.Context, user uuid.UUID) (*time.Location, error) {
	return s.store().zone(ctx, user, reqctx.TimeZone(ctx))
}

// MARK: Hooks

// AfterWrite runs after a live library or list write commits: streak bonuses, then badges.
// actionID is the journal row (nil for a write that has none).
func (s *Service) AfterWrite(ctx context.Context, user uuid.UUID, actionID *uuid.UUID) {
	s.bestEffort(ctx, user, func() error {
		if err := s.StreakBonuses(ctx, user); err != nil {
			return err
		}
		_, err := s.Evaluate(ctx, user, OriginLive, actionID)
		return err
	})
}

// AfterUndo takes back tiers the undone action earned and no longer holds, then evaluates as usual.
func (s *Service) AfterUndo(ctx context.Context, user, undone, undoAction uuid.UUID) {
	s.bestEffort(ctx, user, func() error {
		if err := s.TakeBack(ctx, user, undone); err != nil {
			return err
		}
		_, err := s.Evaluate(ctx, user, OriginLive, &undoAction)
		return err
	})
}

// FriendAdded is a mutual friendship beginning: both earn, once per pair.
func (s *Service) FriendAdded(ctx context.Context, first, second uuid.UUID) {
	root := FriendRoot(first, second)
	for _, user := range []uuid.UUID{first, second} {
		s.bestEffort(ctx, user, func() error {
			if err := s.award(ctx, user, []Award{NewAward(KindFriendAdded, root, nil, nil)}); err != nil {
				return err
			}
			_, err := s.Evaluate(ctx, user, OriginLive, nil)
			return err
		})
	}
}

// FriendEnded is a friendship ending. Under seven days old, both lose its points; re-friending
// earns nothing.
func (s *Service) FriendEnded(ctx context.Context, first, second uuid.UUID, since time.Time) {
	if s.now().Sub(since) >= FriendReversalWindow {
		return
	}
	root := FriendRoot(first, second)
	for _, user := range []uuid.UUID{first, second} {
		s.bestEffort(ctx, user, func() error {
			_, err := s.store().revoke(ctx, []string{root}, user)
			return err
		})
	}
}

// RoomAttended is the user being in a watch party, once per party.
func (s *Service) RoomAttended(ctx context.Context, user, session uuid.UUID) {
	s.bestEffort(ctx, user, func() error {
		if err := s.award(ctx, user, []Award{NewAward(KindRoomAttended, RoomRoot(session), nil, nil)}); err != nil {
			return err
		}
		_, err := s.Evaluate(ctx, user, OriginLive, nil)
		return err
	})
}

// ListensKept is listens a scrobbler just sent. Only listens from the last day earn points (a
// backlog is not a day's listening); every listen counts toward music badges. Listens keep no streak.
func (s *Service) ListensKept(ctx context.Context, user uuid.UUID, listens []Listen) {
	if len(listens) == 0 {
		return
	}
	now := s.now()
	var awards []Award
	for _, l := range listens {
		if now.Sub(l.ListenedAt) <= ListenWindow {
			awards = append(awards, NewAward(KindListen, ListenRoot(l), nil, nil))
		}
	}
	s.bestEffort(ctx, user, func() error {
		if len(awards) > 0 {
			if err := s.award(ctx, user, awards); err != nil {
				return err
			}
		}
		_, err := s.Evaluate(ctx, user, OriginLive, nil)
		return err
	})
}

// BatchApplied is an import or an approved plan applied: no points per item, and its badges
// arrive as one summary. Undoing that action takes back what it earned.
func (s *Service) BatchApplied(ctx context.Context, user uuid.UUID, actionID *uuid.UUID, firstImport bool) {
	err := func() error {
		if firstImport {
			if err := s.award(ctx, user, []Award{NewAward(KindImportFirst, ImportFirstRoot, nil, nil)}); err != nil {
				return err
			}
		}
		_, err := s.Evaluate(ctx, user, OriginBatch, actionID)
		return err
	}()
	if err != nil {
		s.log().Error("Gamification step failed", "error", err.Error())
		_ = s.store().markDirty(ctx, user, OriginBatch)
	}
}

// ListensImported is a listening-history import applied (MUS-004): no points, however recent its
// listens. Its music badges arrive as one summary.
func (s *Service) ListensImported(ctx context.Context, user uuid.UUID) {
	s.bestEffort(ctx, user, func() error {
		_, err := s.Evaluate(ctx, user, OriginBatch, nil)
		return err
	})
}

// ListensUndone is a listening-history import undone: the music tiers whose rule no longer holds
// go. The import is not a journaled action, so its tiers are found by rule rather than by action.
func (s *Service) ListensUndone(ctx context.Context, user uuid.UUID) {
	s.bestEffort(ctx, user, func() error {
		st := s.store()
		facts, err := st.facts(ctx, user)
		if err != nil {
			return err
		}
		earned, err := st.badges(ctx, user)
		if err != nil {
			return err
		}
		var lost []uuid.UUID
		for _, b := range earned {
			if d, ok := ByID[b.Badge]; ok && d.Family == FamilyMusic && b.Tier > d.Tier(facts) {
				lost = append(lost, b.ID)
			}
		}
		return st.deleteBadges(ctx, lost, user)
	})
}

func (s *Service) award(ctx context.Context, user uuid.UUID, awards []Award) error {
	st := s.store()
	loc, err := st.zone(ctx, user, reqctx.TimeZone(ctx))
	if err != nil {
		return err
	}
	_, err = st.award(ctx, awards, user, loc, s.now())
	return err
}

func (s *Service) bestEffort(ctx context.Context, user uuid.UUID, body func() error) {
	if err := body(); err != nil {
		s.log().Error("Gamification step failed", "error", err.Error())
		_ = s.store().markDirty(ctx, user, OriginLive)
	}
}

// MARK: Evaluation

// Evaluate awards every tier the facts reach and the user lacks. A user never evaluated before
// gets their live streak days backfilled first, and the result is one summary, not a toast each.
func (s *Service) Evaluate(ctx context.Context, user uuid.UUID, origin Origin, actionID *uuid.UUID) ([]EarnedBadge, error) {
	started := s.now()
	st := s.store()
	fresh, err := st.isFresh(ctx, user)
	if err != nil {
		return nil, err
	}
	if fresh {
		loc, err := st.zone(ctx, user, reqctx.TimeZone(ctx))
		if err != nil {
			return nil, err
		}
		if err := st.q.GamificationBackfillStreakDays(ctx, sqlc.GamificationBackfillStreakDaysParams{UserID: user, Zone: loc.String()}); err != nil {
			return nil, fmt.Errorf("backfill streak days: %w", err)
		}
		origin = OriginBackfill
	}
	facts, err := st.facts(ctx, user)
	if err != nil {
		return nil, err
	}
	earned, err := st.badges(ctx, user)
	if err != nil {
		return nil, err
	}
	have := map[string]bool{}
	for _, b := range earned {
		have[fmt.Sprintf("%s#%d", b.Badge, b.Tier)] = true
	}
	var due []TierDue
	for _, d := range Catalog {
		reached := d.Tier(facts)
		for tier := 1; tier <= reached; tier++ {
			if !have[fmt.Sprintf("%s#%d", d.ID, tier)] {
				due = append(due, TierDue{Badge: d.ID, Tier: tier})
			}
		}
	}
	if origin == OriginBackfill {
		actionID = nil
	}
	inserted, err := st.insertBadges(ctx, due, user, origin, actionID, started)
	if err != nil {
		return nil, err
	}
	if err := st.q.GamificationFinishEvaluation(ctx, sqlc.GamificationFinishEvaluationParams{
		UserID: user, StartedAt: timestamptz(started),
	}); err != nil {
		return nil, fmt.Errorf("finish evaluation: %w", err)
	}
	return inserted, nil
}

// TakeBack deletes the tiers the undone action earned whose rule no longer holds.
func (s *Service) TakeBack(ctx context.Context, user, undone uuid.UUID) error {
	st := s.store()
	all, err := st.badges(ctx, user)
	if err != nil {
		return err
	}
	var earned []EarnedBadge
	for _, b := range all {
		if b.ActionID != nil && *b.ActionID == undone {
			earned = append(earned, b)
		}
	}
	if len(earned) == 0 {
		return nil
	}
	facts, err := st.facts(ctx, user)
	if err != nil {
		return err
	}
	var lost []uuid.UUID
	for _, b := range earned {
		if d, ok := ByID[b.Badge]; ok && b.Tier > d.Tier(facts) {
			lost = append(lost, b.ID)
		}
	}
	return st.deleteBadges(ctx, lost, user)
}

// StreakBonuses awards the milestone bonuses for the live run: once per run per milestone.
func (s *Service) StreakBonuses(ctx context.Context, user uuid.UUID) error {
	st := s.store()
	loc, err := st.zone(ctx, user, reqctx.TimeZone(ctx))
	if err != nil {
		return err
	}
	days, err := st.streakDays(ctx, user)
	if err != nil {
		return err
	}
	summary := core.SummarizeStreak(days, core.LocalDate(s.now(), loc))
	if summary.RunStart == nil {
		return nil
	}
	var awards []Award
	for _, m := range core.StreakMilestones {
		if summary.Current >= m {
			awards = append(awards, Award{
				Kind: KindStreakMilestone, Root: StreakRoot(*summary.RunStart, m), Points: StreakBonus(m),
			})
		}
	}
	if len(awards) == 0 {
		return nil
	}
	_, err = st.award(ctx, awards, user, loc, s.now())
	return err
}

// MARK: Reads

// DayState is one of the last seven local dates and whether it was a streak day.
type DayState struct {
	Date   string
	Active bool
}

// Progress is the user's level, streak and what is new, as `/v1/me/progress` returns it.
type Progress struct {
	Total       int
	Level       int
	LevelStart  int
	NextLevelAt int
	WeekPoints  int
	Streak      core.StreakSummary
	// Days are the last seven local dates, oldest first.
	Days []DayState
	// Unseen badges, newest first.
	Unseen []EarnedBadge
}

// Progress reads `/v1/me/progress`.
func (s *Service) Progress(ctx context.Context, user uuid.UUID) (Progress, error) {
	st := s.store()
	loc, err := st.zone(ctx, user, reqctx.TimeZone(ctx))
	if err != nil {
		return Progress{}, err
	}
	today := core.LocalDate(s.now(), loc)
	total, err := st.totalPoints(ctx, user)
	if err != nil {
		return Progress{}, err
	}
	level := LevelFor(total)
	week := WeekContaining(today)
	days, err := st.streakDays(ctx, user)
	if err != nil {
		return Progress{}, err
	}
	dates := map[string]bool{}
	for _, d := range days {
		dates[d.Date] = true
	}
	var lastSeven []DayState
	for back := 6; back >= 0; back-- {
		if date, ok := core.AddingDays(-back, today); ok {
			lastSeven = append(lastSeven, DayState{Date: date, Active: dates[date]})
		}
	}
	earned, err := st.badges(ctx, user)
	if err != nil {
		return Progress{}, err
	}
	var unseen []EarnedBadge
	for _, b := range earned {
		if b.SeenAt == nil {
			unseen = append(unseen, b)
		}
	}
	// Swift's sort is not stable; ties keep the store's order here.
	slices.SortStableFunc(unseen, func(a, b EarnedBadge) int { return b.AwardedAt.Compare(a.AwardedAt) })
	weekPoints, err := st.boardPoints(ctx, user, week.From, week.Until)
	if err != nil {
		return Progress{}, err
	}
	return Progress{
		Total: total, Level: level, LevelStart: LevelThreshold(level), NextLevelAt: LevelThreshold(level + 1),
		WeekPoints: weekPoints, Streak: core.SummarizeStreak(days, today), Days: lastSeven, Unseen: unseen,
	}, nil
}

// BadgeStatus is one catalog badge with what the user has of it.
type BadgeStatus struct {
	Definition Definition
	// Earned tiers, lowest first.
	Earned []EarnedBadge
	Value  int
}

// Tier is the highest tier earned; 0 for none.
func (b BadgeStatus) Tier() int {
	tier := 0
	for _, e := range b.Earned {
		tier = max(tier, e.Tier)
	}
	return tier
}

// Target is the next threshold; false once every tier is earned.
func (b BadgeStatus) Target() (int, bool) {
	tier := b.Tier()
	if tier < b.Definition.MaxTier() {
		return b.Definition.Thresholds[tier], true
	}
	return 0, false
}

// Badges is every catalog badge with the user's tiers and progress.
func (s *Service) Badges(ctx context.Context, user uuid.UUID) ([]BadgeStatus, error) {
	st := s.store()
	facts, err := st.facts(ctx, user)
	if err != nil {
		return nil, err
	}
	all, err := st.badges(ctx, user)
	if err != nil {
		return nil, err
	}
	byBadge := map[string][]EarnedBadge{}
	for _, b := range all {
		byBadge[b.Badge] = append(byBadge[b.Badge], b)
	}
	out := make([]BadgeStatus, len(Catalog))
	for i, d := range Catalog {
		earned := byBadge[d.ID]
		slices.SortStableFunc(earned, func(a, b EarnedBadge) int { return cmp.Compare(a.Tier, b.Tier) })
		out[i] = BadgeStatus{Definition: d, Earned: earned, Value: d.Value(facts)}
	}
	return out, nil
}

// MarkSeen marks unseen awards seen.
func (s *Service) MarkSeen(ctx context.Context, ids []uuid.UUID, user uuid.UUID) error {
	if len(ids) == 0 {
		return nil
	}
	now := s.now()
	if err := s.store().q.GamificationMarkBadgesSeen(ctx, sqlc.GamificationMarkBadgesSeenParams{SeenAt: &now, UserID: user, Ids: ids}); err != nil {
		return fmt.Errorf("mark badges seen: %w", err)
	}
	return nil
}

// FriendAchievements is what a friend may see: level and non-private earned badges, one per
// badge (its highest tier), newest first. ok is false when they turned the switch off.
// The friend profile (FriendService) calls it.
func (s *Service) FriendAchievements(ctx context.Context, friend uuid.UUID) (level int, badges []EarnedBadge, ok bool, err error) {
	settings, err := s.settings(ctx, friend)
	if err != nil {
		return 0, nil, false, err
	}
	if !settings.ShowAchievementsToFriends {
		return 0, nil, false, nil
	}
	st := s.store()
	total, err := st.totalPoints(ctx, friend)
	if err != nil {
		return 0, nil, false, err
	}
	all, err := st.badges(ctx, friend)
	if err != nil {
		return 0, nil, false, err
	}
	top := map[string]EarnedBadge{}
	var order []string
	for _, b := range all {
		d, known := ByID[b.Badge]
		if !known || d.Private {
			continue
		}
		current, seen := top[b.Badge]
		if !seen {
			order = append(order, b.Badge)
		}
		if !seen || b.Tier > current.Tier {
			top[b.Badge] = b
		}
	}
	for _, id := range order {
		badges = append(badges, top[id])
	}
	slices.SortStableFunc(badges, func(a, b EarnedBadge) int { return b.AwardedAt.Compare(a.AwardedAt) })
	return LevelFor(total), badges, true, nil
}

type socialSettings struct {
	ShowAchievementsToFriends bool
	LeaderboardOptIn          bool
}

func (s *Service) settings(ctx context.Context, user uuid.UUID) (socialSettings, error) {
	rows, err := s.store().q.GamificationSocialSettings(ctx, user)
	if err != nil {
		return socialSettings{}, fmt.Errorf("social settings: %w", err)
	}
	if len(rows) == 0 {
		return socialSettings{ShowAchievementsToFriends: true}, nil
	}
	return socialSettings{ShowAchievementsToFriends: rows[0].ShowAchievementsToFriends, LeaderboardOptIn: rows[0].LeaderboardOptIn}, nil
}

// SocialUser is a person on the board (Swift's SocialUser).
type SocialUser struct {
	ID            uuid.UUID
	Handle        string
	DisplayName   *string
	AvatarVersion *int64
}

// LeaderboardEntry is one row of the board.
type LeaderboardEntry struct {
	User   SocialUser
	Points int
	Rank   int
}

// Leaderboard is one weekly board (GAM-005).
type Leaderboard struct {
	Week    string
	From    string
	Until   string
	OptedIn bool
	Entries []LeaderboardEntry
}

// ErrBadWeek is a week that does not look like `2026-W43`.
var ErrBadWeek = apperr.New(400, "bad_request", "Weeks look like 2026-W43.")

// Leaderboard is the viewer's weekly friends board; requested is an ISO week name or nil for
// this week in the viewer's zone.
func (s *Service) Leaderboard(ctx context.Context, viewer uuid.UUID, requested *string) (Leaderboard, error) {
	st := s.store()
	loc, err := st.zone(ctx, viewer, reqctx.TimeZone(ctx))
	if err != nil {
		return Leaderboard{}, err
	}
	week := WeekContaining(core.LocalDate(s.now(), loc))
	if requested != nil {
		named, ok := WeekNamed(*requested)
		if !ok {
			return Leaderboard{}, ErrBadWeek
		}
		week = named
	}
	settings, err := s.settings(ctx, viewer)
	if err != nil {
		return Leaderboard{}, err
	}
	var rows []sqlc.GamificationLeaderboardRow
	if settings.LeaderboardOptIn {
		rows, err = st.q.GamificationLeaderboard(ctx, sqlc.GamificationLeaderboardParams{
			FromDate: week.From, UntilDate: week.Until, OffBoard: OffBoardKinds(), Viewer: viewer,
		})
		if err != nil {
			return Leaderboard{}, fmt.Errorf("leaderboard: %w", err)
		}
	}
	friends, err := st.q.GamificationFriends(ctx, viewer)
	if err != nil {
		return Leaderboard{}, fmt.Errorf("friends: %w", err)
	}
	byID := map[uuid.UUID]SocialUser{}
	for _, f := range friends {
		byID[f.UserID] = SocialUser{ID: f.UserID, Handle: f.Handle, DisplayName: f.DisplayName, AvatarVersion: f.AvatarVersion}
	}
	own, err := st.q.GamificationSocialUser(ctx, viewer)
	if err != nil {
		return Leaderboard{}, fmt.Errorf("social user: %w", err)
	}
	if len(own) > 0 {
		byID[own[0].UserID] = SocialUser{ID: own[0].UserID, Handle: own[0].Handle, DisplayName: own[0].DisplayName, AvatarVersion: own[0].AvatarVersion}
	}
	var standings []LeaderboardEntry
	for _, row := range rows {
		if user, ok := byID[row.UserID]; ok {
			standings = append(standings, LeaderboardEntry{User: user, Points: int(row.Points)})
		}
	}
	slices.SortStableFunc(standings, func(a, b LeaderboardEntry) int {
		if a.Points == b.Points {
			return cmp.Compare(a.User.Handle, b.User.Handle)
		}
		return cmp.Compare(b.Points, a.Points)
	})
	for i := range standings {
		if i > 0 && standings[i-1].Points == standings[i].Points {
			standings[i].Rank = standings[i-1].Rank
		} else {
			standings[i].Rank = i + 1
		}
	}
	return Leaderboard{Week: week.Name, From: week.From, Until: week.Until, OptedIn: settings.LeaderboardOptIn, Entries: standings}, nil
}

// Events is a page of the ledger, newest first, before an instant (nil: from the newest).
func (s *Service) Events(ctx context.Context, user uuid.UUID, before *time.Time, limit int) ([]PointsEvent, error) {
	params := sqlc.GamificationEventsParams{UserID: user, RowLimit: int32(limit)} //nolint:gosec // 1…100
	if before != nil {
		params.Before = timestamptz(*before)
	}
	rows, err := s.store().q.GamificationEvents(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("points events: %w", err)
	}
	out := make([]PointsEvent, len(rows))
	for i, r := range rows {
		out[i] = PointsEvent{
			ID: r.ID, Kind: r.Kind, Points: int(r.Points), TitleID: r.TitleID, LocalDate: r.LocalDate,
			CreatedAt: r.CreatedAt, IsRevocation: r.IsRevocation,
		}
	}
	return out, nil
}

// TotalPoints is the cached total.
func (s *Service) TotalPoints(ctx context.Context, user uuid.UUID) (int, error) {
	return s.store().totalPoints(ctx, user)
}

// RebuildTotal sums the ledger and stores it as the cached total.
func (s *Service) RebuildTotal(ctx context.Context, user uuid.UUID) (int, error) {
	return s.store().rebuildTotal(ctx, user)
}

// StreakDays are the user's streak days, oldest first.
func (s *Service) StreakDays(ctx context.Context, user uuid.UUID) ([]core.StreakDay, error) {
	return s.store().streakDays(ctx, user)
}

// TimeZone is the request's zone when it sent one (stored for later), else the stored zone,
// else UTC.
func (s *Service) TimeZone(ctx context.Context, user uuid.UUID) (*time.Location, error) {
	return s.zone(ctx, user)
}

// MarkStreakDay writes today's streak day for a live write that happened outside the library
// transaction.
func (s *Service) MarkStreakDay(ctx context.Context, user uuid.UUID) error {
	st := s.store()
	loc, err := st.zone(ctx, user, reqctx.TimeZone(ctx))
	if err != nil {
		return err
	}
	return st.markStreakDay(ctx, user, loc, s.now())
}

// EarnedBadges are the user's earned tiers, oldest first.
func (s *Service) EarnedBadges(ctx context.Context, user uuid.UUID) ([]EarnedBadge, error) {
	return s.store().badges(ctx, user)
}

// InsertBadges inserts tiers not yet earned and returns the rows it wrote.
func (s *Service) InsertBadges(ctx context.Context, due []TierDue, user uuid.UUID, origin Origin, actionID *uuid.UUID) ([]EarnedBadge, error) {
	return s.store().insertBadges(ctx, due, user, origin, actionID, s.now())
}

// Facts reads the badge facts for one user.
func (s *Service) Facts(ctx context.Context, user uuid.UUID) (Facts, error) {
	return s.store().facts(ctx, user)
}

// IsFresh is true for a user never evaluated: the next evaluation is the first run over an
// existing library.
func (s *Service) IsFresh(ctx context.Context, user uuid.UUID) (bool, error) {
	return s.store().isFresh(ctx, user)
}

// MarkDirty leaves the user for the Worker.
func (s *Service) MarkDirty(ctx context.Context, user uuid.UUID, origin Origin) error {
	return s.store().markDirty(ctx, user, origin)
}
