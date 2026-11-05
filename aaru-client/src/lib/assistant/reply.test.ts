import { describe, expect, it } from 'vitest'
import {
  CUT_OFF,
  applyFrame,
  cancelReply,
  newReply,
  streamEnded,
  wrote,
} from './reply'
import type { TitleSummary } from './reply'

const title = (id: string) =>
  ({ id, title: id, type: 'movie' }) as unknown as TitleSummary

describe('chat reply', () => {
  it('builds the text and keeps each title once', () => {
    let reply = newReply()
    reply = applyFrame(reply, { type: 'status', text: 'Searching' })
    reply = applyFrame(reply, { type: 'delta', text: 'Here ' })
    reply = applyFrame(reply, { type: 'delta', text: 'they are.' })
    reply = applyFrame(reply, {
      type: 'components',
      components: { titles: [title('a'), title('b')] },
    })
    reply = applyFrame(reply, {
      type: 'components',
      components: { titles: [title('b')], importId: 'i1' },
    })
    expect(reply.text).toBe('Here they are.')
    expect(reply.status).toBeNull()
    expect(reply.titles.map((t) => t.id)).toEqual(['a', 'b'])
    expect(reply.importId).toBe('i1')
    expect(wrote(reply)).toBe(false)
  })

  it('ends once, and an applied change counts as a write', () => {
    let reply = applyFrame(newReply(), {
      type: 'components',
      components: { actionId: 'x' },
    })
    reply = applyFrame(reply, { type: 'done', turnId: 't' })
    expect(reply.state).toBe('answered')
    expect(applyFrame(reply, { type: 'delta', text: 'late' }).text).toBe('')
    expect(wrote(reply)).toBe(true)
  })

  it('says it was cut off when the stream closes early, and not after a cancel', () => {
    expect(streamEnded(newReply())).toMatchObject({
      state: 'cutOff',
      problem: CUT_OFF,
    })
    expect(streamEnded(cancelReply(newReply())).state).toBe('cancelled')
  })

  it('shows a refusal as stopped, not failed', () => {
    const reply = applyFrame(newReply(), {
      type: 'error',
      code: 'resting',
      message: 'Resting.',
    })
    expect(reply).toMatchObject({ state: 'stopped', problem: 'Resting.' })
  })
})
