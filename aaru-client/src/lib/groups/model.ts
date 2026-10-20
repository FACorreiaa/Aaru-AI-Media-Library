import type { GroupMember, GroupMessage } from './server'

// GRP-004/005 on the web: the pure shape of a channel. The server decides who may say what;
// these only lay messages out, find mentions, and keep optimistic sends in step with polls.

/** A run by one author holds together this long. */
export const RUN_WINDOW_MS = 5 * 60 * 1000
export const MAX_MESSAGE_LENGTH = 4000

/** A message typed here that the server has not confirmed yet. */
export type PendingMessage = {
  nonce: string
  body: string
  createdAt: string
  state: 'sending' | 'failed'
  /** Title channels: how it is marked, kept so a retry sends the same. */
  spoiler?: { season?: number; episode?: number; ending?: boolean }
  spoilerFree?: boolean
}

export type TimelineItem =
  | { kind: 'day'; key: string; date: string }
  | { kind: 'new' }
  | { kind: 'message'; message: GroupMessage; startsRun: boolean }
  | { kind: 'pending'; pending: PendingMessage; startsRun: boolean }

/** The local calendar day of a timestamp, as `YYYY-MM-DD`. */
export function dayKey(iso: string): string {
  const date = new Date(iso)
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

/** "Today", "Yesterday", else the weekday and date (with the year when it is not this one). */
export function dayLabel(iso: string, now: Date = new Date()): string {
  const key = dayKey(iso)
  if (key === dayKey(now.toISOString())) return 'Today'
  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  if (key === dayKey(yesterday.toISOString())) return 'Yesterday'
  const date = new Date(iso)
  return date.toLocaleDateString(undefined, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  })
}

/** "14:05", in the reader's locale. */
export function timeLabel(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  })
}

/**
 * Where the "New" line goes: before the oldest of the last `unread` messages from someone else.
 * `unread` is the channel's count when it was opened. Returns an index into `messages`, or -1.
 */
export function newLineIndex(
  messages: GroupMessage[],
  unread: number,
  meId: string,
): number {
  if (unread <= 0) return -1
  let seen = 0
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i]
    if (message.deleted || message.author?.userId === meId) continue
    seen += 1
    if (seen === unread) return i
  }
  // More unread than loaded: the line sits above everything shown.
  return seen > 0 ? 0 : -1
}

function authorOf(item: TimelineItem, meId: string): string | null {
  if (item.kind === 'message') return item.message.author?.userId ?? null
  if (item.kind === 'pending') return meId
  return null
}

function timeOf(item: TimelineItem): number {
  if (item.kind === 'message') return Date.parse(item.message.createdAt)
  if (item.kind === 'pending') return Date.parse(item.pending.createdAt)
  return 0
}

/**
 * Messages laid out for reading: day dividers, the "New" line, and runs. A message starts a run
 * unless the one right above it is by the same author, within five minutes, with no divider or
 * "New" line between. A deleted account never continues a run.
 */
export function buildTimeline(
  messages: GroupMessage[],
  pending: PendingMessage[],
  options: { meId: string; newLineAt?: number },
): TimelineItem[] {
  const items: TimelineItem[] = []
  let previous: TimelineItem | null = null
  let lastDay = ''

  const push = (item: TimelineItem & { startsRun: boolean }, iso: string) => {
    const day = dayKey(iso)
    if (day !== lastDay) {
      items.push({ kind: 'day', key: day, date: iso })
      lastDay = day
      previous = null
    }
    const author = authorOf(item, options.meId)
    const prior: TimelineItem | null = previous
    item.startsRun = !(
      prior !== null &&
      author !== null &&
      authorOf(prior, options.meId) === author &&
      timeOf(item) - timeOf(prior) <= RUN_WINDOW_MS
    )
    items.push(item)
    previous = item
  }

  messages.forEach((message, index) => {
    if (index === options.newLineAt) {
      items.push({ kind: 'new' })
      previous = null
    }
    push({ kind: 'message', message, startsRun: true }, message.createdAt)
  })
  for (const send of pending) {
    push({ kind: 'pending', pending: send, startsRun: true }, send.createdAt)
  }
  return items
}

/**
 * A fetched page folded into what is shown: one row per id (the newer copy wins, so edits and
 * deletes land), oldest first.
 */
export function mergeMessages(
  current: GroupMessage[],
  incoming: GroupMessage[],
): GroupMessage[] {
  const byId = new Map(current.map((m) => [m.id, m]))
  for (const message of incoming) byId.set(message.id, message)
  // Timestamps arrive in whole seconds, so ties keep the order they came in (the server's
  // order): the sort is stable, and an id tie-break would scramble same-second messages.
  return [...byId.values()].sort(
    (a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt),
  )
}

/** Drops the optimistic copy once the server has answered for its nonce. */
export function settlePending(
  pending: PendingMessage[],
  nonce: string,
): PendingMessage[] {
  return pending.filter((p) => p.nonce !== nonce)
}

/** Marks a send as failed so it can be retried. */
export function failPending(
  pending: PendingMessage[],
  nonce: string,
): PendingMessage[] {
  return pending.map((p) =>
    p.nonce === nonce ? { ...p, state: 'failed' as const } : p,
  )
}

export function retryPending(
  pending: PendingMessage[],
  nonce: string,
): PendingMessage[] {
  return pending.map((p) =>
    p.nonce === nonce ? { ...p, state: 'sending' as const } : p,
  )
}

export type BodySegment =
  | { kind: 'text'; text: string }
  | { kind: 'mention'; text: string; handle: string; me: boolean }

const MENTION = /@([A-Za-z0-9_]{3,20})/g
const HANDLE_CHAR = /[\p{L}\p{N}_@]/u

/**
 * A message body cut into text and mentions, the same way the server reads tags: `@handle` not
 * inside a word or an email address. Only members (and Aaru) are highlighted.
 */
export function splitMentions(
  body: string,
  handles: ReadonlySet<string>,
  myHandle?: string,
): BodySegment[] {
  const segments: BodySegment[] = []
  let cursor = 0
  for (const match of body.matchAll(MENTION)) {
    const start = match.index
    const end = start + match[0].length
    const before = start > 0 ? body[start - 1] : ''
    const after = end < body.length ? body[end] : ''
    if (HANDLE_CHAR.test(before) || HANDLE_CHAR.test(after)) continue
    const handle = match[1].toLowerCase()
    if (handle !== 'aaru' && !handles.has(handle)) continue
    if (start > cursor)
      segments.push({ kind: 'text', text: body.slice(cursor, start) })
    segments.push({
      kind: 'mention',
      text: match[0],
      handle,
      me: myHandle !== undefined && handle === myHandle,
    })
    cursor = end
  }
  if (cursor < body.length)
    segments.push({ kind: 'text', text: body.slice(cursor) })
  return segments
}

/** The `@` word being typed at the caret, or null when the caret is not in one. */
export function mentionQuery(
  text: string,
  caret: number,
): { start: number; query: string } | null {
  const upto = text.slice(0, caret)
  const at = upto.lastIndexOf('@')
  if (at < 0) return null
  const query = upto.slice(at + 1)
  if (!/^[A-Za-z0-9_]{0,20}$/.test(query)) return null
  if (at > 0 && HANDLE_CHAR.test(upto[at - 1])) return null
  return { start: at, query: query.toLowerCase() }
}

/** Members to suggest for a partial tag: handle prefix first, then name or handle contains. */
export function matchMembers(
  members: GroupMember[],
  query: string,
  meId: string,
  limit = 6,
): GroupMember[] {
  const q = query.toLowerCase()
  const others = members.filter((m) => m.user.userId !== meId)
  const prefix = others.filter((m) => m.user.handle.startsWith(q))
  const contains = others.filter(
    (m) =>
      !m.user.handle.startsWith(q) &&
      (m.user.handle.includes(q) ||
        (m.user.displayName ?? '').toLowerCase().includes(q)),
  )
  return [...prefix, ...contains].slice(0, limit)
}

/** The text with the partial tag replaced by `@handle `, and where the caret goes. */
export function applyMention(
  text: string,
  start: number,
  caret: number,
  handle: string,
): { text: string; caret: number } {
  const insert = `@${handle} `
  return {
    text: text.slice(0, start) + insert + text.slice(caret),
    caret: start + insert.length,
  }
}

/** Badge text for a count: nothing at zero, "99+" past 99. */
export function badgeText(count: number): string {
  if (count <= 0) return ''
  return count > 99 ? '99+' : String(count)
}

/** One or two letters for a group's monogram. */
export function groupMonogram(name: string): string {
  const words = name.split(/\s+/).filter(Boolean)
  if (words.length === 0) return '?'
  if (words.length === 1) return [...words[0]][0].toUpperCase()
  return ([...words[0]][0] + [...words[1]][0]).toUpperCase()
}

/** How many characters are left, shown only near the limit. */
export function remainingLabel(body: string): string | null {
  const left = MAX_MESSAGE_LENGTH - body.length
  return left <= 200 ? String(left) : null
}

/** Members by role, the way the member list shows them. */
export function membersByRole(members: GroupMember[]): {
  owner: GroupMember[]
  admins: GroupMember[]
  members: GroupMember[]
} {
  const byHandle = (a: GroupMember, b: GroupMember) =>
    a.user.handle.localeCompare(b.user.handle)
  return {
    owner: members.filter((m) => m.role === 'owner'),
    admins: members.filter((m) => m.role === 'admin').sort(byHandle),
    members: members.filter((m) => m.role === 'member').sort(byHandle),
  }
}
