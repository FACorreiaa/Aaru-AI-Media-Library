package apiid

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUppercaseOnTheWire(t *testing.T) {
	id := uuid.MustParse("e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
	data, err := json.Marshal(struct {
		ID UUID            `json:"id"`
		M  map[UUID]string `json:"m"`
	}{From(id), map[UUID]string{From(id): "x"}})
	require.NoError(t, err)
	assert.JSONEq(t, `{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","m":{"E621E1F8-C36C-495A-93FC-0C247A3E6E5F":"x"}}`, string(data))
}

func TestReadsAnyCaseAndMalformedAsNil(t *testing.T) {
	var v struct{ ID UUID }
	require.NoError(t, json.Unmarshal([]byte(`{"ID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}`), &v))
	assert.Equal(t, "e621e1f8-c36c-495a-93fc-0c247a3e6e5f", v.ID.ID().String())
	require.NoError(t, json.Unmarshal([]byte(`{"ID":"nope"}`), &v))
	assert.Equal(t, uuid.Nil, v.ID.ID())
}
