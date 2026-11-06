package httpapi

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"math/rand/v2"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// BOOK-001: a capture from the Books page, read from a long chat or several screenshots, whose
// plan the person can untick row by row.

// captureBooksReport is the model calling report_titles with these items.
func captureBooksReport(items ...map[string]any) model.Response {
	block, err := json.Marshal(map[string]any{
		"type": "tool_use", "id": "toolu_1", "name": capture.ToolName, "input": map[string]any{"titles": items},
	})
	if err != nil {
		panic(err)
	}
	return model.Response{Content: []model.Block{block}, Stop: model.StopToolUse, InputTokens: 1500, OutputTokens: 101}
}

// captureBook is a book the fake catalog finds by name, by this author.
func (e *captureEnv) captureBook(name, author string) {
	id := fmt.Sprintf("OL%dW", rand.IntN(90_000_000))
	year := 1965
	hit := catalog.Hit{
		Type: core.MediaBook, Title: name, Year: &year, Byline: &author, IDs: core.ExternalIDs{OpenLibrary: id},
	}
	e.fake.stubTitle(catalog.Record{Hit: hit})
	e.search.searchMu.Lock()
	e.search.hits[name] = append(e.search.hits[name], hit)
	e.search.searchMu.Unlock()
}

// testPicture is a real JPEG of one grey, at least size bytes long: a 2×2 picture, then padding
// past its end that a header read never reaches. Capture checks a picture's bytes (ASK-010).
func testPicture(t testing.TB, grey byte, size int) []byte {
	t.Helper()
	img := image.NewGray(image.Rect(0, 0, 2, 2))
	for i := range img.Pix {
		img.Pix[i] = grey
	}
	var b bytes.Buffer
	require.NoError(t, jpeg.Encode(&b, img, nil))
	if pad := size - b.Len(); pad > 0 {
		b.Write(make([]byte, pad))
	}
	return b.Bytes()
}

// capturePictures posts a multipart form of images, one part per entry.
func (e *captureEnv) capturePictures(path string, parts ...[]byte) (int, map[string]any) {
	e.t.Helper()
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	for _, data := range parts {
		w, err := form.CreatePart(textproto.MIMEHeader{
			"Content-Disposition": {`form-data; name="image"; filename="p.jpg"`},
			"Content-Type":        {"image/jpeg"},
		})
		require.NoError(e.t, err)
		_, err = w.Write(data)
		require.NoError(e.t, err)
	}
	require.NoError(e.t, form.Close())
	rec := e.upload(path, form.FormDataContentType(), body.Bytes())
	return rec.Code, decode[map[string]any](e.t, rec)
}

func TestCaptureForBooksKeepsOnlyBooksAndCarriesTheAuthor(t *testing.T) {
	name := "Dune " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureBooksReport(
		map[string]any{"title": name, "type": "book", "author": "Frank Herbert"},
		// The model was asked for books only; its word is not taken for it.
		map[string]any{"title": "Heat", "type": "movie", "year": 1995},
	)}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(name, "Frank Herbert")

	rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": "You could try " + name})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	assert.Equal(t, core.MediaBook, env.captureInput(id).Content.Only)

	env.runImports()
	_, rows := env.importDetail(id)
	require.Len(t, rows, 1)
	assert.Equal(t, name, rows[0]["title"])
	assert.Equal(t, "Frank Herbert", rows[0]["author"])
	assert.Equal(t, "create", rows[0]["outcome"])
	require.Len(t, m.requests, 1)
	assert.Contains(t, m.requests[0].System, "Report books only")
}

func TestCaptureForBooksThatFindsNoBookSaysSo(t *testing.T) {
	m := &captureModel{responses: []model.Response{captureBooksReport(map[string]any{"title": "Heat", "type": "movie"})}}
	env := newCaptureEnv(t, m, nil)
	rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": "Heat"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	job, _ := env.importDetail(id)
	assert.Equal(t, "failed", job["state"])
	assert.Equal(t, "Aaru found no book in that capture.", job["errorSummary"])
}

func TestCaptureKindOtherThanBookIsRefused(t *testing.T) {
	env := newCaptureEnv(t, &captureModel{}, nil)
	rec := env.send("POST", "/v1/imports/capture?kind=film", map[string]any{"text": "Heat"})
	assert.Equal(t, 422, rec.Code)
}

func TestCaptureBookMatchesByAuthorWithoutAYear(t *testing.T) {
	cases := []struct {
		name     string
		reported func(name string) map[string]any
		catalog  func(e *captureEnv, name string)
		outcome  string
	}{
		{
			name: "the author picks between books alike",
			reported: func(name string) map[string]any {
				return map[string]any{"title": name, "type": "book", "author": "Jane Austen"}
			},
			catalog: func(e *captureEnv, name string) {
				e.captureBook(name, "Someone Else")
				e.captureBook(name, "Jane Austen")
			},
			outcome: "create",
		},
		{
			name: "duplicate works of one book take the first",
			reported: func(name string) map[string]any {
				return map[string]any{"title": name, "type": "book", "author": "Jane Austen"}
			},
			catalog: func(e *captureEnv, name string) {
				e.captureBook(name, "Jane Austen")
				e.captureBook(name, "Jane Austen")
			},
			outcome: "create",
		},
		{
			name: "a subtitle the catalog keeps apart",
			reported: func(name string) map[string]any {
				return map[string]any{"title": name + ": A Brief History", "type": "book", "author": "Yuval Noah Harari"}
			},
			catalog: func(e *captureEnv, name string) { e.captureBook(name, "Yuval Noah Harari") },
			outcome: "create",
		},
		{
			name: "an edition's year is not the catalog's",
			reported: func(name string) map[string]any {
				return map[string]any{"title": name, "type": "book", "author": "Yuval Noah Harari", "year": 2014}
			},
			catalog: func(e *captureEnv, name string) { e.captureBook(name, "Yuval Noah Harari") },
			outcome: "create",
		},
		{
			name: "a summary by someone else is not the book",
			reported: func(name string) map[string]any {
				return map[string]any{"title": name, "type": "book", "author": "James Clear"}
			},
			catalog: func(e *captureEnv, name string) { e.captureBook(name, "Caleb Reads") },
			outcome: "unmatched",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			name := "Book " + uuid.NewString()
			m := &captureModel{responses: []model.Response{captureBooksReport(c.reported(name))}}
			env := newCaptureEnv(t, m, nil)
			c.catalog(env, name)
			rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": name})
			require.Equal(t, 202, rec.Code, rec.Body.String())
			id := decode[map[string]any](t, rec)["id"].(string)
			env.runImports()
			_, rows := env.importDetail(id)
			require.Len(t, rows, 1)
			assert.Equal(t, c.outcome, rows[0]["outcome"], rows[0]["reason"])
		})
	}
}

func TestCaptureNamesTwoBooksAlikeWithoutAnAuthorIsLeftToPick(t *testing.T) {
	name := "Emma " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureBooksReport(map[string]any{"title": name, "type": "book"})}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(name, "Jane Austen")
	env.captureBook(name, "Someone Else")
	rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": name})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	_, rows := env.importDetail(id)
	require.Len(t, rows, 1)
	assert.Equal(t, "unmatched", rows[0]["outcome"])
}

func TestCaptureSeveralPicturesReachTheModelInOrderAndAreDeletedOnceRead(t *testing.T) {
	name := "Dune " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureBooksReport(map[string]any{"title": name, "type": "book"})}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(name, "Frank Herbert")

	pictures := [][]byte{testPicture(t, 1, 0), testPicture(t, 2, 0), testPicture(t, 3, 0)}
	code, body := env.capturePictures("/v1/imports/capture?kind=book", pictures...)
	require.Equal(t, 202, code, body)
	id := body["id"].(string)
	input := env.captureInput(id)
	require.NotNil(t, input)
	assert.Equal(t, "image", input.Content.Kind())
	assert.Len(t, input.Content.Images(), 3)

	env.runImports()
	require.Len(t, m.requests, 1)
	content := m.requests[0].Turns[0].Content
	require.Len(t, content, 4, "three pictures, then the text")
	for i, picture := range pictures {
		assert.Contains(t, string(content[i]), base64.StdEncoding.EncodeToString(picture), "picture %d", i)
	}
	assert.Nil(t, env.captureInput(id))
	var left int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM capture_images WHERE job_id = $1`, uuid.MustParse(id)).Scan(&left))
	assert.Zero(t, left)
}

func TestCapturePictureLimits(t *testing.T) {
	env := newCaptureEnv(t, &captureModel{}, nil)

	one := testPicture(t, 1, 0)
	code, body := env.capturePictures("/v1/imports/capture", one, one, one, one, one, one)
	assert.Equal(t, 422, code)
	assert.Equal(t, "capture_too_many_images", body["code"])

	code, body = env.capturePictures("/v1/imports/capture", bytes.Repeat([]byte{1}, 5*1024*1024+1))
	assert.Equal(t, http.StatusRequestEntityTooLarge, code)
	assert.Equal(t, "file_too_large", body["code"])

	four := testPicture(t, 4, 4*1024*1024)
	code, body = env.capturePictures("/v1/imports/capture", four, four, four, four)
	assert.Equal(t, http.StatusRequestEntityTooLarge, code)
	assert.Equal(t, "file_too_large", body["code"])

	code, _ = env.capturePictures("/v1/imports/capture")
	assert.Equal(t, 422, code, "a form with no picture")
}

func TestCaptureReadsALongChatUpToItsLimit(t *testing.T) {
	env := newCaptureEnv(t, &captureModel{}, nil)
	fits := env.send("POST", "/v1/imports/capture", map[string]any{"text": strings.Repeat("é", 100000)})
	assert.Equal(t, 202, fits.Code, fits.Body.String())
	over := env.send("POST", "/v1/imports/capture", map[string]any{"text": strings.Repeat("a", 100001)})
	assert.Equal(t, http.StatusRequestEntityTooLarge, over.Code)
	assert.Equal(t, "capture_too_large", captureCode(t, over))
}

func TestCaptureUntickedBookIsNotAddedAndTheCountsFollow(t *testing.T) {
	keep, drop := "Keep "+uuid.NewString(), "Drop "+uuid.NewString()
	unknown := "Nobody Wrote This " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureBooksReport(
		map[string]any{"title": keep, "type": "book", "author": "A"},
		map[string]any{"title": drop, "type": "book", "author": "B"},
		map[string]any{"title": unknown, "type": "book"},
	)}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(keep, "A")
	env.captureBook(drop, "B")

	rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": "three books"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	job, rows := env.importDetail(id)
	require.Len(t, rows, 3)
	assert.EqualValues(t, 2, job["stats"].(map[string]any)["created"])

	index := fmt.Sprint(rows[1]["index"])
	left := env.send("POST", "/v1/imports/"+id+"/rows/"+index+"/left-out", map[string]any{"leftOut": true})
	require.Equal(t, 200, left.Code, left.Body.String())
	answer := decode[map[string]any](t, left)
	assert.Equal(t, true, answer["row"].(map[string]any)["leftOut"])
	assert.EqualValues(t, 1, answer["job"].(map[string]any)["stats"].(map[string]any)["created"])

	// Ticked again, then unticked again: the flag follows, and it survives a read.
	back := env.send("POST", "/v1/imports/"+id+"/rows/"+index+"/left-out", map[string]any{"leftOut": false})
	require.Equal(t, 200, back.Code, back.Body.String())
	assert.Nil(t, decode[map[string]any](t, back)["row"].(map[string]any)["leftOut"])
	require.Equal(t, 200, env.send("POST", "/v1/imports/"+id+"/rows/"+index+"/left-out", map[string]any{"leftOut": true}).Code)
	_, rows = env.importDetail(id)
	assert.Equal(t, true, rows[1]["leftOut"])

	// A row the plan does not write cannot be unticked.
	unmatched := fmt.Sprint(rows[2]["index"])
	refused := env.send("POST", "/v1/imports/"+id+"/rows/"+unmatched+"/left-out", map[string]any{"leftOut": true})
	assert.Equal(t, 409, refused.Code)
	assert.Equal(t, "import_row_not_written", captureCode(t, refused))
	assert.Equal(t, 404, env.send("POST", "/v1/imports/"+id+"/rows/999/left-out", map[string]any{"leftOut": true}).Code)

	applied := env.json("POST", "/v1/imports/"+id+"/apply", nil)
	assert.EqualValues(t, 1, applied["stats"].(map[string]any)["created"])
	items := env.json("GET", "/v1/library/items", nil)["items"].([]any)
	require.Len(t, items, 1)
	assert.Equal(t, keep, items[0].(map[string]any)["title"].(map[string]any)["title"])
	_, rows = env.importDetail(id)
	assert.Equal(t, "skip", rows[1]["outcome"], "the review's result does not list it as added")

	late := env.send("POST", "/v1/imports/"+id+"/rows/"+index+"/left-out", map[string]any{"leftOut": false})
	assert.Equal(t, 409, late.Code, "the plan is applied")

	assert.Equal(t, http.StatusOK, env.send("POST", "/v1/actions/"+applied["actionId"].(string)+"/undo", nil).Code)
	assert.Empty(t, env.json("GET", "/v1/library/items", nil)["items"])
}

func TestCaptureWithEveryBookUntickedCannotBeApproved(t *testing.T) {
	name := "Dune " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureBooksReport(map[string]any{"title": name, "type": "book", "author": "Frank Herbert"})}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(name, "Frank Herbert")
	rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": name})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	_, rows := env.importDetail(id)
	require.Len(t, rows, 1)
	left := env.send("POST", "/v1/imports/"+id+"/rows/"+fmt.Sprint(rows[0]["index"])+"/left-out", map[string]any{"leftOut": true})
	require.Equal(t, 200, left.Code, left.Body.String())

	refused := env.send("POST", "/v1/imports/"+id+"/apply", nil)
	assert.Equal(t, 422, refused.Code)
	assert.Equal(t, "import_nothing_chosen", captureCode(t, refused))
	job, _ := env.importDetail(id)
	assert.Equal(t, "planned", job["state"])
	assert.Empty(t, env.json("GET", "/v1/library/items", nil)["items"])
}
