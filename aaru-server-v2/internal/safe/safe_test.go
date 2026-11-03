package safe

import (
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStepTurnsAPanicIntoAnError(t *testing.T) {
	err := Step(func() error { panic("boom") })
	require.Error(t, err)
	assert.True(t, IsPanic(err))
	assert.Equal(t, "panic: boom", err.Error())
	assert.Contains(t, string(Stack(err)), "TestStepTurnsAPanicIntoAnError")
	assert.True(t, IsPanic(fmt.Errorf("wrapped: %w", err)))
}

func TestStepPassesErrorsAndSuccessThrough(t *testing.T) {
	plain := errors.New("plain")
	assert.Equal(t, plain, Step(func() error { return plain }))
	assert.False(t, IsPanic(plain))
	assert.Nil(t, Stack(plain))
	assert.NoError(t, Step(func() error { return nil }))
}

func TestValueKeepsResultsOrZeroOnPanic(t *testing.T) {
	n, err := Value(func() (int, error) { return 7, nil })
	require.NoError(t, err)
	assert.Equal(t, 7, n)
	n, err = Value(func() (int, error) {
		var m map[string]int
		m["x"] = 1 // nil map write panics
		return 1, nil
	})
	assert.True(t, IsPanic(err))
	assert.Equal(t, 0, n)
}
