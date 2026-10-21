import type { components } from '../api/schema'

export type TitleDetail = components['schemas']['TitleDetail']
export type Season = components['schemas']['Season']
export type Episode = components['schemas']['Episode']
export type LibraryItemPatch = components['schemas']['LibraryItemPatch']

/** "season:number", the key a tick is stored under. */
export const episodeKey = (season: number, number: number) =>
  `${season}:${number}`

export function hasAired(episode: Episode, now: Date = new Date()): boolean {
  return !episode.airsAt || new Date(episode.airsAt) <= now
}

/** Every aired episode of one season: what "Mark watched" ticks. */
export function airedKeys(
  title: TitleDetail | undefined,
  season: number,
  now = new Date(),
) {
  const episodes =
    title?.seasons?.find((s) => s.number === season)?.episodes ?? []
  return episodes
    .filter((e) => hasAired(e, now))
    .map((e) => episodeKey(e.season, e.number))
}

/** Seasons in viewing order, specials (season 0) last. */
export function orderedSeasons(title: TitleDetail | undefined): Season[] {
  const rank = (n: number) => (n === 0 ? Number.MAX_SAFE_INTEGER : n)
  return [...(title?.seasons ?? [])].sort(
    (a, b) => rank(a.number) - rank(b.number),
  )
}

/** Five stars, two points each on the 1–10 scale. Choosing the current value clears it. */
export function nextRating(
  current: number | undefined,
  star: number,
): number | null {
  const value = star * 2
  return current === value ? null : value
}

/** The rating group's name with its value, as a screen reader reads it: "Rating, 8 of 10". */
export function ratingLabel(rating: number | undefined): string {
  return rating === undefined ? 'Rating, not rated' : `Rating, ${rating} of 10`
}

/** Every episode in viewing order: regular seasons ascending, then specials. */
export function orderedEpisodes(title: TitleDetail | undefined): Episode[] {
  return orderedSeasons(title).flatMap((season) => season.episodes)
}

/** The first aired, unwatched episode outside the specials: where the user picks up. */
export function nextEpisode(
  title: TitleDetail | undefined,
  watched: Set<string>,
  now = new Date(),
): Episode | undefined {
  return orderedEpisodes(title).find(
    (e) =>
      e.season > 0 &&
      hasAired(e, now) &&
      !watched.has(episodeKey(e.season, e.number)),
  )
}

export type CellState = 'watched' | 'next' | 'aired' | 'unaired'

/** One season map cell: watched wins, then the next episode, then whether it has aired. */
export function cellState(
  episode: Episode,
  watched: Set<string>,
  next: Episode | undefined,
  now = new Date(),
): CellState {
  if (watched.has(episodeKey(episode.season, episode.number))) return 'watched'
  if (next && next.season === episode.season && next.number === episode.number)
    return 'next'
  return hasAired(episode, now) ? 'aired' : 'unaired'
}

/** The episodes either side of one, in viewing order, for the episode sheet. */
export function neighbours(
  title: TitleDetail | undefined,
  season: number,
  number: number,
): { previous?: Episode; next?: Episode } {
  const all = orderedEpisodes(title)
  const index = all.findIndex((e) => e.season === season && e.number === number)
  if (index < 0) return {}
  return { previous: all[index - 1], next: all[index + 1] }
}

/** "12 Mar 2026", plus the time only when the catalog knows it. */
export function airLabel(episode: Episode): string | undefined {
  if (!episode.airsAt) return undefined
  const date = new Date(episode.airsAt)
  return date.toLocaleString(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    ...(episode.airTimeKnown ? { hour: 'numeric', minute: '2-digit' } : {}),
  })
}
