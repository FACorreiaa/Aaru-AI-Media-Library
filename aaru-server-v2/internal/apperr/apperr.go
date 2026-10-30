// Package apperr is the one error shape every route returns (`ErrorResponse`).
//
// Return an *Error (or wrap one) from a handler or service and the server writes
// its status and code. Anything else becomes an opaque 500 that is logged and
// reported; its text never reaches the client.
package apperr

import (
	"errors"
	"fmt"
	"net/http"
)

// Error is an error a route means to return.
type Error struct {
	Status  int
	Code    string
	Message string
	Details map[string]string
}

func (e *Error) Error() string {
	return fmt.Sprintf("%d %s: %s", e.Status, e.Code, e.Message)
}

// New builds an error with an explicit status and code.
func New(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

// WithDetails returns a copy carrying per-field details.
func (e *Error) WithDetails(details map[string]string) *Error {
	c := *e
	c.Details = details
	return &c
}

// NotFound is a 404 `not_found`.
func NotFound(message ...string) *Error {
	return New(http.StatusNotFound, "not_found", first(message, "Not found."))
}

// Conflict is a 409 `conflict`.
func Conflict(message string) *Error {
	return New(http.StatusConflict, "conflict", message)
}

// BadRequest is a 400 `bad_request`.
func BadRequest(message ...string) *Error {
	return New(http.StatusBadRequest, "bad_request", first(message, "The request could not be read."))
}

// Unauthorized is a 401 `unauthorized`.
func Unauthorized(message ...string) *Error {
	return New(http.StatusUnauthorized, "unauthorized", first(message, "Sign in to continue."))
}

// Forbidden is a 403 `forbidden`.
func Forbidden(message string) *Error {
	return New(http.StatusForbidden, "forbidden", message)
}

// Validation is a 422 `validation_failed` naming the offending request field.
func Validation(field, message string) *Error {
	return &Error{
		Status:  http.StatusUnprocessableEntity,
		Code:    "validation_failed",
		Message: message,
		Details: map[string]string{field: message},
	}
}

// RateLimited is a 429 `rate_limited`.
func RateLimited(message string) *Error {
	return New(http.StatusTooManyRequests, "rate_limited", message)
}

// Unavailable is a 503 with the given code (a feature that is not configured).
func Unavailable(code, message string) *Error {
	return New(http.StatusServiceUnavailable, code, message)
}

// ProviderUnavailable is the 502 a failing upstream catalog or service maps to.
func ProviderUnavailable(provider, displayName string) *Error {
	return &Error{
		Status:  http.StatusBadGateway,
		Code:    "provider_unavailable",
		Message: displayName + " is unavailable right now. Try again later.",
		Details: map[string]string{"provider": provider},
	}
}

// Internal is the opaque 500.
func Internal() *Error {
	return New(http.StatusInternalServerError, "internal", "Something went wrong.")
}

var codes = map[int]string{
	400: "bad_request",
	401: "unauthorized",
	403: "forbidden",
	404: "not_found",
	405: "method_not_allowed",
	409: "conflict",
	413: "payload_too_large",
	422: "validation_failed",
	429: "rate_limited",
}

// CodeFor is the shared code for a bare status (unknown route, bad method, oversize body).
func CodeFor(status int) string {
	if c, ok := codes[status]; ok {
		return c
	}
	if status >= 400 && status < 500 {
		return "client_error"
	}
	return "internal"
}

// FromStatus maps a framework status to the shared shape.
func FromStatus(status int, message string) *Error {
	if message == "" {
		if status >= 500 {
			message = "Something went wrong."
		} else {
			message = http.StatusText(status)
		}
	}
	return New(status, CodeFor(status), message)
}

// Convertible is a domain error that knows its HTTP shape.
type Convertible interface {
	AppError() *Error
}

// From finds the route error inside err, or nil when err carries none.
func From(err error) *Error {
	var e *Error
	if errors.As(err, &e) {
		return e
	}
	var c Convertible
	if errors.As(err, &c) {
		return c.AppError()
	}
	return nil
}

func first(values []string, def string) string {
	if len(values) > 0 && values[0] != "" {
		return values[0]
	}
	return def
}
