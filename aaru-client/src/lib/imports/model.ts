import type { components } from '../api/schema'

type ImportJob = components['schemas']['ImportJob']

export const FILE_SOURCES = [
  {
    source: 'imdb',
    label: 'IMDb',
    hint: 'Your ratings or watchlist export (CSV).',
  },
  {
    source: 'letterboxd',
    label: 'Letterboxd',
    hint: 'diary.csv, ratings.csv, watched.csv or watchlist.csv from your export.',
  },
  {
    source: 'goodreads',
    label: 'Goodreads',
    hint: 'goodreads_library_export.csv. Custom shelves become lists.',
  },
] as const

const SOURCE_LABELS: Record<ImportJob['source'], string> = {
  imdb_csv: 'IMDb',
  letterboxd_csv: 'Letterboxd',
  goodreads_csv: 'Goodreads',
  trakt: 'Trakt',
  cat_list: 'Pogdesign CAT',
  cat_ics: 'Pogdesign CAT',
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
