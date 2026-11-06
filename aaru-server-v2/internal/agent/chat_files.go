package agent

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/model"
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/uuid"
)

// FileImporter hands a chat's file to an import the user reviews in Aaru (ASK-010): an export as a
// file import, a listening history to the listening log, a picture, PDF or text as a capture. It
// never writes the library. Implemented by imports.AgentImporter.
type FileImporter interface {
	CreateFileImport(ctx context.Context, user uuid.UUID, source core.ImportSource, filename *string, text string) (uuid.UUID, error)
	CreateListenImport(ctx context.Context, user uuid.UUID, source core.ImportSource, filename *string, data []byte) (uuid.UUID, error)
	CreateTextCapture(ctx context.Context, user uuid.UUID, text string) (uuid.UUID, error)
	CreatePictureCapture(ctx context.Context, user uuid.UUID, pictures []model.Image) (uuid.UUID, error)
	CreateDocumentCapture(ctx context.Context, user uuid.UUID, pdf []byte) (uuid.UUID, error)
}

// attach gives this turn the chat's files by ref. Any file at all taints the turn.
func (t *ChatTools) attach(refs map[string]Attachment) {
	t.attachments = refs
	t.tainted = len(refs) > 0
}

// rememberOnScreen names the title on screen r0 when it is in the user's library, so "this season"
// needs no search; the line says so for the prompt. Empty when it is not theirs.
func (t *ChatTools) rememberOnScreen(ctx context.Context, title core.Title) (string, error) {
	entry, err := t.Library.Store.EntryForTitle(ctx, t.User, title.ID, t.now())
	if err != nil {
		return "", fmt.Errorf("chat hint entry: %w", err)
	}
	if entry == nil {
		return " It is not in their library.", nil
	}
	id := title.ID
	t.refs[OnScreenRef] = core.MediaRef{TitleID: &id, Type: title.Type}
	t.items[OnScreenRef] = entry.Item.ID
	return " In their library it is ref " + OnScreenRef + " for apply_library_patch: " + describeEntry(*entry) + ".", nil
}

// OnScreenRef is the ref of the title the user is looking at, when it is in their library.
const OnScreenRef = "r0"

// describeEntry is a library line: status, then how far along and what is next.
func describeEntry(e library.Entry) string {
	line := string(e.Item.Status)
	if p := e.Progress; p != nil {
		line += fmt.Sprintf(", %d/%d episodes", p.WatchedCount, p.AiredCount)
		if p.NextEpisode != nil {
			line += fmt.Sprintf(", next is season %d episode %d", p.NextEpisode.Season, p.NextEpisode.Episode)
		}
	}
	if e.Item.Rating != nil {
		line += ", rated " + swiftDouble(e.Item.Rating.Value()) + "/10"
	}
	return line
}

// importAttachmentTool is import_attachment: offered only while the chat holds files.
var importAttachmentTool = model.Tool{
	Name: "import_attachment",
	Description: "Bring the titles in files the user sent into Aaru, as one import the user reviews in Aaru: an " +
		"export (IMDb, Letterboxd, Goodreads, Netflix, TV Time, MyAnimeList, CAT, any CSV) or a listening history is " +
		"read whole; pictures (up to 5 together), a PDF or text are read for the titles they name, and spend one of " +
		"the user's captures. Nothing is added until the user approves. Once per reply; one kind of file per call.",
	InputSchema: schema(map[string]any{
		"refs": map[string]any{
			"type": "array", "minItems": 1, "maxItems": MaxTurnAttachments, "items": map[string]any{"type": "string"},
		},
	}, []string{"refs"}),
}

// importAttachment is import_attachment. Its import id goes to the reply's card for review.
func (t *ChatTools) importAttachment(ctx context.Context, input json.RawMessage) (string, error) {
	if t.importID != nil {
		return "An import from this reply is already waiting for the user's review. Tell them that.", nil
	}
	var args struct {
		Refs []string `json:"refs"`
	}
	if err := json.Unmarshal(input, &args); err != nil || len(args.Refs) == 0 {
		return "", toolError("refs must name at least one file, such as a1.")
	}
	files := make([]Attachment, 0, len(args.Refs))
	for _, ref := range args.Refs {
		f, ok := t.attachments[ref]
		if !ok {
			return "", toolError("Unknown file " + ref + "; use a ref from the files in this chat.")
		}
		files = append(files, f)
	}
	kind := files[0].Kind
	for _, f := range files[1:] {
		if f.Kind != kind {
			return "", toolError("One kind of file per call: send the pictures, a PDF, text or an export on its own.")
		}
	}
	if kind != AttachImage && len(files) > 1 {
		return "", toolError("Only pictures go together; send one " + kind + " file per call.")
	}
	id, err := t.startImport(ctx, files)
	if err != nil {
		return "", err
	}
	t.importID = &id
	names := make([]string, len(files))
	for i, f := range files {
		names[i] = f.Name
	}
	return strings.Join(names, ", ") + " sent. Aaru is reading it, then the titles wait for the user's review in Aaru. " +
		"Nothing is added until they approve. Tell them that.", nil
}

func (t *ChatTools) startImport(ctx context.Context, files []Attachment) (uuid.UUID, error) {
	f := files[0]
	name := f.Name
	switch f.Kind {
	case AttachExport:
		if f.Source == nil {
			return uuid.Nil, toolError("Aaru could not tell what export this is.")
		}
		return t.deps.Files.CreateFileImport(ctx, t.User, *f.Source, &name, string(f.Data))
	case AttachListens:
		if f.Source == nil {
			return uuid.Nil, toolError("Aaru could not tell what history this is.")
		}
		return t.deps.Files.CreateListenImport(ctx, t.User, *f.Source, &name, f.Data)
	case AttachText:
		return t.deps.Files.CreateTextCapture(ctx, t.User, string(f.Data))
	case AttachPDF:
		return t.deps.Files.CreateDocumentCapture(ctx, t.User, f.Data)
	case AttachImage:
		pictures := make([]model.Image, len(files))
		for i, p := range files {
			pictures[i] = model.Image{Data: p.Data, MediaType: p.MediaType}
		}
		return t.deps.Files.CreatePictureCapture(ctx, t.User, pictures)
	}
	return uuid.Nil, toolError("Aaru cannot import that file.")
}
