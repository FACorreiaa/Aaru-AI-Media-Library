import type { components } from '../api/schema'

type ImportJob = components['schemas']['ImportJob']

// CLAUDE.md's import order (UX-026). Trakt, Stremio history, Pogdesign CAT and AniList are
// their own forms on Import; these are the file sources between them, "Any other CSV" last.
export const FILE_SOURCES = [
  {
    source: 'imdb',
    label: 'IMDb',
    hint: 'Your ratings or watchlist export (CSV).',
    accept: '.csv,text/csv,text/plain',
  },
  {
    source: 'letterboxd',
    label: 'Letterboxd',
    hint: 'diary.csv, ratings.csv, watched.csv or watchlist.csv from your export.',
    accept: '.csv,text/csv,text/plain',
  },
  {
    source: 'goodreads',
    label: 'Goodreads',
    hint: 'goodreads_library_export.csv. Custom shelves become lists.',
    accept: '.csv,text/csv,text/plain',
  },
  {
    source: 'netflix',
    label: 'Netflix',
    hint: 'Account → Profile → Viewing activity → Download all. One profile per file.',
    accept: '.csv,text/csv,text/plain',
  },
  {
    source: 'tvtime',
    label: 'TV Time',
    hint: 'Unzip your TV Time export, then upload one CSV at a time: tvtime-series-episodes.csv, tvtime-series.csv and tvtime-movies.csv, or from a GDPR export tracking-prod-records-v2.csv and tracking-prod-records.csv.',
    accept: '.csv,text/csv,text/plain',
  },
  {
    source: 'mal',
    label: 'MyAnimeList',
    hint: 'MAL → Profile → Export → Anime list. The .xml.gz file as downloaded.',
    accept: '.xml,.gz,application/xml,text/xml,application/gzip',
  },
  {
    source: 'auto',
    label: 'Any other CSV',
    hint: 'A CSV from any other site, or a spreadsheet. Aaru reads the columns.',
    accept:
      '.csv,.xml,.gz,text/csv,text/plain,application/xml,text/xml,application/gzip',
  },
] as const

const SOURCE_LABELS: Record<ImportJob['source'], string> = {
  imdb_csv: 'IMDb',
  letterboxd_csv: 'Letterboxd',
  goodreads_csv: 'Goodreads',
  trakt: 'Trakt',
  stremio: 'Stremio',
  cat_list: 'Pogdesign CAT',
  cat_ics: 'Pogdesign CAT',
  netflix_csv: 'Netflix',
  tvtime_csv: 'TV Time',
  mal_xml: 'MyAnimeList',
  anilist: 'AniList',
  csv: 'CSV',
}

export const sourceLabel = (job: ImportJob) => SOURCE_LABELS[job.source]

export function stateLabel(job: ImportJob): string {
  switch (job.state) {
    case 'queued':
      return job.errorSummary ? 'Paused, retrying soon' : 'In line'
    case 'running': {
      const share = progressShare(job)
      return share === null
        ? 'Matching titles…'
        : `Matching titles… ${Math.floor(share * 100)}%`
    }
    case 'planned':
      return 'Ready to review'
    case 'succeeded':
      return 'Imported'
    case 'partial':
      return `Imported, ${job.stats.unmatched} unmatched`
    case 'failed':
      return 'Failed'
  }
}

/** 0…1 of the rows matched while running; null before the rows are known. */
export function progressShare(job: ImportJob): number | null {
  if (job.state !== 'running' || job.rowsTotal === 0) return null
  return Math.min(1, job.rowsMatched / job.rowsTotal)
}

/** One row of a working import's ledger (DESIGN §3, IMP-017): a step, not a spinner. */
export interface ImportStep {
  label: string
  detail?: string
  state: 'done' | 'current' | 'todo'
  /** 0…1 on the matching step while it runs; absent elsewhere. */
  progress?: number
}

const count = (n: number) => n.toLocaleString('en')

/** Sources whose rows the worker reads from an account, not from an upload. */
const READ_BY_WORKER: ReadonlyArray<ImportJob['source']> = ['trakt', 'anilist']

/** The steps of a queued or running import, in order; empty once it has a plan or an end. */
export function importSteps(job: ImportJob): ImportStep[] {
  if (!isWorking(job)) return []
  const source = sourceLabel(job)
  const running = job.state === 'running'
  const known = job.rowsTotal > 0
  const entries = `${count(job.rowsTotal)} ${job.rowsTotal === 1 ? 'entry' : 'entries'}`
  const fromAccount = READ_BY_WORKER.includes(job.source)
  const matching = running && known && job.rowsMatched < job.rowsTotal
  const checking = running && known && job.rowsMatched >= job.rowsTotal
  return [
    {
      label: fromAccount ? `Read your ${source} library` : 'Read your file',
      detail: known ? entries : undefined,
      state: known ? 'done' : running ? 'current' : 'todo',
    },
    {
      label: 'Wait for a free slot',
      detail: running
        ? undefined
        : job.errorSummary
          ? `Paused: ${job.errorSummary} Trying again shortly; nothing is lost.`
          : 'Starts in a few seconds.',
      state: running ? 'done' : 'current',
    },
    {
      label: 'Match each title to the catalog',
      detail: matching
        ? `${count(job.rowsMatched)} of ${count(job.rowsTotal)}`
        : checking
          ? `All ${entries}`
          : undefined,
      state: checking ? 'done' : matching ? 'current' : 'todo',
      progress: matching ? job.rowsMatched / job.rowsTotal : undefined,
    },
    {
      label: 'Check against your library',
      state: checking ? 'current' : 'todo',
    },
    {
      label: 'Ready for you to review',
      detail: 'Nothing is added until you approve.',
      state: 'todo',
    },
  ]
}

/** Still changing on the server: the page polls until it is not. */
export const isWorking = (job: ImportJob) =>
  job.state === 'queued' || job.state === 'running'

/** What Trakt's redirect back (`?trakt=`) means, in words; null for anything else. */
export function traktResult(
  value: string | undefined,
): { ok: boolean; message: string } | null {
  switch (value) {
    case 'connected':
      return {
        ok: true,
        message: 'Trakt is connected. Import when you are ready.',
      }
    case 'denied':
      return {
        ok: false,
        message: 'Trakt was not connected: access was declined.',
      }
    case 'failed':
      return {
        ok: false,
        message:
          'Trakt could not finish connecting. Free Trakt accounts can connect two apps; disconnect one on trakt.tv, or try again.',
      }
    default:
      return null
  }
}
