import { kindOf, mangaProgressLabel } from './model'
import type { LibraryEntry, MediaKind } from './model'
import { GROUP_KINDS, NOW_GROUPS, groupTitle } from './now-groups'
import type { NowGroup } from './now-groups'

// APP-017: "Now" at the top of Library — what the user is in the middle of, grouped the way they
// would say it: watching, reading, listening. Derived from the shelf already loaded; nothing extra is
// fetched. Newest activity first.
// APP-018: each group has its own page, and anime the user never touched in Aaru (`inBacklog`, the
// server's rule) leave Watching for that page's Anime backlog.

export { GROUP_KINDS, NOW_GROUPS, groupTitle, isNowGroup } from './now-groups'
export type { NowGroup } from './now-groups'
export type { WatchingItem } from './watching'

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
  /** Anime in the backlog this group leaves out (Watching only). */
  backlogCount: number
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
  if (kind === 'manga') {
    const chapter = entry.mangaProgress?.chapter
    const total = entry.title.chapterCount
    return {
      entry,
      kind,
      done: chapter != null && total ? Math.min(1, chapter / total) : undefined,
      progressLabel: mangaProgressLabel(entry) ?? 'Just started',
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
        : 'Watching',
  }
}

/** When the user last moved it: their newest tick in Aaru, else the item's last change. */
export function recentKey(entry: LibraryEntry): string {
  return entry.lastWatchedAt ?? entry.updatedAt
}

const byRecent = (a: NowItem, b: NowItem) =>
  recentKey(b.entry).localeCompare(recentKey(a.entry))

/** In-progress items in their groups, newest first; empty groups left out. A chosen kind keeps
 *  only that kind. Backlog anime are counted, not listed. */
export function nowSections(
  entries: LibraryEntry[],
  kind?: MediaKind | null,
): NowSection[] {
  const active = entries
    .filter((entry) => entry.status === 'in_progress')
    .map(nowItem)
    .filter((item) => !kind || item.kind === kind)
    .sort(byRecent)
  return NOW_GROUPS.map((group) => {
    const all = active.filter((item) => GROUP_KINDS[group].includes(item.kind))
    const items = all.filter((item) => !item.entry.inBacklog)
    return {
      group,
      title: groupTitle(group),
      items,
      backlogCount: all.length - items.length,
    }
  }).filter((section) => section.items.length + section.backlogCount > 0)
}

export type NowSort = 'recent' | 'airs' | 'title'

/** One group's page: what the user keeps up with, and the anime backlog apart. */
export function groupItems(
  entries: LibraryEntry[],
  group: NowGroup,
  kind?: MediaKind | null,
): { active: NowItem[]; backlog: NowItem[] } {
  const all = entries
    .filter((entry) => entry.status === 'in_progress')
    .map(nowItem)
    .filter(
      (item) =>
        GROUP_KINDS[group].includes(item.kind) && (!kind || item.kind === kind),
    )
  return {
    active: all.filter((item) => !item.entry.inBacklog),
    backlog: all.filter((item) => item.entry.inBacklog),
  }
}

/** Recent first, the soonest next airing first (titles with none after, by recent), or A–Z. */
export function sortNow(
  items: NowItem[],
  sort: NowSort,
  airsAt: (item: NowItem) => string | undefined = () => undefined,
): NowItem[] {
  const sorted = [...items]
  if (sort === 'title')
    return sorted.sort((a, b) =>
      a.entry.title.title.localeCompare(b.entry.title.title),
    )
  if (sort === 'airs')
    return sorted.sort((a, b) => {
      const x = airsAt(a)
      const y = airsAt(b)
      if (x && y) return x.localeCompare(y)
      if (x) return -1
      if (y) return 1
      return byRecent(a, b)
    })
  return sorted.sort(byRecent)
}
