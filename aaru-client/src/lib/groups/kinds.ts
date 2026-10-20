import type { components } from '../api/schema'
import { statusLabel } from '../library/model'

// GRP-007…GRP-009 on the web: the pure half of title, shelf and watch channels. The server
// decides what is veiled, who may start a party and when it starts; these only label, count
// down and turn the composer's choices into request fields.

export type ChannelKind = components['schemas']['ChannelKind']
export type SpoilerStamp = components['schemas']['SpoilerStamp']
export type MemberProgress = components['schemas']['MemberProgress']
export type WatchParty = components['schemas']['WatchParty']
export type MediaRef = components['schemas']['MediaRef']
export type CatalogHit = components['schemas']['CatalogHit']

export const KIND_OPTIONS: Array<{
  kind: ChannelKind
  label: string
  hint: string
}> = [
  { kind: 'text', label: 'Text', hint: 'Talk about anything.' },
  {
    kind: 'title',
    label: 'Title',
    hint: 'One film, show or book, with spoilers hidden from whoever is behind.',
  },
  {
    kind: 'watch',
    label: 'Watch party',
    hint: 'Pick an episode, count down together and react live.',
  },
  {
    kind: 'shelf',
    label: 'Shelf',
    hint: 'A list of titles everyone in the group can add to.',
  },
]

/** The glyph in front of a channel's name: `#` for chat, the rest by kind. */
export function kindGlyph(kind: ChannelKind): string {
  switch (kind) {
    case 'watch':
      return '▶'
    case 'shelf':
      return '▤'
    case 'title':
      return '◐'
    default:
      return '#'
  }
}

export function kindLabel(kind: ChannelKind): string {
  return KIND_OPTIONS.find((k) => k.kind === kind)?.label ?? 'Text'
}

// MARK: Spoilers

/** What the composer marks a message as, in a title channel. */
export type SpoilerChoice =
  | { mode: 'auto' }
  | { mode: 'free' }
  | { mode: 'ending' }
  | { mode: 'episode'; season: number; episode: number }

export const AUTO_SPOILER: SpoilerChoice = { mode: 'auto' }

/** The request fields for a choice: nothing for auto, so the server stamps my progress. */
export function spoilerFields(choice: SpoilerChoice): {
  spoiler?: SpoilerStamp
  spoilerFree?: boolean
} {
  switch (choice.mode) {
    case 'free':
      return { spoilerFree: true }
    case 'ending':
      return { spoiler: { ending: true } }
    case 'episode':
      return { spoiler: { season: choice.season, episode: choice.episode } }
    default:
      return {}
  }
}

/** The composer's chip: what this message will be marked as. */
export function spoilerChoiceLabel(choice: SpoilerChoice): string {
  switch (choice.mode) {
    case 'free':
      return 'No spoilers'
    case 'ending':
      return 'Spoils the ending'
    case 'episode':
      return `Spoils up to ${episodeCode(choice.season, choice.episode)}`
    default:
      return 'Marked at your progress'
  }
}

/** A hand-set episode is valid when both numbers are whole, the season ≥ 0, the episode ≥ 1. */
export function validEpisode(season: number, episode: number): boolean {
  return (
    Number.isInteger(season) &&
    Number.isInteger(episode) &&
    season >= 0 &&
    episode >= 1
  )
}

export function episodeCode(season: number, episode: number): string {
  return `S${season}E${episode}`
}

/** The small tag on my own stamped message: "S1E3", "Ending", or nothing. */
export function stampLabel(stamp?: SpoilerStamp): string | null {
  if (!stamp) return null
  if (stamp.ending) return 'Ending'
  if (stamp.season !== undefined && stamp.episode !== undefined)
    return episodeCode(stamp.season, stamp.episode)
  return null
}

/** Where someone is in a title: "S1E3", "Finished", "Wishlist", or "Not started". */
export function progressLabel(progress?: MemberProgress): string {
  if (!progress?.status) return 'Not started'
  if (progress.status === 'finished') return 'Finished'
  if (progress.season !== undefined && progress.episode !== undefined)
    return episodeCode(progress.season, progress.episode)
  return statusLabel(progress.status)
}

// MARK: Watch parties

/**
 * How far the server's clock is ahead of this device's, in ms, from a response's `serverTime`
 * and the local time it arrived. Counting against this keeps every client within a few hundred
 * milliseconds of each other however wrong their clocks are.
 */
export function serverOffset(serverTime: string, receivedAt: number): number {
  const server = Date.parse(serverTime)
  return Number.isNaN(server) ? 0 : server - receivedAt
}

/** Whole seconds left before `startsAt` on the server's clock; 0 once it has passed. */
export function countdownSeconds(
  startsAt: string,
  localNow: number,
  offset: number,
): number {
  const left = Date.parse(startsAt) - (localNow + offset)
  return left <= 0 ? 0 : Math.ceil(left / 1000)
}

export type PartyPhase = 'lobby' | 'countdown' | 'live' | 'ended'

/**
 * A party's phase now. The server's `state` was true when it answered; a countdown turns live
 * on its own, so that one is recomputed from `startsAt` and the server's clock.
 */
export function partyPhase(
  party: WatchParty,
  localNow: number,
  offset: number,
): PartyPhase {
  if (party.state === 'ended' || party.endedAt) return 'ended'
  if (!party.startsAt) return 'lobby'
  return countdownSeconds(party.startsAt, localNow, offset) > 0
    ? 'countdown'
    : 'live'
}

export function phaseLabel(phase: PartyPhase): string {
  switch (phase) {
    case 'lobby':
      return 'Waiting to start'
    case 'countdown':
      return 'Starting'
    case 'live':
      return 'Playing now'
    default:
      return 'Ended'
  }
}

/** The host, or an admin or owner, starts and ends a party. */
export function canHost(
  party: WatchParty,
  meId: string,
  role: 'owner' | 'admin' | 'member',
): boolean {
  return party.host?.userId === meId || role !== 'member'
}

export const COUNTDOWN_DEFAULT = 10
export const REACTIONS = ['😂', '😱', '😭', '❤️', '👏', '🔥'] as const
export const REACTION_INTERVAL_MS = 1000

/** Whether a reaction may go out now, given when the last one went. */
export function reactionDue(lastSent: number | undefined, now: number) {
  return lastSent === undefined || now - lastSent >= REACTION_INTERVAL_MS
}

// MARK: Titles

/** A search hit as the server's `MediaRef`: provider ids first, then title and year. */
export function hitRef(hit: CatalogHit): MediaRef {
  return { type: hit.type, ids: hit.ids, title: hit.title, year: hit.year }
}
