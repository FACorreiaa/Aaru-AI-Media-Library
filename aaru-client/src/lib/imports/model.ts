import type { components } from '../api/schema'

type ImportJob = components['schemas']['ImportJob']

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
  cat_list: 'Pogdesign CAT',
  cat_ics: 'Pogdesign CAT',
  mal_xml: 'MyAnimeList',
  anilist: 'AniList',
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
