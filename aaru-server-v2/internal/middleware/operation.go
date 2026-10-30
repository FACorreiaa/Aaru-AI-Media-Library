package middleware

import (
	"aaru-go-api/internal/api"
	"unicode"
	"unicode/utf8"

	"github.com/labstack/echo/v4"
)

const operationKey = "aaru.operation"

// Operation records the openapi operation id for the error reports, as Swift's
// ServerError carried it. oapi-codegen hands over the Go name (`GetTitle`);
// the spec's id, which Swift reported, starts lowercase (`getTitle`).
func Operation(f api.StrictHandlerFunc, operationID string) api.StrictHandlerFunc {
	id := lowerFirst(operationID)
	return func(c echo.Context, request any) (any, error) {
		c.Set(operationKey, id)
		return f(c, request)
	}
}

func operation(c echo.Context) string {
	id, _ := c.Get(operationKey).(string)
	return id
}

func lowerFirst(s string) string {
	r, n := utf8.DecodeRuneInString(s)
	if n == 0 {
		return s
	}
	return string(unicode.ToLower(r)) + s[n:]
}
