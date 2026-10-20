import type { components } from '../api/schema'
import { airingBadge } from '../home/model'
import { idKeys, kindOf, toRow } from '../library/model'
import type { CatalogHit, LibraryStatus, MediaKind } from '../library/model'

export type ListItem = components['schemas']['ListItem']
export type ShowStatus = NonNullable<ListItem['showStatus']>

const SHOW_STATUS_LABELS: Record<ShowStatus, string> = {
  upcoming: 'Upcoming',
  returning: 'Returning',
  ended: 'Ended',
  canceled: 'Canceled',
}

/** One list member, ready to draw (LST-003). Same shape as the Apple apps' `ListItemRow`. */
export interface ListRow {
  titleId: string
  /** Set when the title is in the library: the row then opens its title page. */
  libraryItemId?: string
  title: string
  year?: number
  posterUrl?: string
  kind: MediaKind
  network?: string
  status?: LibraryStatus
  detail?: string
  showStatus?: string
  /** "S2E3 · Tomorrow"; just "S2E3" until the page knows the time. */
  airing?: string
}

export function toListRow(item: ListItem, now: Date | null): ListRow {
  const library = item.entry ? toRow(item.entry) : undefined
  const next = item.nextAiring
  let airing: string | undefined
  if (next) {
    const episode = `S${next.season}E${next.number}`
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
    network: item.title.network,
    status: library?.status,
    detail: library?.detail,
    showStatus: item.showStatus && SHOW_STATUS_LABELS[item.showStatus],
    airing,
  }
}

/** "On this list" for a search hit: any provider id in common. */
export function isOnList(hit: CatalogHit, items: ListItem[]): boolean {
  const known = new Set(items.flatMap((i) => idKeys(i.title.ids)))
  return idKeys(hit.ids).some((key) => known.has(key))
}
