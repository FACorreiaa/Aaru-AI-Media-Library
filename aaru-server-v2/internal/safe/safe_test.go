package safe

import (
	"context"
	"errors"
	"fmt"
	"sync"
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
		panic("boom")
	})
	assert.True(t, IsPanic(err))
	assert.Equal(t, 0, n)
}

func TestGroupTurnsAPanicIntoItsError(t *testing.T) {
	g, ctx := WithContext(context.Background())
	g.SetLimit(2)
	g.Go(func() error { panic("decoder bug") })
	g.Go(func() error {
		<-ctx.Done() // the panic ends the group's context, like any error
		return ctx.Err()
	})
	err := g.Wait()
	require.Error(t, err)
	assert.True(t, IsPanic(err), "%v", err)
	assert.Contains(t, string(Stack(err)), "safe_test.go")
}

func TestGroupKeepsAnOrdinaryError(t *testing.T) {
	want := errors.New("no")
	g, _ := WithContext(context.Background())
	g.Go(func() error { return nil })
	g.Go(func() error { return want })
	err := g.Wait()
	require.ErrorIs(t, err, want)
	assert.False(t, IsPanic(err))
}

func TestGoKeepsAPanicFromEndingTheProcess(t *testing.T) {
	var wg sync.WaitGroup
	ran := false
	Go(&wg, "test", func() { panic("boom") })
	Go(&wg, "test", func() { ran = true })
	wg.Wait()
	assert.True(t, ran)
}
