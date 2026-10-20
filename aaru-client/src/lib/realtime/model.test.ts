import { describe, expect, it } from 'vitest'
import type { PendingMessage } from '../groups/model'
import type { GroupMessage } from '../groups/server'
import {
  BACKOFF_CAP_MS,
  TYPING_TTL_MS,
  applyMessageEvent,
  backoffDelay,
  noteTyping,
  parseEvent,
  pruneTyping,
  settleEcho,
  typingDue,
  typingLine,
} from './model'

const ana = { userId: 'a', handle: 'ana', displayName: 'Ana' }
const kai = { userId: 'k', handle: 'kai' }
const bo = { userId: 'b', handle: 'bo', displayName: 'Bo' }

function message(
  id: string,
  createdAt: string,
  overrides: Partial<GroupMessage> = {},
): GroupMessage {
  return {
    id,
    channelId: 'c1',
    author: ana,
    body: id,
    mentions: [],
    mentionsAgent: false,
    fromBlocked: false,
    deleted: false,
    veiled: false,
    createdAt,
    ...overrides,
  }
}

describe('backoffDelay', () => {
  it('doubles from about a second and never passes the cap', () => {
    expect(backoffDelay(0, () => 0)).toBe(500)
    expect(backoffDelay(0, () => 1)).toBe(1000)
    expect(backoffDelay(3, () => 1)).toBe(8000)
    expect(backoffDelay(20, () => 1)).toBe(BACKOFF_CAP_MS)
    expect(backoffDelay(20, () => 0)).toBe(BACKOFF_CAP_MS / 2)
  })
})

describe('typingDue', () => {
  it('lets one frame through every three seconds', () => {
    expect(typingDue(undefined, 10)).toBe(true)
    expect(typingDue(1000, 3999)).toBe(false)
    expect(typingDue(1000, 4000)).toBe(true)
  })
})

describe('parseEvent', () => {
  it('reads known frames and drops the rest', () => {
    expect(parseEvent('{"type":"ready"}')?.type).toBe('ready')
    expect(parseEvent('{"type":"typing","groupId":"g"}')?.groupId).toBe('g')
    expect(parseEvent('{"type":"shout"}')).toBeNull()
    expect(parseEvent('not json')).toBeNull()
    expect(parseEvent('42')).toBeNull()
  })

  it('reads the shelf and watch-party frames', () => {
    for (const type of ['shelf.updated', 'watch.updated', 'watch.reaction'])
      expect(parseEvent(`{"type":"${type}"}`)?.type).toBe(type)
    expect(parseEvent('{"type":"watch.reaction","emoji":"🔥"}')?.emoji).toBe(
      '🔥',
    )
  })
})

describe('applyMessageEvent', () => {
  const list = [message('m1', '2026-10-20T10:00:00Z')]

  it('adds and replaces messages in the open channel only', () => {
    const fresh = message('m2', '2026-10-20T10:01:00Z')
    const added = applyMessageEvent(
      list,
      { type: 'message.created', channelId: 'c1', message: fresh },
      'c1',
    )
    expect(added.map((m) => m.id)).toEqual(['m1', 'm2'])
    // The same message twice (socket, then a REST catch-up) is still one row.
    expect(
      applyMessageEvent(
        added,
        { type: 'message.created', channelId: 'c1', message: fresh },
        'c1',
      ),
    ).toHaveLength(2)
    expect(
      applyMessageEvent(
        list,
        { type: 'message.created', channelId: 'c2', message: fresh },
        'c1',
      ),
    ).toBe(list)
    const edited = applyMessageEvent(
      list,
      {
        type: 'message.updated',
        channelId: 'c1',
        message: { ...list[0], body: 'edited' },
      },
      'c1',
    )
    expect(edited[0].body).toBe('edited')
  })

  it('empties a deleted message and ignores one it never had', () => {
    const gone = applyMessageEvent(
      list,
      { type: 'message.deleted', channelId: 'c1', messageId: 'm1' },
      'c1',
    )
    expect(gone[0]).toMatchObject({ body: '', deleted: true })
    expect(
      applyMessageEvent(
        list,
        { type: 'message.deleted', channelId: 'c1', messageId: 'zz' },
        'c1',
      ),
    ).toBe(list)
  })
})

describe('settleEcho', () => {
  const pending: PendingMessage[] = [
    { nonce: 'n1', body: 'hi', createdAt: '', state: 'failed' },
    { nonce: 'n2', body: 'hi', createdAt: '', state: 'sending' },
    { nonce: 'n3', body: 'hi', createdAt: '', state: 'sending' },
  ]

  it('drops exactly the pending copy the echo answers, by nonce', () => {
    const echo = message('m9', '2026-10-20T10:00:00Z', {
      body: 'hi',
      author: ana,
      clientNonce: 'n3',
    })
    expect(settleEcho(pending, echo).map((p) => p.nonce)).toEqual(['n1', 'n2'])
    const failedEcho = { ...echo, clientNonce: 'n1' }
    expect(settleEcho(pending, failedEcho).map((p) => p.nonce)).toEqual([
      'n2',
      'n3',
    ])
  })

  it('leaves pending alone for messages without my nonce', () => {
    const theirs = message('m8', '2026-10-20T10:00:00Z', { body: 'hi' })
    expect(settleEcho(pending, theirs)).toBe(pending)
  })
})

describe('typing', () => {
  it('keeps one entry per person and extends it on a newer frame', () => {
    let typists = noteTyping([], kai, 1000)
    typists = noteTyping(typists, kai, 3000)
    expect(typists).toEqual([{ user: kai, until: 3000 + TYPING_TTL_MS }])
  })

  it('drops expired entries and the person whose message arrived', () => {
    const typists = noteTyping(noteTyping([], kai, 0), bo, 4000)
    expect(pruneTyping(typists, TYPING_TTL_MS + 1).map((t) => t.user)).toEqual([
      bo,
    ])
    expect(pruneTyping(typists, 0, 'b').map((t) => t.user)).toEqual([kai])
  })

  it('names one or two people, then says several', () => {
    expect(typingLine([])).toBeNull()
    const one = noteTyping([], kai, 0)
    expect(typingLine(one)).toBe('@kai is typing…')
    const two = noteTyping(one, bo, 0)
    expect(typingLine(two)).toBe('@kai and Bo are typing…')
    expect(typingLine(noteTyping(two, ana, 0))).toBe(
      'Several people are typing…',
    )
  })
})
