import type { components } from '../api/schema'

type Listen = components['schemas']['Listen']
export type Scrobbler = components['schemas']['MusicScrobbler']

/** What Settings offers, in this order. Same list and text as the Apple app's `MusicSection`. */
export const SCROBBLERS = [
  'web_scrobbler',
  'pano_scrobbler',
  'navidrome',
  'jellyfin',
  'other',
] as const satisfies readonly Scrobbler[]

const LABELS: Record<Scrobbler, string> = {
  web_scrobbler: 'Web Scrobbler',
  pano_scrobbler: 'Pano Scrobbler',
  navidrome: 'Navidrome',
  jellyfin: 'Jellyfin',
  other: 'Other',
}

const SUMMARIES: Record<Scrobbler, string> = {
  web_scrobbler:
    'A browser extension for Chrome, Firefox, Edge and Safari. Covers YouTube, YouTube Music, Spotify and Apple Music in the browser.',
  pano_scrobbler:
    'An app for Android, Windows and Linux that sends whatever plays, Spotify and YouTube Music included.',
  navidrome:
    'Your own music server. Plays in Navidrome and the apps connected to it are sent.',
  jellyfin:
    'The ListenBrainz plugin sends what you play on your Jellyfin server.',
  other: 'Anything that lets you set its ListenBrainz server.',
}

export const scrobblerLabel = (scrobbler: Scrobbler) => LABELS[scrobbler]
export const scrobblerSummary = (scrobbler: Scrobbler) => SUMMARIES[scrobbler]

/** "Sabotage — Beastie Boys". */
export const listenTitle = (listen: Listen) =>
  `${listen.track} — ${listen.artist}`

/** "3 min ago · Web Scrobbler · YouTube Music": when, then what sent it and where it played. */
export function listenDetail(listen: Listen, now = new Date()): string {
  return [
    ago(new Date(listen.listenedAt), now),
    listen.client,
    listen.musicService,
  ]
    .filter(Boolean)
    .join(' · ')
}

function ago(date: Date, now: Date): string {
  const minutes = Math.round((now.getTime() - date.getTime()) / 60_000)
  if (minutes < 1) return 'Just now'
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return hours === 1 ? '1 hour ago' : `${hours} hours ago`
  const days = Math.round(hours / 24)
  return days === 1 ? 'Yesterday' : `${days} days ago`
}

/** How long Settings waits for the first listen after connecting, and how often it looks. */
export const FIRST_LISTEN_WAIT_MS = 10 * 60_000
export const FIRST_LISTEN_POLL_MS = 5_000

/** A listen that arrived after `seen`, the newest one when the scrobbler was connected. */
export const isNewListen = (seen: Listen | null, latest: Listen | null) =>
  latest !== null && latest.id !== seen?.id
