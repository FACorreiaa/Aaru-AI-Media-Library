// Package safe turns a panic in background work into an error, so one bad job fails through its
// normal attempts instead of taking the process (and every socket and request on it) down.
package safe

import (
	"errors"
	"fmt"
	"runtime/debug"
)

// PanicError is a recovered panic: the value and the stack where it happened.
type PanicError struct {
	Value any
	Stack []byte
}

func (e *PanicError) Error() string {
	return fmt.Sprintf("panic: %v", e.Value)
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
