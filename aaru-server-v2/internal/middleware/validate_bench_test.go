package middleware

import (
	"aaru-go-api/internal/api"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v5"
)

// BenchmarkValidate is PERF-005's measurement: what the request validator costs per request,
// for a route early in the spec, one late in it (kin-openapi matches paths in turn), and a small
// JSON body (decoded into `any` before the handler decodes it again).
func BenchmarkValidate(b *testing.B) {
	spec, err := api.GetSwagger()
	if err != nil {
		b.Fatal(err)
	}
	validate, err := Validate(spec)
	if err != nil {
		b.Fatal(err)
	}
	e := echo.New()
	handler := validate(func(*echo.Context) error { return nil })
	cases := []struct {
		name, method, path, body string
	}{
		{"get-early", http.MethodGet, "/v1/health", ""},
		{"get-late", http.MethodGet, "/v1/imports/0b6a2f63-6c7e-4b8c-9a55-0d4f1c2e3a4b", ""},
		{"post-json", http.MethodPost, "/v1/auth/email/link", `{"email":"a@example.com"}`},
	}
	for _, tc := range cases {
		b.Run(tc.name, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
				if tc.body != "" {
					req.Header.Set("Content-Type", "application/json")
				}
				if err := handler(e.NewContext(req, httptest.NewRecorder())); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
