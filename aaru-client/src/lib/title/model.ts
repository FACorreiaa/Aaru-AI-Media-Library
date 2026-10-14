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
