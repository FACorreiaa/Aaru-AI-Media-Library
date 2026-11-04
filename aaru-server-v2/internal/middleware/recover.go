package middleware

import (
	"aaru-go-api/internal/safe"
	"errors"
	"net/http"
	"runtime/debug"

	"github.com/labstack/echo/v4"
)

// PanicError is a panic turned into an error, with the goroutine's stack where it happened: a
// handler's, or one of its safe.Group goroutines'. Errors logs the stack and reports it like any 500.
type PanicError = safe.PanicError

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
