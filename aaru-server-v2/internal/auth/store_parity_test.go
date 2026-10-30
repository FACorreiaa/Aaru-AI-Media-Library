//go:build parity_g1

package auth

import (
	"aaru-go-api/internal/testdb"
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// DatabaseTests.identityIsUnique (SRV-004): one identity maps to one user.
func TestOneIdentityMapsToOneUser(t *testing.T) {
	store := NewStore(testdb.New(t))
	ctx := context.Background()
	identity := Identity{Provider: ProviderApple, Subject: uuid.NewString()}
	id, err := store.createUser(ctx, identity, nil)
	require.NoError(t, err)
	found, ok, err := store.userFor(ctx, ProviderApple, identity.Subject)
	require.NoError(t, err)
	assert.True(t, ok)
	assert.Equal(t, id, found)
	_, err = store.createUser(ctx, identity, nil)
	var conflict storeConflict
	assert.ErrorAs(t, err, &conflict)
}

// ProfileTests.split: a name splits at the first space; a name joins back for display.
func TestANameSplitsAtTheFirstSpace(t *testing.T) {
	str := func(s string) *string { return &s }
	first, last := SplitName(str("  Ana  "))
	assert.Equal(t, str("Ana"), first)
	assert.Nil(t, last)
	first, last = SplitName(str("Fernando Pereira Correia"))
	assert.Equal(t, str("Fernando"), first)
	assert.Equal(t, str("Pereira Correia"), last)
	first, last = SplitName(str(""))
	assert.Nil(t, first)
	assert.Nil(t, last)
	assert.Equal(t, str("Lopes"), JoinName(nil, str("Lopes")))
	assert.Nil(t, JoinName(nil, nil))
}
