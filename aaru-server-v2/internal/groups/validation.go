package groups

import (
	"aaru-go-api/internal/apperr"
	"fmt"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Limits (GroupService.swift).
const (
	MaxMembers           = 50
	MaxChannels          = 20
	MaxOwnedGroups       = 10
	MaxNameLength        = 50
	MaxChannelNameLength = 32
	MaxTopicLength       = 200
	MaxMessageLength     = 4000
	DefaultPageSize      = 50
	MaxPageSize          = 100
	// AgentHandle is the handle a message uses to tag the agent. Reserved in social.
	AgentHandle = "aaru"
)

// Errors every group route shares. A non-member gets the same 404 as a missing group.
var (
	ErrNoSuchGroup   = apperr.NotFound("No such group.")
	ErrNoSuchMember  = apperr.NotFound("Not a member of this group.")
	ErrNoSuchInvite  = apperr.NotFound("No such invite.")
	ErrNoSuchChannel = apperr.NotFound("No such channel.")
	ErrNoSuchMessage = apperr.NotFound("No such message.")
)

// Forbidden is a 403 `forbidden`.
func Forbidden(message string) error { return apperr.Forbidden(message) }

// Invalid is a 422 `validation_failed` on one field.
func Invalid(field, message string) error { return apperr.Validation(field, message) }

// ErrHandleRequired is returned when posting, inviting or hosting without a handle, so friends see who it is.
var ErrHandleRequired = apperr.New(422, "handle_required", "Choose a handle first, so friends can see who you are.")

var handlePattern = regexp.MustCompile(`@([A-Za-z0-9_]{3,20})`)

// Mentions are the users tagged with `@handle`, and whether `@aaru` was. A tag inside a word or
// an email address is not a mention. The Board uses the same rules over its own people.
func Mentions(body string, users []User) (ids []uuid.UUID, agent bool) {
	byHandle := map[string]uuid.UUID{}
	for _, u := range users {
		if _, ok := byHandle[u.Handle]; !ok {
			byHandle[u.Handle] = u.ID
		}
	}
	ids = []uuid.UUID{}
	for _, loc := range handlePattern.FindAllStringSubmatchIndex(body, -1) {
		if loc[0] > 0 {
			before, _ := utf8.DecodeLastRuneInString(body[:loc[0]])
			if isHandleCharacter(before) {
				continue
			}
		}
		if loc[1] < len(body) {
			after, _ := utf8.DecodeRuneInString(body[loc[1]:])
			if isHandleCharacter(after) {
				continue
			}
		}
		handle := strings.ToLower(body[loc[2]:loc[3]])
		if handle == AgentHandle {
			agent = true
			continue
		}
		if id, ok := byHandle[handle]; ok && !containsID(ids, id) {
			ids = append(ids, id)
		}
	}
	return ids, agent
}

func memberUsers(members []Member) []User {
	users := make([]User, len(members))
	for i, m := range members {
		users[i] = m.User
	}
	return users
}

func isHandleCharacter(r rune) bool {
	return r == '_' || r == '@' || unicode.IsLetter(r) || unicode.IsNumber(r)
}

func containsID(ids []uuid.UUID, id uuid.UUID) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

func trim(s string) string { return strings.TrimFunc(s, unicode.IsSpace) }

func length(s string) int { return utf8.RuneCountInString(s) }

// ChannelName lowercases, turns spaces into dashes and keeps letters, numbers, dashes and
// underscores: `Movie Night` becomes `movie-night`.
func ChannelName(raw string) (string, error) {
	words := strings.FieldsFunc(strings.ToLower(raw), func(r rune) bool { return unicode.IsSpace(r) || r == '-' })
	var kept []string
	for _, w := range words {
		filtered := strings.Map(func(r rune) rune {
			if unicode.IsLetter(r) || unicode.IsNumber(r) || r == '_' {
				return r
			}
			return -1
		}, w)
		if filtered != "" {
			kept = append(kept, filtered)
		}
	}
	name := strings.Join(kept, "-")
	if name == "" || length(name) > MaxChannelNameLength {
		return "", Invalid("name", fmt.Sprintf("Use 1–%d letters or numbers.", MaxChannelNameLength))
	}
	return name, nil
}

// ValidName is a group name, trimmed.
func ValidName(raw string) (string, error) {
	name := trim(raw)
	if name == "" || length(name) > MaxNameLength {
		return "", Invalid("name", fmt.Sprintf("Use 1–%d characters.", MaxNameLength))
	}
	return name, nil
}

// ValidTopic is trimmed; empty clears it (nil).
func ValidTopic(raw *string) (*string, error) {
	if raw == nil {
		return nil, nil //nolint:nilnil // no stamp, as Swift's optional
	}
	topic := trim(*raw)
	if topic == "" {
		return nil, nil //nolint:nilnil // no stamp, as Swift's optional
	}
	if length(topic) > MaxTopicLength {
		return nil, Invalid("topic", fmt.Sprintf("Keep the topic under %d characters.", MaxTopicLength))
	}
	return &topic, nil
}

// ValidBody is a message body, trimmed.
func ValidBody(raw string) (string, error) {
	body := trim(raw)
	if body == "" {
		return "", Invalid("body", "Write something first.")
	}
	if length(body) > MaxMessageLength {
		return "", Invalid("body", fmt.Sprintf("Keep messages under %d characters.", MaxMessageLength))
	}
	return body, nil
}

// AutoStamp is the stamp a message gets by default: where the author is in the show, or the
// ending once they finished it. Nothing for a title they have not started.
func AutoStamp(p *TitleProgress) *SpoilerStamp {
	if p == nil {
		return nil
	}
	if p.Status == "finished" {
		return EndingStamp()
	}
	if p.Furthest == nil {
		return nil
	}
	return EpisodeStamp(*p.Furthest)
}

// Veils reports whether a stamp hides a message from a reader with this progress. Finishing a
// title unveils everything about it.
func Veils(stamp *SpoilerStamp, reader *TitleProgress) bool {
	if stamp == nil {
		return false
	}
	if reader != nil && reader.Status == "finished" {
		return false
	}
	if stamp.Ending || stamp.Episode == nil {
		return true
	}
	if reader == nil || reader.Furthest == nil {
		return true
	}
	return reader.Furthest.Before(*stamp.Episode)
}

// VeiledFor are the members a message is veiled for. The author never is.
func VeiledFor(m Message, members []Member, progress map[uuid.UUID]TitleProgress) map[uuid.UUID]bool {
	veiled := map[uuid.UUID]bool{}
	if progress == nil || m.Spoiler == nil {
		return veiled
	}
	for _, member := range members {
		id := member.User.ID
		if id == m.AuthorID() {
			continue
		}
		if Veils(m.Spoiler, progressOf(progress, id)) {
			veiled[id] = true
		}
	}
	return veiled
}

func progressOf(progress map[uuid.UUID]TitleProgress, user uuid.UUID) *TitleProgress {
	if p, ok := progress[user]; ok {
		return &p
	}
	return nil
}
