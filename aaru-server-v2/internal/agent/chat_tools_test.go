package agent_test

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/social"
	"aaru-go-api/internal/sports"
	"aaru-go-api/internal/stats"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type chatToolsFixture struct {
	*writeFixture
	sports *sports.Service
}

func newChatToolsFixture(t *testing.T) *chatToolsFixture {
	t.Helper()
	f := newWriteFixture(t)
	f.tools.Quota = f.realQuota()
	return &chatToolsFixture{
		writeFixture: f,
		sports:       sports.NewService(&sports.Store{Q: sqlc.New(f.pool), Pool: f.pool}, nil),
	}
}

func (f *chatToolsFixture) deps(withSports bool) agent.ChatDeps {
	d := agent.ChatDeps{
		Q: sqlc.New(f.pool), Tools: f.tools, Stats: stats.New(f.pool), Lists: f.lib.Store,
		Favorites: social.New(social.NewStore(f.pool), nil, f.kit, f.lib, nil, ""),
		Music:     &music.Service{Store: music.NewStore(f.pool)},
	}
	if withSports {
		d.Sports = f.sports
	}
	return d
}

func (f *chatToolsFixture) chatTools(user uuid.UUID) *agent.ChatTools {
	return agent.NewChatTools(f.deps(true), user)
}

func run(t *testing.T, c *agent.ChatTools, name string, input any) (string, bool) {
	t.Helper()
	raw, err := json.Marshal(input)
	require.NoError(t, err)
	return c.Run(t.Context(), name, raw)
}

// seed gives a user a marker's worth of data in every area the read tools cover.
func (f *chatToolsFixture) seed(user uuid.UUID, marker string, finished int) {
	f.t.Helper()
	by := library.ChatCaller
	fin := core.StatusFinished
	var first core.Title
	for i := range finished {
		e, err := f.lib.Add(f.ctx, *movieRef(fmt.Sprintf("%s%d", marker, i)), &fin, user, by)
		require.NoError(f.t, err)
		if i == 0 {
			first = e.Title
		}
	}
	_, err := f.tools.Library.Store.Apply(f.ctx, library.InsertList(library.ListSnapshot{
		ID: uuid.New(), Name: "List " + marker, CreatedAt: f.now, Members: []uuid.UUID{first.ID},
	}), user, by, "list", "made a list")
	require.NoError(f.t, err)
	_, err = social.New(social.NewStore(f.pool), nil, f.kit, f.lib, nil, "").
		ReplaceFavorites(f.ctx, social.FavoriteFilm, []core.MediaRef{{TitleID: &first.ID, Type: core.MediaMovie}}, user)
	require.NoError(f.t, err)
	_, err = music.NewStore(f.pool).Insert(f.ctx, []music.NewListen{{
		ListenedAt: time.Now().Add(-time.Hour), Artist: "Artist " + marker, Track: "Track " + marker,
	}}, user, nil)
	require.NoError(f.t, err)
	_, err = f.sports.Store.Follow(f.ctx, sports.Entity{Kind: sports.KindTeam, ID: marker, Name: "Team " + marker, Sport: "Soccer"},
		user, 20, f.now)
	require.NoError(f.t, err)
}

func TestReadsOnlyCaller(t *testing.T) {
	f := newChatToolsFixture(t)
	a, b := f.user, f.newUser()
	f.seed(a, "AAA", 2)
	f.seed(b, "BBB", 3)

	cases := []struct{ tool, markerA, markerB string }{
		{"read_my_library", "Title AAA0", "Title BBB0"},
		{"read_my_stats", "2 movies finished", "3 movies finished"},
		{"read_my_lists", "List AAA", "List BBB"},
		{"read_my_favorites", "Title AAA0", "Title BBB0"},
		{"read_my_listens", "Artist AAA", "Artist BBB"},
		{"read_my_sports", "Team AAA", "Team BBB"},
	}
	for _, c := range cases {
		t.Run(c.tool, func(t *testing.T) {
			out, isErr := run(t, f.chatTools(a), c.tool, map[string]any{})
			require.False(t, isErr, out)
			assert.Contains(t, out, c.markerA)
			assert.NotContains(t, out, c.markerB)
			out, isErr = run(t, f.chatTools(b), c.tool, map[string]any{})
			require.False(t, isErr, out)
			assert.Contains(t, out, c.markerB)
			assert.NotContains(t, out, c.markerA)
		})
	}
}

func TestReadsEmpty(t *testing.T) {
	f := newChatToolsFixture(t)
	for _, tool := range []string{"read_my_library", "read_my_lists", "read_my_favorites", "read_my_listens", "read_my_sports"} {
		out, isErr := run(t, f.chatTools(f.user), tool, map[string]any{})
		assert.False(t, isErr, tool)
		assert.NotEmpty(t, out, tool)
	}
}

func TestSportsAbsentWhenOff(t *testing.T) {
	f := newChatToolsFixture(t)
	names := func(c *agent.ChatTools) []string {
		var out []string
		for _, d := range c.Definitions() {
			out = append(out, d.Name)
		}
		return out
	}
	assert.Contains(t, names(f.chatTools(f.user)), "read_my_sports")
	off := agent.NewChatTools(f.deps(false), f.user)
	assert.NotContains(t, names(off), "read_my_sports")
	out, isErr := run(t, off, "read_my_sports", map[string]any{})
	assert.True(t, isErr, out)
	assert.ElementsMatch(t, []string{
		"search_titles", "title_details", "list_airs", "read_my_library", "show_titles", "read_my_stats",
		"read_my_lists", "read_my_favorites", "read_my_listens", "apply_library_patch",
	}, names(off))
}

func (f *chatToolsFixture) withHit(tmdb string) {
	year := 1999
	f.fake.hits = append(f.fake.hits, catalog.Hit{
		Type: core.MediaMovie, Title: "Hit " + tmdb, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb},
	})
}

func TestPatchToolApplies(t *testing.T) {
	f := newChatToolsFixture(t)
	f.withHit("900")
	c := f.chatTools(f.user)
	out, isErr := run(t, c, "search_titles", map[string]any{"query": "hit", "kind": "movie"})
	require.False(t, isErr, out)
	require.Contains(t, out, "r1: Hit 900")

	out, isErr = run(t, c, "apply_library_patch", map[string]any{"changes": []any{
		map[string]any{"op": "add", "ref": "r1", "status": "wishlist"},
	}})
	require.False(t, isErr, out)
	assert.Contains(t, out, "Applied")
	assert.Nil(t, c.Plan())
	require.NotNil(t, c.ActionID())
	assert.Contains(t, c.ActionSummary(), "Title 900")
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
}

func TestPatchToolUpdatesByLibraryRef(t *testing.T) {
	f := newChatToolsFixture(t)
	f.seed(f.user, "UPD", 1)
	c := f.chatTools(f.user)
	out, _ := run(t, c, "read_my_library", map[string]any{})
	require.Contains(t, out, "r1: Title UPD0")
	out, isErr := run(t, c, "apply_library_patch", map[string]any{"changes": []any{
		map[string]any{"op": "update", "ref": "r1", "status": "dropped"},
	}})
	require.False(t, isErr, out)
	assert.Contains(t, out, "Applied")
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1 AND status = 'dropped'`, f.user))
}

// A turn offers one Undo, so it applies one tap: "mark A, B and C" must not become three writes.
func TestPatchToolAppliesOnePerTurn(t *testing.T) {
	add := func(ref string) map[string]any {
		return map[string]any{"changes": []any{map[string]any{"op": "add", "ref": ref, "status": "wishlist"}}}
	}
	setup := func(t *testing.T) (*chatToolsFixture, *agent.ChatTools) {
		t.Helper()
		f := newChatToolsFixture(t)
		f.withHit("905")
		f.withHit("906")
		f.withHit("907")
		c := f.chatTools(f.user)
		out, isErr := run(t, c, "search_titles", map[string]any{"query": "hit", "kind": "movie"})
		require.False(t, isErr, out)
		out, isErr = run(t, c, "apply_library_patch", add("r1"))
		require.False(t, isErr, out)
		require.Contains(t, out, "Applied")
		return f, c
	}
	actions := func(f *chatToolsFixture) []uuid.UUID {
		list, err := f.lib.Store.Actions(f.ctx, f.user, 10)
		require.NoError(f.t, err)
		ids := make([]uuid.UUID, len(list))
		for i, a := range list {
			ids[i] = a.ID
		}
		return ids
	}

	t.Run("a second single change is refused", func(t *testing.T) {
		f, c := setup(t)
		first := *c.ActionID()
		summary := c.ActionSummary()
		assert.Contains(t, summary, "Title 905")

		out, isErr := run(t, c, "apply_library_patch", add("r2"))

		assert.True(t, isErr, "a tool error the model can read")
		assert.Contains(t, out, "Nothing was changed")
		assert.Contains(t, out, "one apply_library_patch call")
		assert.NotContains(t, out, "Applied")
		assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
		assert.Equal(t, []uuid.UUID{first}, actions(f), "one write in the journal")
		assert.Equal(t, first, *c.ActionID(), "the Undo stays the first write's")
		assert.Equal(t, summary, c.ActionSummary())
		assert.Nil(t, c.Plan())
	})

	t.Run("a larger change still becomes a plan", func(t *testing.T) {
		f, c := setup(t)
		first := *c.ActionID()

		out, isErr := run(t, c, "apply_library_patch", map[string]any{"changes": []any{
			map[string]any{"op": "add", "ref": "r2"}, map[string]any{"op": "add", "ref": "r3"},
		}})

		require.False(t, isErr, out)
		assert.Contains(t, out, "needs approval in Aaru")
		require.NotNil(t, c.Plan())
		assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
		assert.Equal(t, first, *c.ActionID())
	})

	t.Run("a next turn applies again", func(t *testing.T) {
		f, c := setup(t)
		next := f.chatTools(f.user)
		out, isErr := run(t, next, "search_titles", map[string]any{"query": "hit", "kind": "movie"})
		require.False(t, isErr, out)
		out, isErr = run(t, next, "apply_library_patch", add("r2"))
		require.False(t, isErr, out)
		assert.Contains(t, out, "Applied")
		assert.NotEqual(t, *c.ActionID(), *next.ActionID())
	})
}

func TestPatchToolPlan(t *testing.T) {
	f := newChatToolsFixture(t)
	f.withHit("901")
	f.withHit("902")
	c := f.chatTools(f.user)
	run(t, c, "search_titles", map[string]any{"query": "hit", "kind": "movie"})
	out, isErr := run(t, c, "apply_library_patch", map[string]any{"changes": []any{
		map[string]any{"op": "add", "ref": "r1"}, map[string]any{"op": "add", "ref": "r2"},
	}})
	require.False(t, isErr, out)
	assert.Contains(t, out, "needs approval in Aaru")
	assert.NotContains(t, strings.ToLower(out), "applied")
	require.NotNil(t, c.Plan())
	assert.Nil(t, c.ActionID())
	assert.Zero(t, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
}

func TestPatchToolQuota(t *testing.T) {
	f := newChatToolsFixture(t)
	f.withHit("903")
	f.withHit("904")
	for i := range imports.FreeCapturesPerMonth {
		_, err := f.tools.ChatPatch(f.ctx, bulk("8"+strconv.Itoa(i)), f.user)
		require.NoError(t, err)
	}
	c := f.chatTools(f.user)
	run(t, c, "search_titles", map[string]any{"query": "hit", "kind": "movie"})
	out, isErr := run(t, c, "apply_library_patch", map[string]any{"changes": []any{
		map[string]any{"op": "add", "ref": "r1"}, map[string]any{"op": "add", "ref": "r2"},
	}})
	assert.True(t, isErr)
	assert.Contains(t, out, "captures")
	assert.Nil(t, c.Plan())
}

func TestPatchToolUnknownRef(t *testing.T) {
	f := newChatToolsFixture(t)
	c := f.chatTools(f.user)
	out, isErr := run(t, c, "apply_library_patch", map[string]any{"changes": []any{
		map[string]any{"op": "add", "ref": "r9"},
	}})
	assert.True(t, isErr)
	assert.Contains(t, out, "ref")
}

// From Home there is no hint: title_details is what the spoiler guard has to go on.
func TestTitleDetailsGuardsSpoilersInAChat(t *testing.T) {
	f := newChatToolsFixture(t)
	f.withHit("920")
	details := func(user uuid.UUID) string {
		c := f.chatTools(user)
		out, isErr := run(t, c, "search_titles", map[string]any{"query": "hit", "kind": "movie"})
		require.False(t, isErr, out)
		out, isErr = run(t, c, "title_details", map[string]any{"ref": "r1"})
		require.False(t, isErr, out)
		return out
	}
	stranger := f.newUser()
	finished := core.StatusFinished
	_, err := f.lib.Add(f.ctx, *movieRef("920"), &finished, stranger, library.ChatCaller)
	require.NoError(t, err)

	assert.Contains(t, details(stranger), "They have finished it. Do not reveal anything that happens after that point.")
	got := details(f.user)
	assert.Contains(t, got, "They have not started it.", "the caller's progress, not another user's")
	assert.NotContains(t, got, "finished")

	// A show, up to an episode.
	aired := f.now.Add(-48 * time.Hour)
	f.fake.episodes["921"] = catalog.Episodes{Episodes: []catalog.Episode{
		{Season: 1, Episode: 1, AirsAt: &aired}, {Season: 1, Episode: 2, AirsAt: &aired},
	}}
	show := &core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "921"}}
	inProgress := core.StatusInProgress
	entry, err := f.lib.Add(f.ctx, *show, &inProgress, f.user, library.ChatCaller)
	require.NoError(t, err)
	_, err = f.tools.ChatPatch(f.ctx, patch(agent.PatchChange{
		Op: "episodes", LibraryItemID: ptrTo(entry.Item.ID.String()), Watched: ptrTo(true),
		Episodes: []agent.EpisodeInput{{Season: 1, Episode: 2}},
	}), f.user)
	require.NoError(t, err)
	c := f.chatTools(f.user)
	_, isErr := run(t, c, "read_my_library", map[string]any{})
	require.False(t, isErr)
	out, isErr := run(t, c, "title_details", map[string]any{"ref": "r1"})
	require.False(t, isErr, out)
	assert.Contains(t, out, "They have watched up to season 1 episode 2.")
}

func ptrTo[T any](v T) *T { return &v }

// `@aaru` reads the same title and says nothing of anyone's progress: byte for byte what it said.
func TestTitleDetailsUnchangedInAGroup(t *testing.T) {
	f := newChatToolsFixture(t)
	f.withHit("922")
	finished := core.StatusFinished
	_, err := f.lib.Add(f.ctx, *movieRef("922"), &finished, f.user, library.ChatCaller)
	require.NoError(t, err)
	tools := agent.NewGroupToolsForTest(f.kit, f.lib, f.user)
	out, isErr := tools.Run(t.Context(), "search_titles", json.RawMessage(`{"query":"hit","kind":"movie"}`))
	require.False(t, isErr, out)

	out, isErr = tools.Run(t.Context(), "title_details", json.RawMessage(`{"ref":"r1"}`))

	require.False(t, isErr, out)
	assert.Equal(t, "Title 922 (2001) [movie]", out)
	for _, d := range agent.GroupToolDefinitions {
		if d.Name == "title_details" {
			assert.Equal(t, "Facts about one title: year, synopsis, network, and for shows the status and episode count.", d.Description)
		}
	}
}

func TestGroupToolsStillReadOnly(t *testing.T) {
	var names []string
	for _, d := range agent.GroupToolDefinitions {
		names = append(names, d.Name)
	}
	assert.ElementsMatch(t, []string{"search_titles", "title_details", "list_airs", "read_my_library", "show_titles"}, names)
	assert.NotContains(t, names, "apply_library_patch")
}
