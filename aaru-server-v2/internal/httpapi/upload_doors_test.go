package httpapi

import (
	"bytes"
	"compress/gzip"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ASK-010: every upload door reads a file's bytes before anything else does.

func TestExportDoorRefusesAProgramSentAsCSV(t *testing.T) {
	env, _ := newOneFakeEnv(t)
	program := append([]byte("MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\x00\x00"), make([]byte, 128)...)
	rec := env.upload("/v1/imports/csv?source=auto&filename=list.csv", "text/csv", program)
	assert.Equal(t, 422, rec.Code)
	body := decode[map[string]any](t, rec)
	assert.Contains(t, body["message"], "program")
}

func TestExportDoorRefusesXMLThatDeclaresEntities(t *testing.T) {
	env, _ := newOneFakeEnv(t)
	bomb := `<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol">]><myanimelist>&lol;</myanimelist>`
	rec := env.upload("/v1/imports/csv?source=auto&filename=animelist.xml", "application/xml", []byte(bomb))
	assert.Equal(t, 422, rec.Code)
}

func TestExportDoorUnpacksMALGzip(t *testing.T) {
	env, _ := newOneFakeEnv(t)
	var packed bytes.Buffer
	w := gzip.NewWriter(&packed)
	_, err := w.Write([]byte(`<?xml version="1.0"?><myanimelist><anime><series_title>Frieren</series_title>` +
		`<series_animedb_id>52991</series_animedb_id><my_status>Completed</my_status></anime></myanimelist>`))
	require.NoError(t, err)
	require.NoError(t, w.Close())
	rec := env.upload("/v1/imports/csv?source=auto&filename=animelist.xml.gz", "application/xml", packed.Bytes())
	assert.Equal(t, 202, rec.Code, rec.Body.String())
}

func TestCaptureDoorRefusesAPictureWhoseBytesSayOtherwise(t *testing.T) {
	env := newCaptureEnv(t, &captureModel{}, nil)
	jpegBytes := testPicture(t, 9, 0)
	rec := env.upload("/v1/imports/capture", "image/png", jpegBytes)
	assert.Equal(t, 422, rec.Code)

	rec = env.upload("/v1/imports/capture", "image/jpeg", []byte("%PDF-1.7\n%%EOF\n"))
	assert.Equal(t, 422, rec.Code)
}
