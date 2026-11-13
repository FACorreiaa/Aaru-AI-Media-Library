// Package moderation is the word filter on text one person writes for another to read
// (SOC-012, owner 2026-11-13; App Store guideline 1.2).
//
// It is a short, reviewed list (words.txt) matched on Aaru's own server: no outside service
// and no model sees the text. A write that holds a listed word is refused whole with one typed
// error that never names the word; nothing is stored and the text is never logged. Private
// text (library notes, chats with Aaru, a list's name) is not checked, and neither is what
// `@aaru` writes. Text already stored is never scanned.
package moderation

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/metrics"
	_ "embed"
	"net/http"
)

//go:embed words.txt
var builtinList []byte

var builtin = mustParse(builtinList)

func mustParse(data []byte) *Matcher {
	m, err := Parse(data)
	if err != nil {
		panic(err) // the committed list does not parse: a build error, caught by the package's tests
	}
	return m
}

// Builtin is the matcher over the committed list.
func Builtin() *Matcher { return builtin }

// Surface is where refused text was headed. The metric's one label: a small fixed set.
type Surface string

// The surfaces that are checked. metrics.ContentRefusalSurfaces repeats them.
const (
	SurfaceBoardPost      Surface = "board_post"
	SurfaceBoardComment   Surface = "board_comment"
	SurfaceGroupMessage   Surface = "group_message"
	SurfaceGroupName      Surface = "group_name"
	SurfaceChannelName    Surface = "channel_name"
	SurfaceChannelTopic   Surface = "channel_topic"
	SurfaceRecommendation Surface = "recommendation_note"
	SurfaceShareNote      Surface = "share_note"
	SurfaceProfileName    Surface = "profile_name"
	SurfaceHandle         Surface = "handle"
)

// Surfaces are every checked surface.
var Surfaces = []Surface{
	SurfaceBoardPost, SurfaceBoardComment, SurfaceGroupMessage, SurfaceGroupName, SurfaceChannelName,
	SurfaceChannelTopic, SurfaceRecommendation, SurfaceShareNote, SurfaceProfileName, SurfaceHandle,
}

// ErrNotAllowed is the one answer to refused text: 422 `content_not_allowed`. It never names
// the word, so the list cannot be read back one guess at a time any faster than by posting.
var ErrNotAllowed = apperr.New(http.StatusUnprocessableEntity, "content_not_allowed",
	"That text has words Aaru doesn't allow. Change it and try again.")

// Check refuses text headed for a surface when it holds a listed word, and counts the refusal.
func Check(surface Surface, text string) error {
	if builtin.Allows(text) {
		return nil
	}
	return refuse(surface)
}

// CheckHandle is Check for a handle, where words run together.
func CheckHandle(handle string) error {
	if builtin.AllowsHandle(handle) {
		return nil
	}
	return refuse(SurfaceHandle)
}

// Allowed reports whether text may be shown, counting a refusal. For the one place that drops
// the text rather than refuse the request: the name a sign-in brings.
func Allowed(surface Surface, text string) bool {
	return Check(surface, text) == nil
}

func refuse(surface Surface) error {
	metrics.ContentRefusals.WithLabelValues(string(surface)).Inc()
	return ErrNotAllowed
}
