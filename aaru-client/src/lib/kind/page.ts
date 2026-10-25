import { CREDITS } from '../credits'
import { shelf, statusLabel } from '../library/model'
import type { LibraryEntry, LibraryRow, LibraryStatus } from '../library/model'

// NAV-001: the Books, Manga and Music pages' pure part. Each is the user's shelf for one kind
// (In progress, then Planned, as short rows into Library) above that kind's public rows.

export type PageKind = 'book' | 'manga' | 'album'

/** How many titles a shelf row shows before "See all". */
export const SHELF_LIMIT = 12

/** In progress first, then Planned: the two shelves a kind page leads with. */
const SHELF_STATUSES: LibraryStatus[] = ['in_progress', 'wishlist']

export type KindShelf = {
  status: LibraryStatus
  /** "Reading", "Plan to read"; "Listening", "Plan to listen". */
  label: string
  /** Newest change first, at most `SHELF_LIMIT`. */
  rows: LibraryRow[]
  /** Every title with that status, for the count beside "See all". */
  total: number
}

/** The kind's two shelves, each possibly empty. */
export function kindShelves(
  entries: LibraryEntry[],
  kind: PageKind,
): KindShelf[] {
  return SHELF_STATUSES.map((status) => {
    const rows = shelf(entries, kind, status)
    return {
      status,
      label: statusLabel(status, kind),
      rows: rows.slice(0, SHELF_LIMIT),
      total: rows.length,
    }
  })
}

export type Source = { name: string; href: string }

const credit = (name: string): Source => ({
  name,
  href: CREDITS.find((c) => c.name === name)?.href ?? '',
})

/** UX-048: the credit names only the providers of the rows on the page. Concerts credit
 * Ticketmaster in their own section. */
export function kindSources(kind: PageKind): Source[] {
  if (kind === 'book') return [credit('Open Library')]
  if (kind === 'manga') return [credit('AniList')]
  return [
    credit('ListenBrainz'),
    credit('MusicBrainz'),
    credit('Cover Art Archive'),
  ]
}
