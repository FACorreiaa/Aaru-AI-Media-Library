package middleware

import (
	"errors"
	"fmt"
	"net/http"
	"runtime/debug"

	"github.com/labstack/echo/v4"
)

// PanicError is a handler panic turned into an error, with the goroutine's stack where it
// happened. Errors logs the stack and reports it like any 500.
type PanicError struct {
	Value any
	Stack []byte
}

func (e *PanicError) Error() string { return fmt.Sprintf("panic: %v", e.Value) }

// Unwrap is the panic's value when it was an error.
func (e *PanicError) Unwrap() error {
	err, _ := e.Value.(error)
	return err
}

// Recover turns a handler panic into a *PanicError (REL-001), so Errors, which wraps it, answers
// the JSON 500, logs the stack and reports it once, instead of net/http cutting the connection.
// http.ErrAbortHandler is net/http's deliberate abort and is panicked on.
func Recover() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) (err error) {
			defer func() {
				r := recover()
				if r == nil {
					return
				}
				if e, ok := r.(error); ok && errors.Is(e, http.ErrAbortHandler) {
					panic(r)
				}
				err = &PanicError{Value: r, Stack: debug.Stack()}
			}()
			return next(c)
		}
	}
}
