import type { components } from '../api/schema'
import type { PendingMessage } from '../groups/model'
import { mergeMessages } from '../groups/model'
import type { GroupMessage } from '../groups/server'

// GRP-006 on the web: the pure half of the realtime socket. The socket only announces; REST
// stays the source of truth, so everything here folds an event into what is already on screen.

export type RealtimeEvent = components['schemas']['RealtimeEvent']
export type SocialUser = components['schemas']['SocialUser']

/** The first reconnect waits about this long; each failure doubles it up to the cap. */
export const BACKOFF_BASE_MS = 1000
export const BACKOFF_CAP_MS = 30_000
/** One typing frame per channel this often; the server drops the rest anyway. */
export const TYPING_INTERVAL_MS = 3000
/** A typist disappears this long after their last frame. */
export const TYPING_TTL_MS = 5000
/** A hidden tab keeps its socket this long before closing it. */
export const HIDDEN_GRACE_MS = 60_000
/** "Reconnecting…" shows only after the socket has been down this long. */
export const STALE_AFTER_MS = 5000

const EVENT_TYPES = new Set<RealtimeEvent['type']>([
  'ready',
  'message.created',
  'message.updated',
  'message.deleted',
  'typing',
  'read',
  'group.updated',
  'group.removed',
  'invites.changed',
  'shelf.updated',
  'watch.updated',
  'watch.reaction',
])

/**
 * How long to wait before reconnect attempt `attempt` (0-based): exponential from 1 s, capped at
 * 30 s, with "equal jitter" (half fixed, half random) so many tabs do not reconnect in step.
 */
export function backoffDelay(
  attempt: number,
  random: () => number = Math.random,
): number {
  const ceiling = Math.min(
    BACKOFF_CAP_MS,
    BACKOFF_BASE_MS * 2 ** Math.max(0, attempt),
  )
  return Math.round(ceiling / 2 + random() * (ceiling / 2))
}

/** Whether a typing frame for a channel may go out now, given when the last one went. */
export function typingDue(lastSent: number | undefined, now: number): boolean {
  return lastSent === undefined || now - lastSent >= TYPING_INTERVAL_MS
}

/** One frame off the socket, or null for anything this client does not understand. */
export function parseEvent(text: string): RealtimeEvent | null {
  try {
    const value = JSON.parse(text) as unknown
    if (!value || typeof value !== 'object') return null
    const type = (value as { type?: unknown }).type
    if (typeof type !== 'string' || !EVENT_TYPES.has(type as never)) return null
    return value as RealtimeEvent
  } catch {
    return null
  }
}

/**
 * Folds a message event for the open channel into its list. Events for other channels, and
 * events that are not about messages, leave the list as it was (the same array).
 */
export function applyMessageEvent(
  messages: GroupMessage[],
  event: RealtimeEvent,
  channelId: string,
): GroupMessage[] {
  if (event.channelId !== channelId) return messages
  switch (event.type) {
    case 'message.created':
    case 'message.updated':
      return event.message ? mergeMessages(messages, [event.message]) : messages
    case 'message.deleted': {
      const target = messages.find((m) => m.id === event.messageId)
      if (!target || target.deleted) return messages
      return mergeMessages(messages, [
        { ...target, body: '', deleted: true, mentions: [] },
      ])
    }
    default:
      return messages
  }
}

/**
 * My own message can arrive over the socket before the POST that sent it answers. The server
 * returns my clientNonce on my own messages, so the pending copy it answers is exact; even a
 * copy marked failed goes, since the echo proves it was saved.
 */
export function settleEcho(
  pending: PendingMessage[],
  message: GroupMessage,
): PendingMessage[] {
  const nonce = message.clientNonce
  if (!nonce || !pending.some((p) => p.nonce === nonce)) return pending
  return pending.filter((p) => p.nonce !== nonce)
}

/** Someone typing in the open channel, until `until` (epoch ms). */
export type Typist = { user: SocialUser; until: number }

/** Notes a typing frame; the same person's newer frame extends their entry. */
export function noteTyping(
  typists: Typist[],
  user: SocialUser,
  now: number,
): Typist[] {
  return [
    ...typists.filter((t) => t.user.userId !== user.userId),
    { user, until: now + TYPING_TTL_MS },
  ]
}

/** Drops a typist (their message arrived) and anyone whose entry ran out. */
export function pruneTyping(
  typists: Typist[],
  now: number,
  sentBy?: string,
): Typist[] {
  return typists.filter((t) => t.until > now && t.user.userId !== sentBy)
}

/** The line above the composer, or null when nobody is typing. */
export function typingLine(typists: Typist[]): string | null {
  const names = typists.map((t) => t.user.displayName ?? `@${t.user.handle}`)
  if (names.length === 0) return null
  if (names.length === 1) return `${names[0]} is typing…`
  if (names.length === 2) return `${names[0]} and ${names[1]} are typing…`
  return 'Several people are typing…'
}
