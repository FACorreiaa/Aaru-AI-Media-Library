import type { components } from '../api/schema'
import { airingBadge } from '../home/model'
import { idKeys, kindOf, toRow } from '../library/model'
import type { CatalogHit, LibraryStatus, MediaKind } from '../library/model'
import { episodeCode, showStatusLabel } from '../title/model'

export type ListItem = components['schemas']['ListItem']
export type ShowStatus = NonNullable<ListItem['showStatus']>

/** One list member, ready to draw (LST-003). Same shape as the Apple apps' `ListItemRow`. */
export interface ListRow {
  titleId: string
  /** Set when the title is in the library: the row then opens its title page. */
  libraryItemId?: string
  title: string
  year?: number
  posterUrl?: string
  kind: MediaKind
  /** An album's artist (and a book's authors). */
  byline?: string
  network?: string
  status?: LibraryStatus
  detail?: string
  showStatus?: string
  /** "S2 · E3 · Tomorrow"; just "S2 · E3" until the page knows the time. */
  airing?: string
  /** Set when the title is not in the library: what its Add control adds (UX-072). */
  hit?: CatalogHit
}

export function toListRow(item: ListItem, now: Date | null): ListRow {
  const library = item.entry ? toRow(item.entry) : undefined
  const next = item.nextAiring
  let airing: string | undefined
  if (next) {
    const episode = episodeCode(next.season, next.number)
    const when = now ? airingBadge(next, now) : null
    airing = when ? `${episode} · ${when}` : episode
  }
  return {
    titleId: item.title.id,
    libraryItemId: item.entry?.id,
    title: item.title.title,
    year: item.title.year,
    posterUrl: item.title.posterUrl,
    kind: kindOf(item.title.type, item.title.isAnime),
    byline: item.title.byline,
    network: item.title.network,
    status: library?.status,
    detail: library?.detail,
    showStatus: showStatusLabel(item.showStatus),
    airing,
    hit: item.entry
      ? undefined
      : {
          type: item.title.type,
          title: item.title.title,
          year: item.title.year,
          posterUrl: item.title.posterUrl,
          byline: item.title.byline,
          isAnime: item.title.isAnime,
          ids: item.title.ids,
        },
  }
}

/** "On this list" for a search hit: any provider id in common. */
export function isOnList(hit: CatalogHit, items: ListItem[]): boolean {
  const known = new Set(items.flatMap((i) => idKeys(i.title.ids)))
  return idKeys(hit.ids).some((key) => known.has(key))
}
