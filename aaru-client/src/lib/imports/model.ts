import type { components } from '../api/schema'

type ImportJob = components['schemas']['ImportJob']

export const FILE_SOURCES = [
  {
    source: 'auto',
    label: 'Any site',
    hint: 'A CSV from any site (Simkl, Serializd, StoryGraph, a spreadsheet) or MAL-format XML (MyAnimeList, Kitsu, AniList). Aaru reads the columns.',
    accept:
      '.csv,.xml,.gz,text/csv,text/plain,application/xml,text/xml,application/gzip',
  },
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
    source: 'mal',
    label: 'MyAnimeList',
    hint: 'MAL → Profile → Export → Anime list. The .xml.gz file as downloaded.',
    accept: '.xml,.gz,application/xml,text/xml,application/gzip',
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
  mal_xml: 'MyAnimeList',
  anilist: 'AniList',
  csv: 'CSV',
}

export const sourceLabel = (job: ImportJob) => SOURCE_LABELS[job.source]

export function stateLabel(job: ImportJob): string {
  switch (job.state) {
    case 'queued':
      return 'Waiting'
    case 'running':
      return 'Matching titles…'
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
