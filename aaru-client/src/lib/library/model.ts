import type { components } from '../api/schema'
import type { MediaType } from '../media'

export type LibraryEntry = components['schemas']['LibraryEntry']
export type LibraryStatus = components['schemas']['LibraryStatus']
export type CatalogHit = components['schemas']['CatalogHit']
export type ExternalIds = components['schemas']['ExternalIds']
export type SearchResults = components['schemas']['SearchResults']
/** `all` searches films, shows and anime together; books and albums are only ever searched on
 * their own. */
export const SEARCH_TYPES = [
  'all',
  'movie',
  'show',
  'anime',
  'book',
  'album',
  'manga',
] as const
export type SearchType = (typeof SEARCH_TYPES)[number]

/** How the library is browsed: anime is its own shelf even though it is a show or a film. */
export type MediaKind = 'film' | 'show' | 'anime' | 'manga' | 'book' | 'album'

export const KINDS: Array<{
  kind: MediaKind
  label: string
  search: SearchType
}> = [
  { kind: 'film', label: 'Films', search: 'movie' },
  { kind: 'show', label: 'Shows', search: 'show' },
  { kind: 'anime', label: 'Anime', search: 'anime' },
  { kind: 'manga', label: 'Manga', search: 'manga' },
  { kind: 'book', label: 'Books', search: 'book' },
  { kind: 'album', label: 'Music', search: 'album' },
]

const KIND_NAMES: Record<MediaKind, string> = {
  film: 'Film',
  show: 'Show',
  anime: 'Anime',
  manga: 'Manga',
  book: 'Book',
  album: 'Album',
}

/** One title's kind, singular: the badge on a search hit or a Discover card. */
export function kindName(kind: MediaKind): string {
  return KIND_NAMES[kind]
}

/** Stored order of the five statuses. The words differ per kind; the values never do. On hold
 * (LIB-007) sits beside in progress: a paused title, not a finished one. */
export const STATUS_ORDER: LibraryStatus[] = [
  'wishlist',
  'in_progress',
  'on_hold',
  'finished',
  'dropped',
]

const VIDEO_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Plan to watch',
  in_progress: 'Watching',
  on_hold: 'On hold',
  finished: 'Watched',
  dropped: 'Dropped',
}

const BOOK_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Plan to read',
  in_progress: 'Reading',
  on_hold: 'On hold',
  finished: 'Read',
  dropped: 'Dropped',
}

const LISTEN_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Plan to listen',
  in_progress: 'Listening',
  on_hold: 'On hold',
  finished: 'Listened',
  dropped: 'Dropped',
}

/** For a mixed shelf (no kind chosen), words that fit films and books alike. */
const NEUTRAL_LABELS: Record<LibraryStatus, string> = {
  wishlist: 'Planned',
  in_progress: 'In progress',
  on_hold: 'On hold',
  finished: 'Finished',
  dropped: 'Dropped',
}

function labelsFor(kind: MediaKind | null): Record<LibraryStatus, string> {
  if (kind === null) return NEUTRAL_LABELS
  if (kind === 'book' || kind === 'manga') return BOOK_LABELS
  if (kind === 'album') return LISTEN_LABELS
  return VIDEO_LABELS
}

/** What a status is called for this kind: "Watching" for a show, "Reading" for a book,
 * "Listening" for an album. */
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

export function kindOf(type: MediaType, isAnime: boolean): MediaKind {
  if (type === 'book') return 'book'
  if (type === 'album') return 'album'
  if (type === 'manga') return 'manga'
  if (isAnime) return 'anime'
  return type === 'movie' ? 'film' : 'show'
}

/** An album's cover is square (Cover Art Archive); every other kind's poster is 2:3. */
export function coverShape(kind: MediaKind): 'square' | 'poster' {
  return kind === 'album' ? 'square' : 'poster'
}

/** One library entry, ready to draw. Same shape as the Apple apps' `LibraryRow`. */
export interface LibraryRow {
  id: string
  title: string
  /** The title in its own language ("葬送のフリーレン"): the Library filter matches it too. */
  originalTitle?: string
  year?: number
  posterUrl?: string
  kind: MediaKind
  /** An album's artist (and a book's authors): the line under an album's name. */
  byline?: string
  status: LibraryStatus
  detail?: string
  updatedAt: string
}

/** Where a manga reader is (MNG-001): "Ch. 112 of 364 · Vol. 12", either part alone, or
 * undefined before they log any. */
export function mangaProgressLabel(entry: LibraryEntry): string | undefined {
  const chapter = entry.mangaProgress?.chapter
  const volume = entry.mangaProgress?.volume
  const parts: string[] = []
  if (chapter != null) {
    const total = entry.title.chapterCount
    parts.push(total ? `Ch. ${chapter} of ${total}` : `Ch. ${chapter}`)
  }
  if (volume != null) parts.push(`Vol. ${volume}`)
  return parts.length > 0 ? parts.join(' · ') : undefined
}

export function toRow(entry: LibraryEntry): LibraryRow {
  let detail: string | undefined
  if (entry.progress && entry.progress.airedCount > 0) {
    detail = `${entry.progress.watchedCount} of ${entry.progress.airedCount} episodes`
  } else if (entry.mangaProgress) {
    detail = mangaProgressLabel(entry)
  } else if (entry.bookProgress?.page != null) {
    detail = `Page ${entry.bookProgress.page}`
  } else if (entry.bookProgress?.percent != null) {
    detail = `${Math.round(entry.bookProgress.percent)}%`
  }
  return {
    id: entry.id,
    title: entry.title.title,
    originalTitle: entry.title.originalTitle,
    year: entry.title.year,
    posterUrl: entry.title.posterUrl,
    kind: kindOf(entry.title.type, entry.title.isAnime),
    byline: entry.title.byline,
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

/** One key per catalog hit: a provider key when there is one, so one title is one hit. */
export function hitKey(hit: CatalogHit): string {
  return idKeys(hit.ids).sort()[0] ?? `${hit.title}-${hit.year ?? ''}`
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
