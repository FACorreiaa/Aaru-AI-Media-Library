package agent_test

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/plans"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeCatalog hydrates any tmdb id: movies by that id, and the shows stubbed in episodes.
type fakeCatalog struct {
	mu       sync.Mutex
	episodes map[string]catalog.Episodes
}

func (f *fakeCatalog) Search(context.Context, string, core.MediaType) ([]catalog.Hit, error) {
	return nil, nil
}

func (f *fakeCatalog) SearchMulti(context.Context, string) ([]catalog.Hit, error) { return nil, nil }

func (f *fakeCatalog) Hydrate(_ context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*catalog.Record, error) {
	year := 2001
	r := catalog.Record{Hit: catalog.Hit{Type: mediaType, Title: "Title " + ids.TMDB, Year: &year, IDs: ids}}
	if mediaType == core.MediaShow {
		status := catalog.TitleStatus("ended")
		r.Status = &status
	}
	return &r, nil
}

func (f *fakeCatalog) Episodes(_ context.Context, ids core.ExternalIDs) (*catalog.Episodes, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if e, ok := f.episodes[ids.TMDB]; ok {
		return &e, nil
	}
	return nil, nil // not known
}

func (f *fakeCatalog) Tracks(context.Context, core.ExternalIDs) ([]catalog.AlbumTrack, error) {
	return nil, nil
}

type writeFixture struct {
	*chatFixture
	fake  *fakeCatalog
	kit   *catalog.Kit
	lib   *library.Service
	plans *plans.Service
	tools *agent.Tools
}

func newWriteFixture(t *testing.T) *writeFixture {
	t.Helper()
	f := newChatFixture(t)
	fake := &fakeCatalog{episodes: map[string]catalog.Episodes{}}
	providers := catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}
	log := slog.Default()
	kit := catalog.NewKit(f.pool, providers, log)
	lib := library.NewService(library.NewStore(f.pool), kit, nil, log)
	planService := plans.NewService(f.pool, lib, nil, nil, log)
	return &writeFixture{
		chatFixture: f, fake: fake, kit: kit, lib: lib, plans: planService,
		tools: &agent.Tools{Catalog: kit, Library: lib, Plans: planService},
	}
}

// realQuota is the capture quota as the server wires it.
func (f *writeFixture) realQuota() func(context.Context, uuid.UUID) error {
	service := imports.NewService(imports.NewStore(f.pool), f.kit, f.lib.Store, nil, slog.Default())
	q := sqlc.New(f.pool)
	return func(ctx context.Context, user uuid.UUID) error { return service.CheckCaptureQuota(ctx, q, user) }
}

func movieRef(tmdb string) *core.MediaRef {
	return &core.MediaRef{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: tmdb}}
}

func addChange(tmdb string, status ...core.LibraryStatus) agent.PatchChange {
	c := agent.PatchChange{Op: "add", MediaRef: movieRef(tmdb)}
	if len(status) > 0 {
		c.Status = &status[0]
	}
	return c
}

func updateChange(item uuid.UUID, status core.LibraryStatus) agent.PatchChange {
	id := item.String()
	return agent.PatchChange{Op: "update", LibraryItemID: &id, Patch: &library.ItemPatch{Status: &status}}
}

func patch(changes ...agent.PatchChange) agent.PatchInput { return agent.PatchInput{Changes: changes} }

// bulk is two adds of titles nobody has yet, unique per name.
func bulk(name string) agent.PatchInput {
	return patch(addChange(name+"1", core.StatusInProgress), addChange(name+"2"))
}

func (f *writeFixture) byHand(item uuid.UUID) bool {
	f.t.Helper()
	var byHand bool
	require.NoError(f.t, f.pool.QueryRow(f.ctx, `SELECT status_by_hand FROM library_items WHERE id = $1`, item).Scan(&byHand))
	return byHand
}

func (f *writeFixture) status(item uuid.UUID) string {
	f.t.Helper()
	var status string
	require.NoError(f.t, f.pool.QueryRow(f.ctx, `SELECT status FROM library_items WHERE id = $1`, item).Scan(&status))
	return status
}

// wouldMerge is what an import saying the title is finished decides against the item as it is now.
func (f *writeFixture) wouldMerge(user, title uuid.UUID) imports.Decision {
	f.t.Helper()
	states, err := f.lib.Store.ImportStates(f.ctx, user, []uuid.UUID{title})
	require.NoError(f.t, err)
	state, ok := states[title]
	require.True(f.t, ok)
	finished := core.StatusFinished
	return imports.Decide(imports.Row{Type: core.MediaMovie, Title: "Any", Status: &finished, Lists: []string{}}, &state)
}

func TestChatPatchOneItem(t *testing.T) {
	f := newWriteFixture(t)
	res, err := f.tools.ChatPatch(f.ctx, patch(addChange("100", core.StatusInProgress)), f.user)
	require.NoError(t, err)
	assert.True(t, res.Applied)
	assert.Nil(t, res.Plan)
	require.NotNil(t, res.Item)
	require.NotNil(t, res.ActionID)
	item := res.Item.Item.ID
	assert.True(t, f.byHand(item))

	var actor, summary string
	var token *uuid.UUID
	require.NoError(t, f.pool.QueryRow(f.ctx, `SELECT actor, summary, agent_token_id FROM actions WHERE id = $1`, *res.ActionID).
		Scan(&actor, &summary, &token))
	assert.Equal(t, "agent", actor)
	assert.Equal(t, "Aaru: added Title 100 to Watching", summary)
	assert.Nil(t, token)

	_, err = f.lib.Undo(f.ctx, *res.ActionID, f.user)
	require.NoError(t, err)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM library_items WHERE id = $1`, item))
}

func TestChatPatchUpdateUndoes(t *testing.T) {
	f := newWriteFixture(t)
	added, err := f.tools.ChatPatch(f.ctx, patch(addChange("101", core.StatusInProgress)), f.user)
	require.NoError(t, err)
	item := added.Item.Item.ID

	res, err := f.tools.ChatPatch(f.ctx, patch(updateChange(item, core.StatusFinished)), f.user)
	require.NoError(t, err)
	require.NotNil(t, res.ActionID)
	assert.NotEqual(t, *added.ActionID, *res.ActionID)
	assert.Equal(t, "finished", f.status(item))

	_, err = f.lib.Undo(f.ctx, *res.ActionID, f.user)
	require.NoError(t, err)
	assert.Equal(t, "in_progress", f.status(item))
}

// A change that writes nothing has no action to offer. The item's older one is not Aaru's to undo.
func TestChatPatchNothingWrittenHasNoAction(t *testing.T) {
	f := newWriteFixture(t)
	added, err := f.tools.ChatPatch(f.ctx, patch(addChange("102", core.StatusInProgress)), f.user)
	require.NoError(t, err)
	item := added.Item.Item.ID

	again, err := f.tools.ChatPatch(f.ctx, patch(addChange("102", core.StatusInProgress)), f.user)
	require.NoError(t, err)
	assert.True(t, again.Applied)
	assert.Nil(t, again.ActionID)

	same, err := f.tools.ChatPatch(f.ctx, patch(updateChange(item, core.StatusInProgress)), f.user)
	require.NoError(t, err)
	assert.True(t, same.Applied)
	assert.Nil(t, same.ActionID)
}

func TestChatPatchWishlistNotByHand(t *testing.T) {
	f := newWriteFixture(t)
	for _, c := range []agent.PatchChange{addChange("103"), addChange("104", core.StatusWishlist)} {
		res, err := f.tools.ChatPatch(f.ctx, patch(c), f.user)
		require.NoError(t, err)
		assert.False(t, f.byHand(res.Item.Item.ID))
		assert.Equal(t, imports.OutcomeUpdate, f.wouldMerge(f.user, res.Item.Title.ID).Outcome)
	}
}

func TestChatPatchHoldsAgainstImport(t *testing.T) {
	f := newWriteFixture(t)
	added, err := f.tools.ChatPatch(f.ctx, patch(addChange("105", core.StatusInProgress)), f.user)
	require.NoError(t, err)
	moved, err := f.tools.ChatPatch(f.ctx, patch(updateChange(added.Item.Item.ID, core.StatusWishlist)), f.user)
	require.NoError(t, err)
	assert.True(t, f.byHand(moved.Item.Item.ID))
	assert.Equal(t, imports.OutcomeSkip, f.wouldMerge(f.user, moved.Item.Title.ID).Outcome)

	// The same move by an outside agent stays open to the import, so the check above tells them apart.
	external := f.externalCaller()
	theirs, err := f.tools.ApplyLibraryPatch(f.ctx, patch(addChange("106", core.StatusInProgress)), external)
	require.NoError(t, err)
	theirs, err = f.tools.ApplyLibraryPatch(f.ctx, patch(updateChange(theirs.Item.Item.ID, core.StatusWishlist)), external)
	require.NoError(t, err)
	merged := f.wouldMerge(f.user, theirs.Item.Title.ID)
	require.Equal(t, imports.OutcomeUpdate, merged.Outcome)
	assert.Equal(t, core.StatusFinished, merged.Fields.Status)
}

func TestChatPatchWholeShowWatchedByHand(t *testing.T) {
	f := newWriteFixture(t)
	airs := time.Now().Add(-400 * 24 * time.Hour)
	f.fake.episodes["107"] = catalog.Episodes{Episodes: []catalog.Episode{{Season: 1, Episode: 1, AirsAt: &airs}}}
	inProgress := core.StatusInProgress
	ref := core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "107"}}
	item, err := f.lib.Add(f.ctx, ref, &inProgress, f.user, library.AgentCaller(auth.AgentToken{ID: f.newToken(), Name: "Other"}))
	require.NoError(t, err)
	require.False(t, f.byHand(item.Item.ID))
	_, err = f.kit.Service.Detail(f.ctx, item.Title.ID)
	require.NoError(t, err)

	res, err := f.tools.ChatPatch(f.ctx, patch(updateChange(item.Item.ID, core.StatusFinished)), f.user)
	require.NoError(t, err)
	require.NotNil(t, res.ActionID)
	assert.Equal(t, "finished", f.status(item.Item.ID))
	assert.True(t, f.byHand(item.Item.ID))
}

// A chat tick earns what gamification gives any live write, with no scrobble bonus: it never reads
// the actor.
func TestChatPatchTickEarnsLikeAnyWrite(t *testing.T) {
	f := newWriteFixture(t)
	airs := time.Now().Add(-400 * 24 * time.Hour)
	f.fake.episodes["109"] = catalog.Episodes{Episodes: []catalog.Episode{{Season: 1, Episode: 1, AirsAt: &airs}}}
	ref := core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "109"}}
	added, err := f.tools.ChatPatch(f.ctx, patch(agent.PatchChange{Op: "add", MediaRef: &ref}), f.user)
	require.NoError(t, err)
	_, err = f.kit.Service.Detail(f.ctx, added.Item.Title.ID)
	require.NoError(t, err)

	id, watched := added.Item.Item.ID.String(), true
	res, err := f.tools.ChatPatch(f.ctx, patch(agent.PatchChange{
		Op: "episodes", LibraryItemID: &id, Episodes: []agent.EpisodeInput{{Season: 1, Episode: 1}}, Watched: &watched,
	}), f.user)
	require.NoError(t, err)
	require.NotNil(t, res.ActionID)
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM points_events WHERE user_id = $1 AND kind = 'episode' AND action_id = $2`, f.user, *res.ActionID))
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM points_events WHERE user_id = $1 AND kind = 'scrobble_bonus'`, f.user))
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM check_ins WHERE user_id = $1`, f.user))
}

func TestChatPatchBulkPlan(t *testing.T) {
	f := newWriteFixture(t)
	res, err := f.tools.ChatPatch(f.ctx, bulk("20"), f.user)
	require.NoError(t, err)
	assert.False(t, res.Applied)
	assert.Nil(t, res.Item)
	assert.Nil(t, res.ActionID)
	require.NotNil(t, res.Plan)
	assert.Equal(t, plans.StatusPending, res.Plan.Status)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))

	var token *uuid.UUID
	var name string
	var spends bool
	require.NoError(t, f.pool.QueryRow(f.ctx, `SELECT agent_token_id, agent_name, spends_capture FROM agent_plans WHERE id = $1`, res.Plan.ID).
		Scan(&token, &name, &spends))
	assert.Nil(t, token)
	assert.Equal(t, "Aaru", name)
	assert.True(t, spends)

	plan, action, err := f.plans.Approve(f.ctx, res.Plan.ID, f.user)
	require.NoError(t, err)
	assert.Equal(t, plans.StatusApplied, plan.Status)
	assert.Equal(t, library.ActorAgent, action.Actor)
	assert.Equal(t, "Aaru: add 2 titles", action.Summary)
	var actor string
	require.NoError(t, f.pool.QueryRow(f.ctx, `SELECT actor, agent_token_id FROM actions WHERE id = $1`, action.ID).Scan(&actor, &token))
	assert.Equal(t, "agent", actor)
	assert.Nil(t, token)

	// As one tap each: the status the user asked for holds; a wishlist add says nothing yet.
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1 AND status = 'in_progress' AND status_by_hand`, f.user))
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1 AND status = 'wishlist' AND NOT status_by_hand`, f.user))
}

func TestChatPatchRemovePlanNoSpend(t *testing.T) {
	f := newWriteFixture(t)
	added, err := f.tools.ChatPatch(f.ctx, patch(addChange("108")), f.user)
	require.NoError(t, err)
	id := added.Item.Item.ID.String()

	// Removing does not need a capture left, so nobody asks.
	f.tools.Quota = func(context.Context, uuid.UUID) error { return errors.New("quota was consulted") }
	res, err := f.tools.ChatPatch(f.ctx, patch(agent.PatchChange{Op: "remove", LibraryItemID: &id}), f.user)
	require.NoError(t, err)
	assert.False(t, res.Applied)
	require.NotNil(t, res.Plan)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM agent_plans WHERE id = $1 AND spends_capture`, res.Plan.ID))
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM agent_plans WHERE id = $1`, res.Plan.ID))
}

func TestChatPatchQuota(t *testing.T) {
	f := newWriteFixture(t)
	f.tools.Quota = f.realQuota()
	for i := range imports.FreeCapturesPerMonth {
		res, err := f.tools.ChatPatch(f.ctx, bulk("3"+strconv.Itoa(i)), f.user)
		require.NoError(t, err)
		require.NotNil(t, res.Plan)
	}
	plansBefore := f.count(`SELECT count(*)::int FROM agent_plans WHERE user_id = $1`, f.user)

	_, err := f.tools.ChatPatch(f.ctx, bulk("39"), f.user)
	require.ErrorIs(t, err, agent.ErrCaptureQuota)
	assert.Contains(t, err.Error(), "Aaru Plus lifts the limit")
	assert.NotContains(t, err.Error(), "402")
	assert.Equal(t, plansBefore, f.count(`SELECT count(*)::int FROM agent_plans WHERE user_id = $1`, f.user))

	one, err := f.tools.ChatPatch(f.ctx, patch(addChange("400", core.StatusInProgress)), f.user)
	require.NoError(t, err)
	assert.True(t, one.Applied)
	require.NotNil(t, one.ActionID)
}

// Spending is decided on what the plan would really do, so changes that do nothing do not count.
func TestChatPatchQuotaCountsRealAdds(t *testing.T) {
	f := newWriteFixture(t)
	for _, tmdb := range []string{"410", "411"} {
		_, err := f.tools.ChatPatch(f.ctx, patch(addChange(tmdb, core.StatusInProgress)), f.user)
		require.NoError(t, err)
	}
	f.tools.Quota = func(context.Context, uuid.UUID) error {
		return errors.New("quota was consulted")
	}

	// Both already there: nothing to do.
	_, err := f.tools.ChatPatch(f.ctx, patch(addChange("410"), addChange("411")), f.user)
	var toolErr *agent.ToolError
	require.ErrorAs(t, err, &toolErr)
	assert.NotErrorIs(t, err, agent.ErrCaptureQuota)

	// One already there: a plan with one add, which spends nothing.
	res, err := f.tools.ChatPatch(f.ctx, patch(addChange("410"), addChange("412")), f.user)
	require.NoError(t, err)
	require.NotNil(t, res.Plan)
	assert.Equal(t, 1, res.Plan.Counts.Adds)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM agent_plans WHERE id = $1 AND spends_capture`, res.Plan.ID))
}

// Parallel chats cannot pass the quota together (DB-004 for captures).
func TestChatPatchQuotaHoldsInParallel(t *testing.T) {
	f := newWriteFixture(t)
	f.tools.Quota = f.realQuota()
	for i := range imports.FreeCapturesPerMonth - 1 {
		_, err := f.tools.ChatPatch(f.ctx, bulk("5"+strconv.Itoa(i)), f.user)
		require.NoError(t, err)
	}
	const callers = 6
	errs := make([]error, callers)
	var wg sync.WaitGroup
	for i := range callers {
		wg.Go(func() {
			_, errs[i] = f.tools.ChatPatch(f.ctx, bulk(fmt.Sprintf("6%d", i)), f.user)
		})
	}
	wg.Wait()
	refused := 0
	for _, err := range errs {
		if err != nil {
			require.ErrorIs(t, err, agent.ErrCaptureQuota)
			refused++
		}
	}
	assert.Equal(t, callers-1, refused)
	assert.Equal(t, imports.FreeCapturesPerMonth, f.count(`SELECT count(*)::int FROM agent_plans WHERE user_id = $1 AND spends_capture`, f.user))
}

// A spending plan queues behind a capture counting the same quota (DB-004), and stores nothing while it does.
func TestChatPatchWaitsForCaptureLock(t *testing.T) {
	f := newWriteFixture(t)
	tx, err := f.pool.Begin(f.ctx)
	require.NoError(t, err)
	defer func() { require.NoError(t, tx.Rollback(f.ctx)) }()
	require.NoError(t, imports.NewStore(f.pool).LockUserCaptures(f.ctx, tx, f.user))

	// Not a spending plan: the lock is not in its way.
	one, err := f.tools.ChatPatch(f.ctx, patch(addChange("73")), f.user)
	require.NoError(t, err)
	id := one.Item.Item.ID.String()
	remove, err := f.tools.ChatPatch(f.ctx, patch(agent.PatchChange{Op: "remove", LibraryItemID: &id}), f.user)
	require.NoError(t, err)
	require.NotNil(t, remove.Plan)

	short, cancel := context.WithTimeout(f.ctx, time.Second)
	defer cancel()
	_, err = f.tools.ChatPatch(short, bulk("74"), f.user)
	require.ErrorIs(t, err, context.DeadlineExceeded)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM agent_plans WHERE user_id = $1 AND spends_capture`, f.user))
}

// A broken quota check is a failure, not an account over quota.
func TestChatPatchQuotaFailureIsNotQuota(t *testing.T) {
	f := newWriteFixture(t)
	broken := errors.New("database down")
	f.tools.Quota = func(context.Context, uuid.UUID) error { return broken }
	_, err := f.tools.ChatPatch(f.ctx, bulk("70"), f.user)
	require.ErrorIs(t, err, broken)
	assert.NotErrorIs(t, err, agent.ErrCaptureQuota)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM agent_plans WHERE user_id = $1`, f.user))
}

func TestChatPatchPendingLimit(t *testing.T) {
	f := newWriteFixture(t)
	insert := func(user uuid.UUID, token *uuid.UUID, name string) {
		f.exec(`INSERT INTO agent_plans (id, user_id, agent_token_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at)
			VALUES ($1, $2, $3, $4, 'pending', 's', '{"items":[]}', '{}', '{}', '{"items":{},"absentTitles":[]}', now(), now() + interval '1 hour')`,
			uuid.New(), user, token, name)
	}
	other := f.newUser()
	token := f.newToken()
	for range plans.MaxPendingPerToken - 1 {
		insert(f.user, nil, "Aaru")
		insert(other, nil, "Aaru")
		insert(f.user, &token, "Aaru")
	}
	res, err := f.tools.ChatPatch(f.ctx, bulk("80"), f.user)
	require.NoError(t, err, "only this user's own Aaru plans count")
	require.NotNil(t, res.Plan)

	_, err = f.tools.ChatPatch(f.ctx, bulk("81"), f.user)
	var toolErr *agent.ToolError
	require.ErrorAs(t, err, &toolErr)
	assert.Equal(t, "20 changes proposed in chats with Aaru are already waiting for the user. Ask them to review those in Aaru first.",
		toolErr.ToolMessage(), "a chat has no connection to speak of, and the limit spans all the user's chats")
}

func (f *writeFixture) newToken() uuid.UUID {
	f.t.Helper()
	id := uuid.New()
	f.exec(`INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes) VALUES ($1, $2, 'Claude', 'claude', $3, $4)`,
		id, f.user, id.String(), []string{"library:read", "library:write"})
	return id
}

func (f *writeFixture) externalCaller() auth.AgentCaller {
	return auth.AgentCaller{UserID: f.user, Token: auth.AgentToken{
		ID: f.newToken(), Name: "Claude", Kind: auth.TokenKind("claude"), Scopes: []auth.Scope{auth.ScopeLibraryRead, auth.ScopeLibraryWrite},
	}}
}

func TestExternalAgentUnchanged(t *testing.T) {
	f := newWriteFixture(t)
	f.tools.Quota = func(context.Context, uuid.UUID) error { return errors.New("quota was consulted") }
	caller := f.externalCaller()

	res, err := f.tools.ApplyLibraryPatch(f.ctx, patch(addChange("90", core.StatusInProgress)), caller)
	require.NoError(t, err)
	require.True(t, res.Applied)
	item := res.Item.Item.ID
	assert.False(t, f.byHand(item))

	res, err = f.tools.ApplyLibraryPatch(f.ctx, patch(updateChange(item, core.StatusWishlist)), caller)
	require.NoError(t, err)
	assert.False(t, f.byHand(item))
	assert.Equal(t, 2, f.count(`SELECT count(*)::int FROM actions WHERE user_id = $1 AND actor = 'external_agent' AND agent_token_id = $2`, f.user, caller.Token.ID))

	// A bulk add is a plan bound to the token, spends nothing, and approves as the token.
	res, err = f.tools.ApplyLibraryPatch(f.ctx, bulk("91"), caller)
	require.NoError(t, err)
	require.NotNil(t, res.Plan)
	require.NotNil(t, res.Plan.AgentTokenID)
	assert.Equal(t, caller.Token.ID, *res.Plan.AgentTokenID)
	assert.Equal(t, "Claude", res.Plan.AgentName)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM agent_plans WHERE id = $1 AND spends_capture`, res.Plan.ID))

	_, action, err := f.plans.Approve(f.ctx, res.Plan.ID, f.user)
	require.NoError(t, err)
	assert.Equal(t, library.ActorExternalAgent, action.Actor)
	assert.Equal(t, "Claude: add 2 titles", action.Summary)
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1 AND status_by_hand`, f.user))

	// A plan whose token was deleted is still an outside agent's.
	res, err = f.tools.ApplyLibraryPatch(f.ctx, bulk("92"), caller)
	require.NoError(t, err)
	f.exec(`UPDATE agent_plans SET agent_token_id = NULL WHERE id = $1`, res.Plan.ID)
	_, action, err = f.plans.Approve(f.ctx, res.Plan.ID, f.user)
	require.NoError(t, err)
	assert.Equal(t, library.ActorExternalAgent, action.Actor)
}
