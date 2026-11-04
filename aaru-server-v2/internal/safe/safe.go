// Package safe turns a panic in background work into an error, so one bad job fails through its
// normal attempts instead of taking the process (and every socket and request on it) down.
package safe

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"runtime/debug"
	"sync"

	"golang.org/x/sync/errgroup"
)

// PanicError is a recovered panic: the value and the stack where it happened.
type PanicError struct {
	Value any
	Stack []byte
}

func (e *PanicError) Error() string {
	return fmt.Sprintf("panic: %v", e.Value)
}

// Unwrap is the panic's value when it was an error.
func (e *PanicError) Unwrap() error {
	err, _ := e.Value.(error)
	return err
}

// IsPanic reports whether err is (or wraps) a recovered panic.
func IsPanic(err error) bool {
	var p *PanicError
	return errors.As(err, &p)
}

// Stack is the stack of a recovered panic inside err; nil for any other error.
func Stack(err error) []byte {
	var p *PanicError
	if errors.As(err, &p) {
		return p.Stack
	}
	return nil
}

// Step runs fn and returns its error, or a *PanicError when it panicked.
func Step(fn func() error) (err error) {
	defer func() {
		if v := recover(); v != nil {
			err = &PanicError{Value: v, Stack: debug.Stack()}
		}
	}()
	return fn()
}

// Value runs fn and returns its results, or the zero value and a *PanicError when it panicked.
func Value[T any](fn func() (T, error)) (out T, err error) {
	err = Step(func() error {
		var stepErr error
		out, stepErr = fn()
		return stepErr
	})
	return out, err
}

// Go runs fn on wg's own goroutine for work whose failure is not anyone's error: a panic is logged
// where the group would have returned it.
func Go(wg *sync.WaitGroup, where string, fn func()) {
	wg.Go(func() {
		err := Step(func() error {
			fn()
			return nil
		})
		if err != nil {
			slog.Default().Error("Recovered a panic", "where", where, "error", err.Error(), "stack", string(Stack(err)))
		}
	})
}

// Group is errgroup.Group for work that must not take the process down: a panic in one of its
// goroutines becomes the group's error, and Wait returns it as a *PanicError (Go audit REL-001).
// A recover in the caller does not reach those goroutines, so this is the only group to use.
type Group struct {
	g *errgroup.Group
}

// WithContext is errgroup.WithContext: the context ends with the group's first error or Wait.
func WithContext(ctx context.Context) (*Group, context.Context) {
	g, gctx := errgroup.WithContext(ctx)
	return &Group{g: g}, gctx
}

// Go runs fn on its own goroutine, once the group's limit lets it.
func (g *Group) Go(fn func() error) {
	g.g.Go(func() error { return Step(fn) })
}

// SetLimit bounds how many of the group's goroutines run at once.
func (g *Group) SetLimit(n int) { g.g.SetLimit(n) }

// Wait is every goroutine's end and the first error, a panic included.
func (g *Group) Wait() error {
	return g.g.Wait()
}
