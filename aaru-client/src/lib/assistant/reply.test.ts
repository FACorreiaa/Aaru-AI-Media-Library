import { describe, expect, it } from 'vitest'
import {
  CUT_OFF,
  DID_NOT_FINISH,
  STOPPED_EARLY,
  applyFrame,
  cancelReply,
  exchangesOf,
  newReply,
  replyFromStored,
  streamEnded,
  wrote,
} from './reply'
import type { StoredTurn, TitleSummary } from './reply'

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

  it('keeps the roadmap a turn planned beside its import', () => {
    const reply = applyFrame(newReply(), {
      type: 'components',
      components: {
        importId: 'i1',
        roadmap: {
          listName: 'Before Secret Wars',
          steps: [{ heading: 'One', items: [{ title: 'Loki', type: 'show' }] }],
        },
      },
    })
    expect(reply.importId).toBe('i1')
    expect(reply.roadmap?.listName).toBe('Before Secret Wars')
    expect(reply.roadmap?.steps[0]?.items[0]?.title).toBe('Loki')
  })
})

const stored = (turn: Partial<StoredTurn>): StoredTurn => ({
  id: 't',
  role: 'agent',
  body: '',
  state: 'done',
  createdAt: '2026-11-10T10:00:00Z',
  ...turn,
})

describe('a chat read back from history', () => {
  it('shows a stored answer as it was, with what it carried', () => {
    const reply = replyFromStored(
      stored({
        body: 'Four titles, waiting for your review.',
        components: {
          importId: 'i1',
          titles: [title('a')],
          roadmap: { steps: [{ items: [{ title: 'Heat', type: 'movie' }] }] },
        },
      }),
    )
    expect(reply).toMatchObject({
      text: 'Four titles, waiting for your review.',
      state: 'answered',
      importId: 'i1',
      problem: null,
    })
    expect(reply.titles).toHaveLength(1)
    expect(reply.roadmap?.steps).toHaveLength(1)
  })

  it('says when a stored answer failed or was stopped', () => {
    expect(replyFromStored(stored({ state: 'failed' }))).toMatchObject({
      state: 'failed',
      problem: DID_NOT_FINISH,
    })
    expect(
      replyFromStored(stored({ state: 'stopped', body: 'First, ' })),
    ).toMatchObject({
      state: 'cancelled',
      text: 'First, ',
      problem: STOPPED_EARLY,
    })
  })

  it('pairs each question with its answer, oldest first', () => {
    const pairs = exchangesOf([
      stored({ role: 'user', body: 'what is on tonight?' }),
      stored({ body: 'Nothing tonight.' }),
      stored({ role: 'user', body: 'and tomorrow?' }),
      stored({ body: 'Two shows.' }),
    ])
    expect(pairs.map((p) => [p.question, p.reply.text])).toEqual([
      ['what is on tonight?', 'Nothing tonight.'],
      ['and tomorrow?', 'Two shows.'],
    ])
  })

  it('keeps a question whose answer was never stored', () => {
    const pairs = exchangesOf([
      stored({ role: 'user', body: 'first' }),
      stored({ role: 'user', body: 'second' }),
    ])
    expect(pairs.map((p) => [p.question, p.reply.state])).toEqual([
      ['first', 'cancelled'],
      ['second', 'cancelled'],
    ])
  })
})
