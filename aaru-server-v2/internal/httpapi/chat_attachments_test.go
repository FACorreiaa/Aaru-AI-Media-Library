package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/model"
	"encoding/base64"
	"net/http"
	"net/url"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ASK-010 · files in a chat, over HTTP.

func (e *chatEnv) attach(chat, filename, contentType string, data []byte) (int, map[string]any) {
	e.t.Helper()
	path := "/v1/chats/" + chat + "/attachments"
	if filename != "" {
		path += "?filename=" + url.QueryEscape(filename)
	}
	rec := e.sendBytes(http.MethodPost, path, e.bearer, contentType, data, false)
	return rec.Code, decode[map[string]any](e.t, rec)
}

func TestAttachAnExportSaysWhatItIs(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	chat := e.newChat(e.bearer)
	csv := "Date,Name,Year,Letterboxd URI\n2024-01-01,Dune,2021,https://boxd.it/a\n2024-01-02,Heat,1995,https://boxd.it/b\n"

	code, body := e.attach(chat, "watched.csv", "text/csv", []byte(csv))

	require.Equal(t, http.StatusCreated, code, body)
	assert.Equal(t, "export", body["kind"])
	assert.Equal(t, "letterboxd_csv", body["source"])
	assert.InDelta(t, 2, body["rows"], 0)
	assert.Equal(t, "a Letterboxd export of 2 rows", body["summary"])
	assert.Equal(t, "watched.csv", body["name"])
}

func TestAttachRefusesWhatIsNotAFileAaruReads(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	chat := e.newChat(e.bearer)
	program := append([]byte("MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff\x00\x00"), make([]byte, 256)...)
	for name, tc := range map[string]struct {
		file, contentType string
		data              []byte
		code              int
	}{
		"a program as a CSV":      {"list.csv", "text/csv", program, http.StatusUnprocessableEntity},
		"a zip":                   {"list.zip", "application/zip", []byte("PK\x03\x04\x14\x00rest"), http.StatusUnprocessableEntity},
		"a PDF with a script":     {"list.pdf", "application/pdf", []byte("%PDF-1.7\n<< /S /JavaScript /JS (x) >>\n%%EOF\n"), http.StatusUnprocessableEntity},
		"JSON that is no history": {"data.json", "application/json", []byte(`{"hello":"world"}`), http.StatusUnprocessableEntity},
		"a picture named a CSV":   {"list.csv", "", testPicture(t, 3, 0), http.StatusUnprocessableEntity},
		"empty":                   {"list.csv", "text/csv", nil, http.StatusUnprocessableEntity},
	} {
		code, body := e.attach(chat, tc.file, tc.contentType, tc.data)
		assert.Equal(t, tc.code, code, "%s: %v", name, body)
	}
	assert.Zero(t, e.count(`SELECT count(*)::int FROM chat_attachments WHERE chat_id = $1::uuid`, chat), "nothing kept")
}

func TestAttachToSomeoneElsesChatIsNotFound(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	_, other := e.signIn()
	theirs := e.newChat(other)

	code, _ := e.attach(theirs, "notes.txt", "text/plain", []byte("Dune"))

	assert.Equal(t, http.StatusNotFound, code)
}

func TestAPastedTextAndAPictureGoWithTheTurn(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("Two films and a screenshot.")}}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)
	pasted := strings.Repeat("1. Dune (2021)\n", 400) // longer than a typed question
	code, text := e.attach(chat, "", "text/plain", []byte(pasted))
	require.Equal(t, http.StatusCreated, code, text)
	assert.Equal(t, "Pasted text", text["name"])
	picture := testPicture(t, 7, 0)
	code, shot := e.attach(chat, "shot.jpg", "image/jpeg", picture)
	require.Equal(t, http.StatusCreated, code, shot)

	res := e.openTurn(chatDeadline(t), e.listen(), chat, e.bearer, map[string]any{
		"body": "", "attachments": []any{text["id"], shot["id"]},
	})
	require.Equal(t, http.StatusOK, res.StatusCode)
	frames := sseOf(res.Body).rest()
	assert.Equal(t, "done", frames[len(frames)-1].event)

	gates, mains := m.counts()
	assert.Zero(t, gates, "files alone skip the gate")
	require.Equal(t, 1, mains)
	seen := seenBy(m.requests[0])
	assert.Contains(t, seen, base64.StdEncoding.EncodeToString(picture))
	assert.Contains(t, seen, "1. Dune (2021)")
	assert.Equal(t, 1, e.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1::uuid AND role = 'user'
		AND body = E'[Attached Pasted text]\n[Attached shot.jpg]'`, chat), "only the names are kept")
}

func TestATurnWithAFileThatIsGone(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)

	rec := e.send(http.MethodPost, "/v1/chats/"+chat+"/turns", map[string]any{
		"body": "import it", "attachments": []string{"5B1F5A52-8E5C-4C07-9D2A-36B3D1F3A0B1"},
	})

	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Equal(t, "attachment_gone", decode[api.ErrorResponse](t, rec).Code)
}

func TestDeleteAnAttachment(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	chat := e.newChat(e.bearer)
	_, body := e.attach(chat, "notes.txt", "text/plain", []byte("Dune"))
	id, _ := body["id"].(string)

	rec := e.send(http.MethodDelete, "/v1/chats/"+chat+"/attachments/"+id, nil)
	assert.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	assert.Zero(t, e.count(`SELECT count(*)::int FROM chat_attachments WHERE chat_id = $1::uuid`, chat))
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/chats/"+chat+"/attachments/"+id, nil).Code, "gone already is fine")
}

// seenBy is everything one request showed the model, as one string.
func seenBy(req model.Request) string {
	var b strings.Builder
	b.WriteString(req.System)
	for _, turn := range req.Turns {
		for _, block := range turn.Content {
			b.Write(block)
		}
	}
	return b.String()
}
