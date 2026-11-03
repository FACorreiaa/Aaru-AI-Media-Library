package imports

import (
	"aaru-go-api/internal/safe"
	"context"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// Go audit REL-001: a step that panics is one failed step; the loop goes on.
func TestLoopsOutliveAPanickingStep(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var mu sync.Mutex
	calls := 0
	var failures []error
	step := func(context.Context) (bool, error) {
		mu.Lock()
		calls++
		n := calls
		mu.Unlock()
		switch {
		case n == 1:
			panic("parser bug")
		case n >= 3:
			cancel()
		}
		return true, nil
	}
	done := make(chan struct{})
	go func() {
		Loops(ctx, 1, time.Millisecond, step, func(err error) {
			mu.Lock()
			failures = append(failures, err)
			mu.Unlock()
		})
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("the loop stopped after the panic")
	}
	mu.Lock()
	defer mu.Unlock()
	assert.GreaterOrEqual(t, calls, 3)
	if assert.Len(t, failures, 1) {
		assert.True(t, safe.IsPanic(failures[0]))
		assert.Contains(t, string(safe.Stack(failures[0])), "TestLoopsOutliveAPanickingStep")
	}
}
