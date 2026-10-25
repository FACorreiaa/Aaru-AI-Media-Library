import type { components } from '../api/schema'

// MUS-003's pure part on the web: how a concert row reads, how a city is named, and the one
// thing the browser does to a position before it leaves (rounding). Dates are the venue's own
// `YYYY-MM-DD` and `HH:mm`, shown as they come: never moved into the viewer's timezone.

export type Concert = components['schemas']['Concert']
export type ConcertPage = components['schemas']['ConcertPage']
export type ArtistConcerts = components['schemas']['ArtistConcerts']
export type ConcertPlace = components['schemas']['ConcertPlace']
export type ConcertPlaceSetting = components['schemas']['ConcertPlaceSetting']
export type ConcertSearchPage = components['schemas']['ConcertSearchPage']
export type SearchScope = components['schemas']['ConcertSearchScope']
export type ConcertPerformer = components['schemas']['ConcertPerformer']
export type ConcertPerformerList = components['schemas']['ConcertPerformerList']

export const RADII = [25, 50, 100] as const
export type Radius = (typeof RADII)[number]
export const DEFAULT_RADIUS: Radius = 50

// Discover's view param lives in its own module: route options ship in the entry chunk.
export { DISCOVER_VIEWS, parseView, shownView } from './view'
export type { DiscoverView } from './view'
// How a city is named and searched, apart too: Settings needs only this much.
export { placeLabel, placeQuery } from './place'

const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
]
const MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
]
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const WEEKDAY_NAMES = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
]

export interface DateBlock {
  /** "24" */
  day: string
  /** "Oct", or "Jan 2027" when the concert falls in another year than today. */
  month: string
  /** "Fri" */
  weekday: string
  /** "Friday 24 October 2026", for screen readers. */
  label: string
}

/**
 * The ticket stub of a row, from the venue's `YYYY-MM-DD`. The weekday is worked out on the
 * calendar date itself (UTC noon), so no timezone can move it. Null for a date that is not one.
 */
export function dateBlock(localDate: string, today?: string): DateBlock | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(localDate)
  if (!match) return null
  const [year, month, day] = match.slice(1).map(Number)
  const date = new Date(Date.UTC(year, month - 1, day, 12))
  if (date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null
  const weekday = date.getUTCDay()
  const otherYear = today !== undefined && today.slice(0, 4) !== String(year)
  return {
    day: String(day),
    month: otherYear ? `${MONTHS[month - 1]} ${year}` : MONTHS[month - 1],
    weekday: WEEKDAYS[weekday],
    label: `${WEEKDAY_NAMES[weekday]} ${day} ${MONTH_NAMES[month - 1]} ${year}`,
  }
}

/** "Venue · City", whichever parts are known; null with neither. */
export function placeLine(concert: Concert): string | null {
  const parts = [concert.venue, concert.city].filter((part): part is string =>
    Boolean(part?.trim()),
  )
  return parts.length > 0 ? parts.join(' · ') : null
}

/** "3.4 km", "42 km" further out. */
export function distanceLabel(km: number): string {
  if (km < 10) {
    // The server sends tenths; a venue next door still reads as a distance.
    const tenths = Math.max(0.1, Math.round(km * 10) / 10)
    return `${Number.isInteger(tenths) ? tenths.toFixed(0) : tenths.toFixed(1)} km`
  }
  return `${Math.round(km)} km`
}

/** "3.4 km · 21:00", whichever parts are known; null with neither. */
export function detailLine(concert: Concert): string | null {
  const parts = [
    concert.distanceKm === undefined ? null : distanceLabel(concert.distanceKm),
    concert.localTime && /^\d{2}:\d{2}/.test(concert.localTime)
      ? concert.localTime.slice(0, 5)
      : null,
  ].filter((part): part is string => part !== null)
  return parts.length > 0 ? parts.join(' · ') : null
}

/** Two decimals, about a kilometre: all of a position that ever leaves the browser. */
export function roundCoordinate(value: number): number {
  return Math.round(value * 100) / 100
}

export function roundPosition(position: {
  latitude: number
  longitude: number
}): { latitude: number; longitude: number } {
  return {
    latitude: roundCoordinate(position.latitude),
    longitude: roundCoordinate(position.longitude),
  }
}

/** "Checking 3 artists — back within the hour.", or null when every artist was looked up. */
export function pendingLine(pending: number): string | null {
  if (pending <= 0) return null
  return `Checking ${pending} ${pending === 1 ? 'artist' : 'artists'} — back within the hour.`
}

/**
 * The quiet line under "Your artists on tour" when nothing is listed, or null with concerts.
 * No artist matched and none waiting means no albums whose artists Aaru could look for.
 */
export function artistsEmptyLine(found: ArtistConcerts): string | null {
  if (found.items.length > 0) return null
  const pending = pendingLine(found.pending)
  if (pending) return pending
  if (found.matched === 0)
    return 'No artists to look for yet. Albums you add bring their artists here.'
  return 'None of your artists are touring soon.'
}

/** The shortest artist name a search sends (MUS-010); the server refuses less. */
export const MIN_SEARCH = 2

/**
 * The "Near" section's heading while an artist is searched: "Radiohead near Lisbon",
 * "Radiohead near you" for a one-off position or no city, "Radiohead anywhere".
 */
export function searchHeading(
  query: string,
  scope: SearchScope,
  placeName: string | null,
): string {
  if (scope === 'anywhere') return `${query} anywhere`
  return `${query} near ${placeName ?? 'you'}`
}

/** The quiet line when a search by artist finds nothing. */
export function searchEmptyLine(
  query: string,
  scope: SearchScope,
  radiusKm: number | undefined,
): string {
  if (scope === 'anywhere' || radiusKm === undefined)
    return `No upcoming ${query} concerts listed.`
  return `No ${query} concerts within ${radiusKm} km.`
}
