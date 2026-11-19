import type { components } from '../api/schema'
import type { ChatComponents, ChatFrame } from './frames'

// What one Chat turn's answer looks like so far (AaruAPI's ChatReply, on the web). Pure: once the
// reply has ended, later frames change nothing.

export type TitleSummary = components['schemas']['TitleSummary']
export type AgentPlan = components['schemas']['AgentPlan']
export type ChatRoadmap = components['schemas']['ChatRoadmap']
export type ChatSource = components['schemas']['ChatSource']
export type StoredTurn = components['schemas']['ChatTurn']

export type ReplyState =
  'working' | 'answered' | 'stopped' | 'cutOff' | 'cancelled' | 'failed'

export type Reply = {
  text: string
  status: string | null
  titles: TitleSummary[]
  plan: AgentPlan | null
  /** A list Aaru sent to be matched (BOOK-003), reviewed like any capture. */
  importId: string | null
  /** That list as Aaru named it, in its steps (ASK-011). */
  roadmap: ChatRoadmap | null
  actionId: string | null
  actionSummary: string | null
  /** The web pages the answer cites (ASK-004): shown under it, never read aloud. */
  sources: ChatSource[]
  state: ReplyState
  problem: string | null
}

export const CUT_OFF = 'That answer was cut off. Ask again.'

export function newReply(): Reply {
  return {
    text: '',
    status: null,
    titles: [],
    plan: null,
    importId: null,
    roadmap: null,
    actionId: null,
    actionSummary: null,
    sources: [],
    state: 'working',
    problem: null,
  }
}

export function applyFrame(reply: Reply, frame: ChatFrame): Reply {
  if (reply.state !== 'working') return reply
  switch (frame.type) {
    case 'status':
      return { ...reply, status: frame.text }
    case 'delta':
      return { ...reply, text: reply.text + frame.text, status: null }
    case 'components':
      return merge(reply, frame.components)
    case 'done':
      return { ...reply, status: null, state: 'answered' }
    case 'error':
      return {
        ...reply,
        status: null,
        problem: frame.message,
        state: 'stopped',
      }
  }
  // Not reachable by the types. A frame from a newer server changes nothing.
  frame satisfies never
  return reply
}

function merge(reply: Reply, parts: ChatComponents): Reply {
  const titles = [...reply.titles]
  for (const title of parts.titles ?? []) {
    if (!titles.some((t) => t.id === title.id)) titles.push(title)
  }
  return {
    ...reply,
    titles,
    plan: parts.plan ?? reply.plan,
    importId: parts.importId ?? reply.importId,
    roadmap: parts.roadmap ?? reply.roadmap,
    actionId: parts.actionId ?? reply.actionId,
    actionSummary: parts.actionSummary ?? reply.actionSummary,
    sources: parts.sources ?? reply.sources,
  }
}

/** A cited page's link and the site it is on; null for anything but http(s), which is never linked. */
export function sourceLink(
  source: ChatSource,
): { href: string; site: string } | null {
  try {
    const url = new URL(source.url)
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null
    return { href: url.href, site: url.hostname.replace(/^www\./, '') }
  } catch {
    return null
  }
}

export const STOPPED_EARLY = 'This answer was stopped before it finished.'
export const DID_NOT_FINISH = 'Aaru could not finish this answer.'

/** A stored agent turn as the reply it was, for a chat opened from history (ASK-011). */
export function replyFromStored(turn: StoredTurn): Reply {
  const reply = merge({ ...newReply(), text: turn.body }, turn.components ?? {})
  switch (turn.state) {
    case 'done':
      return { ...reply, state: 'answered' }
    case 'failed':
      return { ...reply, state: 'failed', problem: DID_NOT_FINISH }
    default:
      // `stopped`, and a `streaming` turn read while another device is still asking.
      return { ...reply, state: 'cancelled', problem: STOPPED_EARLY }
  }
}

export type StoredExchange = {
  question: string
  reply: Reply
}

/** A stored chat's turns as question-and-answer pairs, oldest first. */
export function exchangesOf(turns: StoredTurn[]): StoredExchange[] {
  const out: StoredExchange[] = []
  let question: string | null = null
  for (const turn of turns) {
    if (turn.role === 'user') {
      // A question whose answer was never stored still shows.
      if (question !== null)
        out.push({ question, reply: { ...newReply(), state: 'cancelled' } })
      question = turn.body
      continue
    }
    out.push({ question: question ?? '', reply: replyFromStored(turn) })
    question = null
  }
  if (question !== null)
    out.push({ question, reply: { ...newReply(), state: 'cancelled' } })
  return out
}

/** The stream closed. Without a `done` or `error` first, the answer was cut off. */
export function streamEnded(reply: Reply): Reply {
  if (reply.state !== 'working') return reply
  return { ...reply, status: null, problem: CUT_OFF, state: 'cutOff' }
}

/** The card closed. What was written stays; a write already applied stays journaled. */
export function cancelReply(reply: Reply): Reply {
  if (reply.state !== 'working') return reply
  return { ...reply, status: null, state: 'cancelled' }
}

export function failReply(reply: Reply, problem: string): Reply {
  if (reply.state !== 'working') return reply
  return { ...reply, status: null, problem, state: 'failed' }
}

/** Whether the turn changed the library, so the page behind loads again. */
export function wrote(reply: Reply): boolean {
  return reply.actionId !== null || reply.plan !== null
}
