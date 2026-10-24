// LIB-005: Library, Lists and Discover show 20 at a time, and their filter searches every item,
// not only the page in view. Both run on what the page already holds (the synced library, a
// list's members, Discover's rows), so neither asks the server again.

export const PAGE_SIZE = 20

/** Lowercased, accents and punctuation folded away: "Pokémon: XY" and "pokemon xy" match. */
export function fold(text: string): string {
  return text
    .normalize('NFKD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}]+/gu, ' ')
    .trim()
}

/** True when every word of `query` starts a word of one of `fields` ("fri" finds "Frieren").
 *  An empty query matches everything. */
export function matches(
  query: string,
  ...fields: (string | null | undefined)[]
): boolean {
  const words = fold(query).split(' ').filter(Boolean)
  if (words.length === 0) return true
  const haystack = fields
    .filter((f): f is string => Boolean(f))
    .flatMap((f) => fold(f).split(' '))
  return words.every((word) => haystack.some((w) => w.startsWith(word)))
}

export function pageCount(total: number): number {
  return Math.max(1, Math.ceil(total / PAGE_SIZE))
}

/** A page number that exists for `total` items: a filter that shrinks the list never strands
 *  the reader on an empty page 7. */
export function clampPage(page: number | undefined, total: number): number {
  return Math.min(Math.max(1, page ?? 1), pageCount(total))
}

/** The items on `page` (1-based). */
export function pageOf<T>(items: T[], page: number): T[] {
  const start = (clampPage(page, items.length) - 1) * PAGE_SIZE
  return items.slice(start, start + PAGE_SIZE)
}
