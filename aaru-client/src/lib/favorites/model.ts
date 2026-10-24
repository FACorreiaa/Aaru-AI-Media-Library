import type { components } from '../api/schema'
import { KINDS } from '../library/model'

// FAV-001: an ordered top 10 per kind, any catalog title. Profile data, not the library.

export type Favorites = components['schemas']['Favorites']
export type FavoriteKind = components['schemas']['FavoriteKind']
type TitleSummary = components['schemas']['TitleSummary']
type MediaRef = components['schemas']['MediaRef']

export const FAVORITE_KINDS = [
  'film',
  'show',
  'anime',
  'manga',
  'book',
  'album',
] as const satisfies readonly FavoriteKind[]

export const FAVORITE_LIMIT = 10

/** The library's kind labels ("Films", "Music"), in the library's order. */
export function favoriteLabel(kind: FavoriteKind): string {
  return KINDS.find((k) => k.kind === kind)?.label ?? kind
}

/** Kinds with at least one favorite, in the library's order: what a profile shows. */
export function favoriteRows(
  favorites: Favorites | undefined,
): Array<{ kind: FavoriteKind; label: string; titles: TitleSummary[] }> {
  if (!favorites) return []
  return FAVORITE_KINDS.filter((kind) => favorites[kind].length > 0).map(
    (kind) => ({ kind, label: favoriteLabel(kind), titles: favorites[kind] }),
  )
}

/** A saved favorite as the server's `MediaRef`: by Aaru id, which it always has. */
export function favoriteRef(title: TitleSummary): MediaRef {
  return { titleId: title.id, type: title.type }
}

/** Moves one title up (`-1`) or down (`1`); a move past either end changes nothing. */
export function moveFavorite<T>(titles: T[], index: number, by: -1 | 1): T[] {
  const to = index + by
  if (index < 0 || index >= titles.length || to < 0 || to >= titles.length)
    return titles
  const next = [...titles]
  const [moved] = next.splice(index, 1)
  next.splice(to, 0, moved)
  return next
}
