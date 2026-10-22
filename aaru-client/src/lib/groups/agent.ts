import type { components } from '../api/schema'
import { matchMembers } from './model'
import type { GroupMember, GroupMessage } from './server'

// GRP-011 on the web: the pure half of @aaru in a channel. The server decides when Aaru answers
// and what it may read; these only suggest the tag, track "thinking", and describe replies.

export type MessageComponent = components['schemas']['MessageComponent']

export const AGENT_HANDLE = 'aaru'
/** "Aaru is thinking…" gives up after this long, in case the answer never comes. */
export const THINKING_TTL_MS = 90_000
/** How much of the message an Aaru reply answers is quoted above it. */
export const REPLY_SNIPPET_LENGTH = 80

export type MentionSuggestion =
  { kind: 'agent' } | { kind: 'member'; member: GroupMember }

/**
 * Who to suggest for a partial `@` tag: Aaru first when it answers in this group and the tag
 * could be it, then members as `matchMembers` orders them.
 */
export function suggestMentions(
  members: GroupMember[],
  query: string,
  meId: string,
  agent: boolean,
  limit = 6,
): MentionSuggestion[] {
  const people: MentionSuggestion[] = matchMembers(
    members,
    query,
    meId,
    limit,
  ).map((member) => ({ kind: 'member', member }))
  if (!agent || !AGENT_HANDLE.startsWith(query.toLowerCase())) return people
  return [{ kind: 'agent' } as MentionSuggestion, ...people].slice(0, limit)
}

/** The handle a suggestion inserts. */
export function suggestionHandle(suggestion: MentionSuggestion): string {
  return suggestion.kind === 'agent'
    ? AGENT_HANDLE
    : suggestion.member.user.handle
}

/** A mention Aaru is answering, until `until` (epoch ms). */
export type Thinking = { mention: string; until: number }

/** Notes an `agent.thinking` frame; the same mention twice keeps one entry. */
export function noteThinking(
  list: Thinking[],
  mention: string,
  now: number,
): Thinking[] {
  return [
    ...list.filter((t) => t.mention !== mention),
    { mention, until: now + THINKING_TTL_MS },
  ]
}

/** Drops the mentions these messages answer, and anything that ran out of time. */
export function settleThinking(
  list: Thinking[],
  messages: GroupMessage[],
  now: number,
): Thinking[] {
  const answered = new Set(
    messages.filter((m) => m.fromAgent && m.replyTo).map((m) => m.replyTo),
  )
  const next = list.filter((t) => t.until > now && !answered.has(t.mention))
  return next.length === list.length ? list : next
}

/**
 * The line above an Aaru reply: who asked and the start of what they asked. Null when that
 * message is not loaded. A message the reader cannot see stays unseen here too.
 */
export function replySnippet(
  replyTo: string | undefined,
  messages: GroupMessage[],
): { who: string; text: string } | null {
  if (!replyTo) return null
  const target = messages.find((m) => m.id === replyTo)
  if (!target) return null
  const who = target.fromAgent
    ? 'Aaru'
    : target.author
      ? `@${target.author.handle}`
      : 'a deleted account'
  if (target.deleted) return { who, text: 'something deleted' }
  if (target.fromBlocked) return { who, text: 'something you hid' }
  if (target.veiled) return { who, text: 'something that may spoil' }
  const flat = target.body.replace(/\s+/g, ' ').trim()
  const text =
    flat.length > REPLY_SNIPPET_LENGTH
      ? `${flat.slice(0, REPLY_SNIPPET_LENGTH - 1).trimEnd()}…`
      : flat
  return { who, text }
}

/** The cards on a reply. Title cards are the only kind the server sends (VIEWS.md). */
export function agentCards(message: GroupMessage): MessageComponent[] {
  return message.components ?? []
}
