import type { components } from '../api/schema'

export type LibraryEntry = components['schemas']['LibraryEntry']
export type LibraryStatus = components['schemas']['LibraryStatus']
export type CatalogHit = components['schemas']['CatalogHit']
export type ExternalIds = components['schemas']['ExternalIds']
export type SearchResults = components['schemas']['SearchResults']
/** `all` searches films, shows and anime together; books are only ever searched on their own. */
export type SearchType = 'all' | 'movie' | 'show' | 'anime' | 'book'

/** How the library is browsed: anime is its own shelf even though it is a show or a film. */
export type MediaKind = 'film' | 'show' | 'anime' | 'book'

export const KINDS: Array<{
  kind: MediaKind
  label: string
  search: SearchType
}> = [
  { kind: 'film', label: 'Films', search: 'movie' },
  { kind: 'show', label: 'Shows', search: 'show' },
  { kind: 'anime', label: 'Anime', search: 'anime' },
  { kind: 'book', label: 'Books', search: 'book' },
]

/** Stored order of the four statuses. The words differ per kind; the values never do. */
const KIND_NAMES: Record<MediaKind, string> = {
  film: 'Film',
  show: 'Show',
  anime: 'Anime',
  book: 'Book',
}

/** One title's kind, singular: the badge on a search hit or a Discover card. */
export function kindName(kind: MediaKind): string {
  return KIND_NAMES[kind]
}

export const STATUS_ORDER: LibraryStatus[] = [
  'wishlist',
  'in_progress',
  'finished',
  'dropped',
]

const VIDEO_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Plan to watch',
  in_progress: 'Watching',
  finished: 'Watched',
  dropped: 'Dropped',
}

const BOOK_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Plan to read',
  in_progress: 'Reading',
  finished: 'Read',
  dropped: 'Dropped',
}

/** For a mixed shelf (no kind chosen), words that fit films and books alike. */
const NEUTRAL_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Planned',
  in_progress: 'In progress',
  finished: 'Finished',
  dropped: 'Dropped',
}

function labelsFor(kind: MediaKind | null): Record<LibraryStatus, string> {
  if (kind === null) return NEUTRAL_LABELS
  return kind === 'book' ? BOOK_LABELS : VIDEO_LABELS
}

/** What a status is called for this kind: "Watching" for a show, "Reading" for a book. */
export function statusLabel(
  status: LibraryStatus,
  kind: MediaKind | null,
): string {
  return labelsFor(kind)[status]
}

/** Every status in stored order, labelled for this kind: menus and filters. */
export function statusOptions(
  kind: MediaKind | null,
): Array<{ status: LibraryStatus; label: string }> {
  const labels = labelsFor(kind)
  return STATUS_ORDER.map((status) => ({ status, label: labels[status] }))
}

export function kindOf(
  type: 'movie' | 'show' | 'book',
  isAnime: boolean,
): MediaKind {
  if (type === 'book') return 'book'
  if (isAnime) return 'anime'
  return type === 'movie' ? 'film' : 'show'
}

/** One library entry, ready to draw. Same shape as the Apple apps' `LibraryRow`. */
export interface LibraryRow {
  id: string
  title: string
  year?: number
  posterUrl?: string
  kind: MediaKind
  status: LibraryStatus
  detail?: string
  updatedAt: string
}

export function toRow(entry: LibraryEntry): LibraryRow {
  let detail: string | undefined
  if (entry.progress && entry.progress.airedCount > 0) {
    detail = `${entry.progress.watchedCount} of ${entry.progress.airedCount} episodes`
  } else if (entry.bookProgress?.page != null) {
    detail = `Page ${entry.bookProgress.page}`
  } else if (entry.bookProgress?.percent != null) {
    detail = `${Math.round(entry.bookProgress.percent)}%`
  }
  return {
    id: entry.id,
    title: entry.title.title,
    year: entry.title.year,
    posterUrl: entry.title.posterUrl,
    kind: kindOf(entry.title.type, entry.title.isAnime),
    status: entry.status,
    detail,
    updatedAt: entry.updatedAt,
  }
}

/** Newest change first, then filtered: what the shelf shows. */
export function shelf(
  entries: LibraryEntry[],
  kind: MediaKind | null,
  status: LibraryStatus | null,
): LibraryRow[] {
  return entries
    .map(toRow)
    .filter(
      (row) =>
        (!kind || row.kind === kind) && (!status || row.status === status),
    )
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
}

/** Provider keys that identify one title, for "already on your shelf" on search hits. */
export function idKeys(ids: ExternalIds): string[] {
  return Object.entries(ids)
    .filter(([, value]) => typeof value === 'string' && value.length > 0)
    .map(([name, value]) => `${name}:${value}`)
}

export function isOnShelf(hit: CatalogHit, entries: LibraryEntry[]): boolean {
  const known = new Set(entries.flatMap((e) => idKeys(e.title.ids)))
  return idKeys(hit.ids).some((key) => known.has(key))
}

/** Replaces an entry by id or adds it: an add from search shows at once, no refetch. */
export function upsert(
  entries: LibraryEntry[],
  entry: LibraryEntry,
): LibraryEntry[] {
  return [entry, ...entries.filter((e) => e.id !== entry.id)]
}
