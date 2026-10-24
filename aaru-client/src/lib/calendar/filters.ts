import type { CalendarEntry } from './model'

// CAL-002: what the calendar shows. Filters work on the entries already loaded, so changing
// one never waits on the network; they live in the URL so a view can be shared or reloaded.

export type CalendarView = 'week' | 'month' | 'missed'
export type OnlyFilter = 'premieres' | 'finales'
export type KindFilter = 'show' | 'anime'
/** CAL-005: how Week and Month lay out their episodes. Day when unset. */
export type CalendarGroup = 'channel'

export interface CalendarFilter {
  hideWatched: boolean
  only?: OnlyFilter
  kind?: KindFilter
  /** A layout, not a filter: it hides nothing, so `activeCount` leaves it out. */
  group?: CalendarGroup
}

export const NO_FILTER: CalendarFilter = { hideWatched: false }

/** How many filters are on, for the toolbar's badge. The grouping is not one. */
export const activeCount = (filter: CalendarFilter) =>
  (filter.hideWatched ? 1 : 0) + (filter.only ? 1 : 0) + (filter.kind ? 1 : 0)

export function matches(entry: CalendarEntry, filter: CalendarFilter): boolean {
  if (filter.hideWatched && entry.watched) return false
  if (filter.only === 'premieres' && entry.kind !== 'premiere') return false
  if (filter.only === 'finales' && entry.kind !== 'finale') return false
  if (filter.kind === 'anime' && !entry.title.isAnime) return false
  if (filter.kind === 'show' && entry.title.isAnime) return false
  return true
}

export const applyFilter = (
  entries: CalendarEntry[],
  filter: CalendarFilter,
) =>
  activeCount(filter) === 0
    ? entries
    : entries.filter((entry) => matches(entry, filter))

/** The days the Missed view looks back over: one request, under the 42-day limit. */
export const MISSED_DAYS = 28

export interface MissedShow {
  libraryItemId: string
  title: CalendarEntry['title']
  /** Oldest first: the order to catch up in. */
  episodes: CalendarEntry[]
}

/** Aired and not watched, one group per show, the show with the oldest miss first. */
export function catchUp(entries: CalendarEntry[], now: Date): MissedShow[] {
  const shows = new Map<string, MissedShow>()
  const aired = entries
    .filter((entry) => !entry.watched && new Date(entry.airsAt) <= now)
    .sort(
      (a, b) =>
        a.airsAt.localeCompare(b.airsAt) ||
        a.season - b.season ||
        a.number - b.number,
    )
  for (const entry of aired) {
    const show = shows.get(entry.libraryItemId) ?? {
      libraryItemId: entry.libraryItemId,
      title: entry.title,
      episodes: [],
    }
    show.episodes.push(entry)
    shows.set(entry.libraryItemId, show)
  }
  return [...shows.values()]
}

/** "3 episodes · 2 h 15 min" for a show's missed episodes, the time when every runtime is known. */
export function missedLine(show: MissedShow): string {
  const count = show.episodes.length
  const parts = [`${count} episode${count === 1 ? '' : 's'}`]
  const minutes = show.episodes.map((entry) => entry.runtimeMinutes)
  if (minutes.every((value): value is number => value !== undefined)) {
    const total = minutes.reduce((sum, value) => sum + value, 0)
    const hours = Math.floor(total / 60)
    const rest = total % 60
    parts.push(hours > 0 ? `${hours} h ${rest} min` : `${rest} min`)
  }
  return parts.join(' · ')
}
