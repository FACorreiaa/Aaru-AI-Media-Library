import { kindOf } from './model'
import type { LibraryEntry, MediaKind } from './model'

// APP-017: "Now" at the top of Library — what the user is in the middle of, grouped the way they
// would say it: watching, reading, listening. Derived from the shelf already loaded; nothing extra is
// fetched. Newest activity first.

export type NowGroup = 'watching' | 'reading' | 'listening'

export interface NowItem {
  entry: LibraryEntry
  kind: MediaKind
  /** 0…1 when the share done is known: episodes watched of aired, or a book's percent. */
  done?: number
  /** "4 of 10 episodes", "Page 120 of 412", "35%", or a film's runtime-free "In progress". */
  progressLabel: string
  /** The next episode to tick, for shows and anime. */
  next?: { season: number; number: number; label: string }
}

export interface NowSection {
  group: NowGroup
  title: string
  items: NowItem[]
}

const TITLES: Record<NowGroup, string> = {
  watching: 'Watching',
  reading: 'Reading',
  listening: 'Listening',
}

/** The kinds a group holds, so a kind chip narrows Now to its own group. */
export const GROUP_KINDS: Record<NowGroup, MediaKind[]> = {
  watching: ['film', 'show', 'anime'],
  reading: ['book'],
  listening: ['album'],
}

export function nowItem(entry: LibraryEntry): NowItem {
  const kind = kindOf(entry.title.type, entry.title.isAnime)
  const progress = entry.progress
  if (progress && progress.airedCount > 0) {
    const next = progress.nextEpisode
    return {
      entry,
      kind,
      done: Math.min(1, progress.watchedCount / progress.airedCount),
      progressLabel: `${progress.watchedCount} of ${progress.airedCount} episodes`,
      next: next
        ? {
            season: next.season,
            number: next.number,
            label: `S${next.season} · E${next.number}`,
          }
        : undefined,
    }
  }
  const book = entry.bookProgress
  if (book?.percent !== undefined) {
    return {
      entry,
      kind,
      done: Math.min(1, book.percent / 100),
      progressLabel: `${Math.round(book.percent)}%`,
    }
  }
  const pages = entry.title.pageCount
  if (book?.page !== undefined)
    return pages
      ? {
          entry,
          kind,
          done: Math.min(1, book.page / pages),
          progressLabel: `Page ${book.page} of ${pages}`,
        }
      : { entry, kind, progressLabel: `Page ${book.page}` }
  if (kind === 'album') return { entry, kind, progressLabel: 'Listening' }
  return {
    entry,
    kind,
    progressLabel:
      kind === 'book'
        ? pages
          ? `${pages} pages`
          : 'Just started'
        : 'In progress',
  }
}

/** In-progress items in their groups, newest change first; empty groups left out. A chosen kind
 *  keeps only that kind. */
export function nowSections(
  entries: LibraryEntry[],
  kind?: MediaKind | null,
): NowSection[] {
  const active = entries
    .filter((entry) => entry.status === 'in_progress')
    .map(nowItem)
    .filter((item) => !kind || item.kind === kind)
    .sort((a, b) => b.entry.updatedAt.localeCompare(a.entry.updatedAt))
  return (Object.keys(TITLES) as NowGroup[])
    .map((group) => ({
      group,
      title: TITLES[group],
      items: active.filter((item) => GROUP_KINDS[group].includes(item.kind)),
    }))
    .filter((section) => section.items.length > 0)
}
