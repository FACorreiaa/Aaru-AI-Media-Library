import type { DiscoverRow } from '../home/model'

// DISC-004 / NAV-001: the rows carry their kind, and each page shows only its own. Discover's
// Today keeps films, shows and anime; Books, Manga and Music show theirs; Home shows them all.
// Rows are filtered on `kind`, never on id prefixes.

export type RowKind = DiscoverRow['kind']

/** The kinds Discover's Today shows. Books, manga and albums live on their own pages. */
export const TODAY_KINDS: readonly RowKind[] = ['film', 'show', 'anime']

/** The rows of these kinds, in the server's order. */
export function rowsOfKinds(
  rows: DiscoverRow[],
  kinds: readonly RowKind[],
): DiscoverRow[] {
  return rows.filter((row) => kinds.includes(row.kind))
}
