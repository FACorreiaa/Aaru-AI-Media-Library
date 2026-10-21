import type { Listen, TopRow } from './listening'

// MUS-008: how listens and top rows read, the same on the Apple apps.

export const TOP_BY = [
  { by: 'artist', label: 'Artists' },
  { by: 'track', label: 'Tracks' },
  { by: 'album', label: 'Albums' },
] as const

export type TopBy = (typeof TOP_BY)[number]['by']

/** "Teardrop", with "Massive Attack" under it; an artist row has no second line. */
export function topRowLines(row: TopRow, by: TopBy): [string, string?] {
  if (by === 'track') return [row.track ?? row.artist, row.artist]
  if (by === 'album') return [row.album ?? row.artist, row.artist]
  return [row.artist]
}

export const playsLabel = (count: number) =>
  `${count.toLocaleString('en')} play${count === 1 ? '' : 's'}`

/** "Massive Attack · Mezzanine", or where it played when the album is unknown. */
export function listenSubtitle(listen: Listen): string {
  return [listen.artist, listen.album ?? listen.musicService]
    .filter(Boolean)
    .join(' · ')
}

/** Today / Yesterday / "Mon, Oct 19" / "Oct 19, 2025", in the viewer's time zone. */
export function dayHeading(day: Date, now: Date): string {
  const start = (d: Date) =>
    new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const days = Math.round((start(now) - start(day)) / 86_400_000)
  if (days === 0) return 'Today'
  if (days === 1) return 'Yesterday'
  return day.toLocaleDateString('en', {
    weekday: day.getFullYear() === now.getFullYear() ? 'short' : undefined,
    month: 'short',
    day: 'numeric',
    year: day.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  })
}

/** Listens under their local day, newest first. */
export function byDay(
  listens: Listen[],
  now: Date,
): Array<{ heading: string; listens: Listen[] }> {
  const groups: Array<{ heading: string; listens: Listen[] }> = []
  for (const listen of listens) {
    const heading = dayHeading(new Date(listen.listenedAt), now)
    const last = groups.at(-1)
    if (last?.heading === heading) last.listens.push(listen)
    else groups.push({ heading, listens: [listen] })
  }
  return groups
}

export const timeOfDay = (listen: Listen) =>
  new Date(listen.listenedAt).toLocaleTimeString('en', {
    hour: 'numeric',
    minute: '2-digit',
  })
