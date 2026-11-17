package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"log/slog"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// UserWorlds finds a user's Worlds by writing NodeKeys in SQL. This keeps the two the same: for
// each id a `titles` row can hold, a library title carrying only that id finds a World whose
// title carries it, and a look-alike id of another kind does not.
func TestUserWorldsKeysMatchNodeKeys(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	worlds := NewWorldService(&RelationService{Store: store, log: slog.Default()}, store, nil)
	user := uuid.New()
	_, err := store.pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)

	cases := []struct {
		name      string
		mediaType core.MediaType
		column    string
		node      RelatedNode
	}{
		{"anilist", core.MediaShow, "anilist", RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "11"}}},
		{"mal anime", core.MediaShow, "mal", RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{MAL: "12"}}},
		{"mal manga", core.MediaManga, "mal", RelatedNode{Type: core.MediaManga, IDs: core.ExternalIDs{MAL: "12"}}},
		{"tmdb film", core.MediaMovie, "tmdb", RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "13"}}},
		{"tmdb show", core.MediaShow, "tmdb", RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "13"}}},
		{"imdb", core.MediaMovie, "imdb", RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{IMDB: "tt14"}}},
		{"open library", core.MediaBook, "open_library", RelatedNode{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: "OL15W"}}},
		{"musicbrainz", core.MediaAlbum, "musicbrainz", RelatedNode{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: "mb-16"}}},
	}
	want := map[uuid.UUID]string{}
	for _, c := range cases {
		keys := NodeKeys(c.node)
		require.Len(t, keys, 1, c.name)
		node := c.node
		node.Title = c.name
		partner := RelatedNode{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: "OL-partner-" + c.name}, Title: "partner"}
		world := World{RootKey: keys[0], Name: c.name, Links: []GraphEdge{}, Titles: []WorldTitle{
			{RelatedNode: node, Key: keys[0], Keys: keys, Lane: LaneOf(node)},
			{RelatedNode: partner, Key: NodeKeys(partner)[0], Keys: NodeKeys(partner), Lane: LaneBook, LanePosition: 1},
		}}
		require.NoError(t, worlds.put(ctx, world), c.name)

		titleID := uuid.New()
		id := map[string]string{
			"anilist": c.node.IDs.AniList, "mal": c.node.IDs.MAL, "tmdb": c.node.IDs.TMDB, "imdb": c.node.IDs.IMDB,
			"open_library": c.node.IDs.OpenLibrary, "musicbrainz": c.node.IDs.MusicBrainz,
		}[c.column]
		_, err := store.pool.Exec(ctx, `INSERT INTO titles (id, type, title, `+c.column+`) VALUES ($1, $2, $3, $4)`,
			titleID, string(c.mediaType), c.name, id)
		require.NoError(t, err, c.name)
		_, err = store.pool.Exec(ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
			VALUES ($1, $2, $3, 'wishlist', now(), now())`, uuid.New(), user, titleID)
		require.NoError(t, err, c.name)
		want[titleID] = c.name
	}

	mine, err := worlds.Mine(ctx, user)
	require.NoError(t, err)
	got := map[uuid.UUID]string{}
	for _, w := range mine {
		got[w.TitleID] = w.Name
	}
	assert.Equal(t, want, got, "each library title finds the World of its own kind, and only that one")

	// A book whose Open Library id is also some film's TMDB id finds nothing.
	stray := uuid.New()
	_, err = store.pool.Exec(ctx, `INSERT INTO titles (id, type, title, tmdb) VALUES ($1, 'book', 'stray', '13')`, stray)
	require.NoError(t, err)
	_, err = store.pool.Exec(ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
		VALUES ($1, $2, $3, 'wishlist', now(), now())`, uuid.New(), user, stray)
	require.NoError(t, err)
	mine, err = worlds.Mine(ctx, user)
	require.NoError(t, err)
	assert.Len(t, mine, len(cases), "a TMDB id on a book names no film or show")
}

func TestWorldProgressCountsEverythingAndPicksWhereToGo(t *testing.T) {
	world := World{Titles: []WorldTitle{
		{Key: "b1", Lane: LaneBook},
		{Key: "b2", Lane: LaneBook, LanePosition: 1},
		{Key: "f1", Lane: LaneFilm},
		{Key: "f-side", Lane: LaneFilm, LanePosition: 1, Side: true},
		{Key: "f2", Lane: LaneFilm, LanePosition: 2},
		{Key: "s1", Lane: LaneShow},
	}}
	none := world.Progress(nil)
	assert.Equal(t, 6, none.Total, "side titles count")
	assert.Zero(t, none.Finished)
	assert.Equal(t, map[WorldLane]string{LaneBook: "b1", LaneFilm: "f1", LaneShow: "s1"}, none.Next)
	require.NotNil(t, none.StartHere)
	assert.Equal(t, "b1", *none.StartHere, "nothing started: the first lane")

	films := world.Progress(map[string]core.LibraryStatus{"f1": core.StatusFinished, "f-side": core.StatusFinished, "b1": core.StatusDropped})
	assert.Equal(t, 2, films.Finished, "a finished side title counts; a dropped one does not")
	assert.Equal(t, "f2", films.Next[LaneFilm], "a side title is never a lane's next")
	assert.Equal(t, "b2", films.Next[LaneBook], "a dropped title is passed over")
	assert.Equal(t, "f2", *films.StartHere, "the lane the user is furthest into")

	watching := world.Progress(map[string]core.LibraryStatus{"f1": core.StatusFinished, "s1": core.StatusInProgress})
	assert.Equal(t, "s1", *watching.StartHere, "a title in progress comes first")

	all := map[string]core.LibraryStatus{}
	for _, wt := range world.Titles {
		all[wt.Key] = core.StatusFinished
	}
	done := world.Progress(all)
	assert.Equal(t, 6, done.Finished)
	assert.Nil(t, done.StartHere)
	assert.Empty(t, done.Next)
	assert.Equal(t, []WorldLane{LaneBook, LaneFilm, LaneShow}, world.Kinds())
}
