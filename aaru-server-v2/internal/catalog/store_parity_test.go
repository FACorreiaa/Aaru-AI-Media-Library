package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// DatabaseTests.externalIDsAreUnique (SRV-005): a non-null external id is unique per type; nulls are not.
func TestANonNullExternalIDIsUniqueAndNullsAreNot(t *testing.T) {
	store := NewStore(testdb.New(t))
	ctx := context.Background()
	tmdb := "srv005-" + uuid.NewString()
	insert := func(mediaType core.MediaType, name string, ids core.ExternalIDs) error {
		return store.Insert(ctx, core.Title{ID: uuid.New(), Type: mediaType, Title: name, IDs: ids}, nil, nil, nil)
	}
	require.NoError(t, insert(core.MediaMovie, "A", core.ExternalIDs{TMDB: tmdb}))
	assert.ErrorIs(t, insert(core.MediaMovie, "B", core.ExternalIDs{TMDB: tmdb}), ErrTitleConflict)
	// TMDB numbers movies and shows separately.
	require.NoError(t, insert(core.MediaShow, "C", core.ExternalIDs{TMDB: tmdb}))
	// Two titles with no tmdb id both insert.
	require.NoError(t, insert(core.MediaMovie, "D", core.ExternalIDs{}))
	require.NoError(t, insert(core.MediaMovie, "D", core.ExternalIDs{}))
}

// DatabaseTests.titleRoundTrip (SRV-005): a title round-trips.
func TestATitleRoundTrips(t *testing.T) {
	store := NewStore(testdb.New(t))
	ctx := context.Background()
	year := 2025
	poster := "https://image.tmdb.org/t/p/w500/x.jpg"
	title := core.Title{
		ID: uuid.New(), Type: core.MediaShow, Title: "The Paper", Year: &year, PosterURL: &poster,
		IDs: core.ExternalIDs{TMDB: "rt-" + uuid.NewString(), IMDB: "tt-" + uuid.NewString()},
	}
	require.NoError(t, store.Insert(ctx, title, nil, nil, nil))
	stored, err := store.Title(ctx, title.ID)
	require.NoError(t, err)
	require.NotNil(t, stored)
	assert.Equal(t, title, *stored)
}
