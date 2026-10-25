import { kindOf, statusLabel } from './model'
import type { LibraryEntry, LibraryStatus, MediaKind } from './model'

// Only the Library page draws these, so they live apart from the model every route shares.

/** The Library's status tabs, MyAnimeList's way round (LIB-007): what you are in the middle of
 * first, then what is planned, paused, done and dropped. */
export const STATUS_TAB_ORDER: LibraryStatus[] = [
  'in_progress',
  'wishlist',
  'on_hold',
  'finished',
  'dropped',
]

export interface StatusTab {
  /** `null` is All. */
  status: LibraryStatus | null
  label: string
  count: number
}

/** The Library's tabs for this kind: All, then each status in tab order, worded for the kind and
 * counted over the whole library of that kind (not the name filter). Every tab shows, even at 0,
 * so the strip does not shift while the shelf changes under it. */
export function statusTabs(
  entries: LibraryEntry[],
  kind: MediaKind | null,
): StatusTab[] {
  const counts = new Map<LibraryStatus, number>()
  let all = 0
  for (const entry of entries) {
    if (kind && kindOf(entry.title.type, entry.title.isAnime) !== kind) continue
    all += 1
    counts.set(entry.status, (counts.get(entry.status) ?? 0) + 1)
  }
  return [
    { status: null, label: 'All', count: all },
    ...STATUS_TAB_ORDER.map((status) => ({
      status,
      label: statusLabel(status, kind),
      count: counts.get(status) ?? 0,
    })),
  ]
}
