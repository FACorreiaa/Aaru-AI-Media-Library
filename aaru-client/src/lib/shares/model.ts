import { placeLine as concertPlace } from '../concerts/model'
import { kindName, kindOf } from '../library/model'
import { SITE_URL } from '../site'
import { eventTitle, hasScore } from '../sports/model'
import type { components } from '../api/schema'

// SHR-002 on the web: the lines a share link's page and its link preview say. The page shows
// only what the API sent; the sender and note come from `from`, which only friends get.

export type SharePreview = components['schemas']['SharePreview']
export type ShareTarget = components['schemas']['ShareTargetInput']
export type ShareLink = components['schemas']['ShareLink']

export const DEFAULT_DESCRIPTION =
  'One private shelf for everything you watch and read.'

const DEFAULT_IMAGE = `${SITE_URL}/og.jpg`

const DAY_FORMAT = new Intl.DateTimeFormat('en-GB', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  timeZone: 'UTC',
})

/** What is shared, by name; null when the provider could not give it. */
export function shareName(preview: SharePreview): string | null {
  if (preview.unavailable) return null
  if (preview.title) return preview.title.title
  if (preview.sportEvent) return eventTitle(preview.sportEvent)
  if (preview.concert) return preview.concert.name
  return null
}

/** "2026-11-14" as "Sat 14 Nov 2026"; anything that is not a day comes back as it was. */
export function shareDate(day: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day)
  if (!match) return day
  const date = new Date(Date.UTC(+match[1], +match[2] - 1, +match[3]))
  if (Number.isNaN(date.getTime())) return day
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    DAY_FORMAT.formatToParts(date).find((p) => p.type === type)?.value
  return `${part('weekday')} ${part('day')} ${part('month')} ${part('year')}`
}

/** The link preview's line: kind and year, the score up front, or a concert's day and place. */
export function shareDescription(preview: SharePreview): string {
  if (preview.unavailable) return DEFAULT_DESCRIPTION
  const { title, sportEvent: event, concert } = preview
  let parts: Array<string | number | null | undefined> = []
  if (title)
    parts = [
      kindName(kindOf(title.type, title.isAnime)),
      title.year,
      title.byline,
    ]
  else if (event) {
    const scored = hasScore(event)
    parts = [
      scored
        ? `${event.home?.name} ${event.home?.score}–${event.away?.score} ${event.away?.name}`
        : eventTitle(event),
      event.status === 'live' ? 'Live' : null,
      event.league,
      scored ? null : shareDate(event.day),
    ]
  } else if (concert)
    parts = [shareDate(concert.localDate), concertPlace(concert)]
  const line = parts
    .filter((part) => part !== null && part !== undefined && `${part}`.trim())
    .join(' · ')
  return line || DEFAULT_DESCRIPTION
}

/** The link preview's image: the catalog's own, absolute https only, else Aaru's. */
export function shareImage(preview: SharePreview): string {
  if (preview.unavailable) return DEFAULT_IMAGE
  const event = preview.sportEvent
  const url =
    preview.title?.posterUrl ??
    (event
      ? (event.imageUrl ?? event.home?.badgeUrl ?? event.leagueBadgeUrl)
      : preview.concert?.imageUrl)
  return url?.startsWith('https://') ? url : DEFAULT_IMAGE
}

/** Where sign-in returns to, so the shared title is saved on the way back. */
export function addNext(code: string): string {
  return `/s/${code}?add=1`
}

/** Save the shared title on return from sign-in: once, and only when it is not already theirs. */
export function shouldAutoAdd(input: {
  add: boolean
  signedIn: boolean
  preview: SharePreview
}): boolean {
  const { add, signedIn, preview } = input
  return (
    add &&
    signedIn &&
    preview.kind === 'title' &&
    !preview.unavailable &&
    !!preview.title &&
    !preview.libraryItemId
  )
}
