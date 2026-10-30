package core

import (
	"slices"
	"time"

	"github.com/google/uuid"
)

// ImportSource is where an import's rows came from.
//
// The declaration order (ImportSources) is the merge order: when a user connects
// several sources, apply them in this order and let later sources fill only
// empty fields.
type ImportSource string

// The import sources, in merge order.
const (
	SourceTrakt ImportSource = "trakt"
	// SourceStremio is a Stremio account's library and watch history, read once through a link code (IMP-016).
	SourceStremio       ImportSource = "stremio"
	SourceIMDbCSV       ImportSource = "imdb_csv"
	SourceLetterboxdCSV ImportSource = "letterboxd_csv"
	SourceGoodreadsCSV  ImportSource = "goodreads_csv"
	SourceCATList       ImportSource = "cat_list"
	SourceCATICS        ImportSource = "cat_ics"
	// SourceNetflixCSV is Netflix's viewing activity download, one profile (IMP-018). Names only,
	// so after every source that carries ids.
	SourceNetflixCSV ImportSource = "netflix_csv"
	// SourceTVTimeCSV is one CSV from TV Time's export, the in-app one or the GDPR one (IMP-012).
	SourceTVTimeCSV ImportSource = "tvtime_csv"
	// SourceMALXML is MyAnimeList's XML list export (IMP-013).
	SourceMALXML ImportSource = "mal_xml"
	// SourceAniList is a public AniList list, read by username (IMP-014).
	SourceAniList ImportSource = "anilist"
	// SourceGenericCSV is any other site's CSV, read by its column names. Last in the merge
	// order: it fills gaps only.
	SourceGenericCSV ImportSource = "csv"
	// SourceCapture is a one-shot capture (AG-006): pasted text, a screenshot, or a catalog link.
	// Not part of the merge order: the user asks for it, and it never reconciles a connected source.
	SourceCapture ImportSource = "capture"
	// SourceLastFM and the three after it are past listening (MUS-004). These fill the listening log, never the library, so they are in
	// no merge order.
	SourceLastFM         ImportSource = "lastfm"
	SourceListenBrainz   ImportSource = "listenbrainz"
	SourceSpotifyJSON    ImportSource = "spotify_json"
	SourceYouTubeTakeout ImportSource = "youtube_takeout"
)

// ImportSources are every source, in merge order.
var ImportSources = []ImportSource{
	SourceTrakt, SourceStremio, SourceIMDbCSV, SourceLetterboxdCSV, SourceGoodreadsCSV, SourceCATList, SourceCATICS,
	SourceNetflixCSV, SourceTVTimeCSV, SourceMALXML, SourceAniList, SourceGenericCSV, SourceCapture,
	SourceLastFM, SourceListenBrainz, SourceSpotifyJSON, SourceYouTubeTakeout,
}

// Valid reports whether s is a known source.
func (s ImportSource) Valid() bool { return slices.Contains(ImportSources, s) }

// MergeRank is the position in the merge order, lowest first.
func (s ImportSource) MergeRank() int {
	if i := slices.Index(ImportSources, s); i >= 0 {
		return i
	}
	return len(ImportSources)
}

// IsListens is whether the import brings listens (MUS-004) rather than library rows.
func (s ImportSource) IsListens() bool {
	switch s {
	case SourceLastFM, SourceListenBrainz, SourceSpotifyJSON, SourceYouTubeTakeout:
		return true
	}
	return false
}

// ImportJobState is the lifecycle of one import run.
type ImportJobState string

// The import job states.
const (
	JobQueued  ImportJobState = "queued"
	JobRunning ImportJobState = "running"
	// JobPlanned means rows are matched and a plan is ready; nothing is written until the user approves it.
	JobPlanned   ImportJobState = "planned"
	JobSucceeded ImportJobState = "succeeded"
	JobFailed    ImportJobState = "failed"
	// JobPartial is finished, but some rows could not be matched.
	JobPartial ImportJobState = "partial"
)

// ImportJobStates are every state, in declaration order.
var ImportJobStates = []ImportJobState{JobQueued, JobRunning, JobPlanned, JobSucceeded, JobFailed, JobPartial}

// IsTerminal is true once the run is over (a plan still waits for approval).
func (s ImportJobState) IsTerminal() bool {
	switch s {
	case JobSucceeded, JobFailed, JobPartial:
		return true
	}
	return false
}

// ImportStats is what an import run did. Unmatched rows are counted, never silently dropped.
//
// A listening import (MUS-004) counts new listens as created, listens already in the
// log as skipped, and plays it left out by rule as ignored. Stats stored before
// `ignored` existed decode with none.
type ImportStats struct {
	Created   int `json:"created"`
	Updated   int `json:"updated"`
	Skipped   int `json:"skipped"`
	Unmatched int `json:"unmatched"`
	Ignored   int `json:"ignored"`
}

// Total is every row counted, ignored ones aside.
func (s ImportStats) Total() int { return s.Created + s.Updated + s.Skipped + s.Unmatched }

// ImportJob is one run of a Trakt, CSV, or CAT ingest, or of a listening-history import.
//
// Imports are one-way into Aaru. Re-running an import updates in place via
// (user, title); it does not duplicate items.
type ImportJob struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	Source       ImportSource
	State        ImportJobState
	Stats        ImportStats
	ErrorSummary *string
	// Filename is the uploaded file's name, for file imports. The file itself is never kept.
	Filename  *string
	CreatedAt time.Time
	UpdatedAt time.Time
	// RowsTotal and RowsMatched are the rows read, and how many the worker has matched so far.
	RowsTotal   int
	RowsMatched int
	// ActionID is the journaled action that applied the plan, so a client can offer Undo.
	ActionID *uuid.UUID
}
