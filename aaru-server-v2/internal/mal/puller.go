package mal

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/provider"
	"context"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// The read-back's schedule and limits (MALPuller).
const (
	// PullInterval: every list is read at least this often.
	PullInterval = 6 * time.Hour
	// FullReadInterval: the whole list is read once a week, for entries removed on MAL.
	FullReadInterval = 7 * 24 * time.Hour
	// PullsPerPass is connections read per pass, one after another on the shared MAL pacer.
	PullsPerPass = 10
	// PageSize: a changed-entries read rarely passes its first page; a full read takes MAL's largest.
	PageSize     = 100
	FullPageSize = 1000
	// MaxEntries: no list is read past this many entries.
	MaxEntries = 20000
)

// Applier is the import merge the read-back goes through (imports.Service.ApplyFromMAL).
type Applier interface {
	ApplyFromMAL(ctx context.Context, rows []imports.Row, user uuid.UUID) ([]imports.PlannedRow, error)
}

// Puller is SCR-010: reads connected MyAnimeList lists back into Aaru, the one two-way exception.
// MAL has no webhooks, so a list is read when a client opens Aaru (at most every 10 minutes) and
// every 6 hours. Entries MAL changed after the cursor go through the import merge: they fill gaps
// and move a status forward, never back, never out of dropped, never past a status set by hand.
// Aaru's own pushes come back equal to what it last agreed with MAL and are dropped.
type Puller struct {
	Store   *Store
	Connect *ConnectService
	Imports Applier
	API     *API
	Log     *slog.Logger
	Now     func() time.Time
}

func (p *Puller) now() time.Time {
	if p.Now != nil {
		return p.Now()
	}
	return time.Now()
}

func (p *Puller) log() *slog.Logger {
	if p.Log != nil {
		return p.Log
	}
	return slog.Default()
}

// RunOnce reads every connection due. It returns the titles added or updated.
func (p *Puller) RunOnce(ctx context.Context) (int, error) {
	started := p.now()
	due, err := p.Store.ClaimPulls(ctx, started, started.Add(-PullInterval), started.Add(-FullReadInterval), PullsPerPass)
	if err != nil {
		return 0, err
	}
	changed := 0
	for _, one := range due {
		n, err := p.Pull(ctx, one)
		if err != nil {
			if ctx.Err() != nil {
				return changed, ctx.Err()
			}
			// The cursor stays put: the next read sees these entries again.
			p.log().Warn("MyAnimeList read failed", "error", err.Error())
			continue
		}
		changed += n
	}
	return changed, nil
}

// Pull reads one connection's list and merges what changed.
func (p *Puller) Pull(ctx context.Context, due PullDue) (int, error) {
	started := p.now()
	applied, err := p.pull(ctx, due, started)
	if pe, ok := provider.AsError(err); ok && pe.Kind == provider.KindUnauthorized {
		return 0, p.Store.MarkRevoked(ctx, due.UserID, started)
	}
	return applied, err
}

func (p *Puller) pull(ctx context.Context, due PullDue, started time.Time) (int, error) {
	token, err := p.Connect.AccessToken(ctx, due.UserID)
	if err != nil {
		return 0, err
	}
	if token == nil {
		p.log().Info("MyAnimeList read skipped: no usable token")
		return 0, nil
	}
	entries, err := p.read(ctx, due, *token)
	if err != nil {
		return 0, err
	}
	var changed []ListEntry
	malIDs := []string{}
	for _, e := range entries {
		if e.ListStatus.UpdatedAt.After(due.Cursor) {
			changed = append(changed, e)
			malIDs = append(malIDs, strconv.Itoa(e.Node.ID))
		}
	}
	known, err := p.Store.EntryStates(ctx, due.UserID, malIDs)
	if err != nil {
		return 0, err
	}
	var fresh []ListEntry
	for _, e := range changed {
		state := StateOf(e)
		if state == nil {
			fresh = append(fresh, e)
			continue
		}
		if k, ok := known[state.MalID]; !ok || k != *state {
			fresh = append(fresh, e)
		}
	}
	rows := make([]imports.Row, len(fresh))
	for i, e := range fresh {
		rows[i] = RowOf(e)
	}
	planned, err := p.Imports.ApplyFromMAL(ctx, rows, due.UserID)
	if err != nil {
		return 0, err
	}
	applied := appliedCount(planned)
	p.logRead(due, len(entries), len(changed), planned)
	for _, e := range fresh {
		state := StateOf(e)
		if state == nil {
			continue
		}
		title := e.Node.Title
		if err := p.Store.SaveEntryState(ctx, *state, &title, due.UserID); err != nil {
			return 0, err
		}
	}
	if due.FullRead {
		listed := make([]string, len(entries))
		for i, e := range entries {
			listed[i] = strconv.Itoa(e.Node.ID)
		}
		if err := p.Store.MarkRemoved(ctx, due.UserID, listed, started); err != nil {
			return 0, err
		}
	}
	cursor := due.Cursor
	for i, e := range changed {
		if i == 0 || e.ListStatus.UpdatedAt.After(cursor) {
			cursor = e.ListStatus.UpdatedAt
		}
	}
	var fullReadAt *time.Time
	if due.FullRead {
		fullReadAt = &started
	}
	if err := p.Store.FinishPull(ctx, due.UserID, cursor, fullReadAt); err != nil {
		return 0, err
	}
	return applied, nil
}

func appliedCount(planned []imports.PlannedRow) int {
	n := 0
	for _, r := range planned {
		if r.Outcome == imports.OutcomeCreate || r.Outcome == imports.OutcomeUpdate {
			n++
		}
	}
	return n
}

// logRead says what one read saw and did, so a change on MAL that never reaches the library can be
// traced: counts always, and each entry that wrote nothing, by MAL id and outcome. No user, title
// or reason text: a reason can quote the title. `skip` means the merge found nothing to move
// forward; `unmatched`, no catalog title.
func (p *Puller) logRead(due PullDue, read, changed int, planned []imports.PlannedRow) {
	p.log().Info("MyAnimeList list read",
		"entries", strconv.Itoa(read), "changed", strconv.Itoa(changed), "fresh", strconv.Itoa(len(planned)),
		"applied", strconv.Itoa(appliedCount(planned)), "cursor", due.Cursor.UTC().Format(time.RFC3339),
		"full", strconv.FormatBool(due.FullRead))
	for _, r := range planned {
		if r.Outcome == imports.OutcomeSkip || r.Outcome == imports.OutcomeUnmatched {
			p.log().Info("MyAnimeList entry not applied", "mal", r.Row.IDs.MAL, "outcome", string(r.Outcome))
		}
	}
}

// read is the list newest change first, until the first entry not newer than the cursor; a full
// read takes every page.
func (p *Puller) read(ctx context.Context, due PullDue, token string) ([]ListEntry, error) {
	limit := PageSize
	if due.FullRead {
		limit = FullPageSize
	}
	var entries []ListEntry
	for len(entries) < MaxEntries {
		page, err := p.API.AnimeList(ctx, token, len(entries), limit)
		if err != nil {
			return nil, err
		}
		entries = append(entries, page.Data...)
		if page.Next == nil || len(page.Data) == 0 {
			break
		}
		if last := page.Data[len(page.Data)-1]; !due.FullRead && !last.ListStatus.UpdatedAt.After(due.Cursor) {
			break
		}
	}
	return entries, nil
}

// StateOf is the entry as MAL holds it, to compare with what Aaru last agreed. nil for a status
// Aaru does not know.
func StateOf(e ListEntry) *EntryState {
	if e.ListStatus.Status == nil {
		return nil
	}
	status, ok := ParseListStatus(*e.ListStatus.Status)
	if !ok {
		return nil
	}
	state := EntryState{MalID: strconv.Itoa(e.Node.ID), Status: status}
	if e.ListStatus.NumEpisodesWatched != nil {
		state.Episodes = *e.ListStatus.NumEpisodesWatched
	}
	if e.ListStatus.Score != nil {
		state.Score = *e.ListStatus.Score
	}
	return &state
}

// RowOf is the entry as an import row, read as IMP-013 reads MAL's export.
func RowOf(e ListEntry) imports.Row {
	node, list := e.Node, e.ListStatus
	isMovie := node.MediaType != nil && *node.MediaType == "movie"
	var status *core.LibraryStatus
	if list.Status != nil {
		status = animeStatus(strings.ReplaceAll(*list.Status, "_", ""))
	}
	var rating *float64
	if list.Score != nil && *list.Score >= 1 && *list.Score <= 10 {
		r := float64(*list.Score)
		rating = &r
	}
	watched := 0
	if list.NumEpisodesWatched != nil {
		watched = *list.NumEpisodesWatched
	}
	mediaType := core.MediaShow
	if isMovie {
		mediaType = core.MediaMovie
	}
	sourceKey := "mal:" + strconv.Itoa(node.ID)
	knowsOnHold := true
	return imports.Row{
		SourceKey:   &sourceKey,
		Type:        mediaType,
		Title:       node.Title,
		IDs:         core.ExternalIDs{MAL: strconv.Itoa(node.ID)},
		Status:      status,
		Rating:      rating,
		FinishedAt:  catalog.ParseDay(list.FinishDate),
		Lists:       []string{},
		Watched:     progress(watched, node.NumEpisodes, status, isMovie),
		KnowsOnHold: &knowsOnHold,
	}
}

// animeStatus is AnimeListImport.status: a MAL or AniList status, by name or MAL's number.
func animeStatus(value string) *core.LibraryStatus {
	var s core.LibraryStatus
	switch strings.ReplaceAll(strings.ToLower(value), " ", "") {
	case "watching", "reading", "1", "current", "repeating", "rereading":
		s = core.StatusInProgress
	case "on-hold", "onhold", "3", "paused":
		s = core.StatusOnHold
	case "completed", "2":
		s = core.StatusFinished
	case "dropped", "4":
		s = core.StatusDropped
	case "plantowatch", "plantoread", "6", "planning":
		s = core.StatusWishlist
	default:
		return nil
	}
	return &s
}

// progress is AnimeListImport.progress: episodes 1…n of season 1; a completed entry exported with
// 0 progress means every episode. A film has none.
func progress(watched int, total *int, status *core.LibraryStatus, isMovie bool) []core.EpisodeKey {
	if isMovie {
		return nil
	}
	count := watched
	if status != nil && *status == core.StatusFinished && watched == 0 {
		count = 0
		if total != nil {
			count = *total
		}
	}
	if count <= 0 {
		return nil
	}
	keys := make([]core.EpisodeKey, 0, count)
	for episode := 1; episode <= count; episode++ {
		if key, err := core.NewEpisodeKey(1, episode); err == nil {
			keys = append(keys, key)
		}
	}
	return keys
}
