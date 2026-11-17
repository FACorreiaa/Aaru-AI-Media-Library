import type { components } from '../api/schema'
import type { MediaKind } from '../library/model'

// CAT-014: where a film or show can be watched in the viewer's region, as the server lists it
// (JustWatch data through TMDB). Aaru links out and plays nothing: there is one link per title,
// TMDB's page, never one per service.

export type TitleWatch = components['schemas']['TitleWatch']
export type WatchService = components['schemas']['WatchProvider']

export type WatchGroup = {
  kind: 'stream' | 'rent' | 'buy'
  label: string
  services: WatchService[]
}

/** The groups that have a service, streaming first. Empty: the section is not shown. */
export function watchGroups(
  places: TitleWatch | null | undefined,
): WatchGroup[] {
  if (!places) return []
  const groups: WatchGroup[] = [
    { kind: 'stream', label: 'Stream', services: places.streaming },
    { kind: 'rent', label: 'Rent', services: places.rent },
    { kind: 'buy', label: 'Buy', services: places.buy },
  ]
  return groups.filter((g) => g.services.length > 0)
}

/** Only films, shows and anime are watched; a viewer with no region asks nothing. */
export function asksWhereToWatch(
  kind: MediaKind,
  region: string | undefined,
): region is string {
  return (
    region !== undefined &&
    (kind === 'film' || kind === 'show' || kind === 'anime')
  )
}
