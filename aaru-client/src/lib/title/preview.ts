import type { CatalogHit, ExternalIds } from '../library/model'
import type { MediaType } from '../media'

// LIB-006: any title opens a page, in the library or not. The page's address names the title by
// one provider id (`/app/catalog/show/tmdb/1399`), so a search hit, a Discover card and a list
// member link to it without a round trip; the page resolves it when it opens.

/** Tried in this order: the providers Aaru hydrates from first. */
export const PREVIEW_PROVIDERS = [
  'tmdb',
  'anilist',
  'mal',
  'openLibrary',
  'isbn',
  'musicbrainz',
  'imdb',
  'trakt',
  'tvdb',
  'anidb',
] as const satisfies readonly (keyof ExternalIds)[]
export type PreviewProvider = (typeof PREVIEW_PROVIDERS)[number]

export type PreviewParams = {
  type: MediaType
  provider: PreviewProvider
  ref: string
}

/** The page's params for a title, by the first provider id it has; null with none. */
export function previewParams(
  hit: Pick<CatalogHit, 'type' | 'ids'>,
): PreviewParams | null {
  const provider = PREVIEW_PROVIDERS.find((p) => hit.ids[p])
  const ref = provider ? hit.ids[provider] : undefined
  return provider && ref ? { type: hit.type, provider, ref } : null
}
