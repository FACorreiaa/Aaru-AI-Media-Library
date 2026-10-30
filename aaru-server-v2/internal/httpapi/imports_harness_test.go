package httpapi

import (
	"bytes"
	"context"
	"net/http/httptest"

	"github.com/stretchr/testify/require"
)

// Shared helpers for import tests (ImportFlowTests' upload/runImports/importDetail).

// upload sends a raw body of one content type as the signed-in user.
func (e *libEnv) upload(path, contentType string, body []byte) *httptest.ResponseRecorder {
	e.t.Helper()
	req := httptest.NewRequest("POST", path, bytes.NewReader(body))
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	req.Header.Set("Authorization", "Bearer "+e.bearer)
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

// uploadJob uploads a file and returns the queued job's id, failing the test on anything but 202.
func (e *libEnv) uploadJob(path, contentType string, body []byte) string {
	e.t.Helper()
	rec := e.upload(path, contentType, body)
	require.Equal(e.t, 202, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)["id"].(string)
}

// runImports runs the signed-in user's queued import jobs until none is left.
func (e *libEnv) runImports() { //nolint:unused // shared by the area's flow tests
	e.t.Helper()
	for {
		worked, err := e.server.Imports.RunNext(context.Background(), &e.user)
		require.NoError(e.t, err)
		if !worked {
			return
		}
	}
}

// importDetail is GET /v1/imports/{id}: the job and its rows.
func (e *libEnv) importDetail(id string) (job map[string]any, rows []map[string]any) {
	e.t.Helper()
	detail := e.json("GET", "/v1/imports/"+id, nil)
	job = detail["job"].(map[string]any)
	for _, r := range detail["rows"].([]any) {
		rows = append(rows, r.(map[string]any))
	}
	return job, rows
}

func importPtr[T any](v T) *T { return &v }
