import type { components } from '../api/schema'
import type { ChatComponents, ChatFrame } from './frames'

// What one Chat turn's answer looks like so far (AaruAPI's ChatReply, on the web). Pure: once the
// reply has ended, later frames change nothing.

export type TitleSummary = components['schemas']['TitleSummary']
export type AgentPlan = components['schemas']['AgentPlan']

export type ReplyState =
  'working' | 'answered' | 'stopped' | 'cutOff' | 'cancelled' | 'failed'

export type Reply = {
  text: string
  status: string | null
  titles: TitleSummary[]
  plan: AgentPlan | null
  /** A list Aaru sent to be matched (BOOK-003), reviewed like any capture. */
  importId: string | null
  actionId: string | null
  actionSummary: string | null
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
    actionId: null,
    actionSummary: null,
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
    actionId: parts.actionId ?? reply.actionId,
    actionSummary: parts.actionSummary ?? reply.actionSummary,
  }
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
