package httpapi

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Swift's JSONDecoder matched keys exactly at every depth; a nested key in the wrong case is absent.
func TestToolArgumentKeysMatchExactly(t *testing.T) {
	var args struct {
		Patch struct {
			Status *string `json:"status"`
		} `json:"patch"`
	}
	require.NoError(t, decodeArgs(json.RawMessage(`{"patch":{"Status":"finished"}}`), &args))
	assert.Nil(t, args.Patch.Status)
	require.NoError(t, decodeArgs(json.RawMessage(`{"patch":{"status":"finished"}}`), &args))
	assert.Equal(t, "finished", *args.Patch.Status)
	assert.ErrorIs(t, decodeArgs(json.RawMessage(`{"patch":`), &args), errArgs)
}
