import { describe, expect, it } from 'vitest'
import {
  applyMention,
  badgeText,
  buildTimeline,
  dayLabel,
  failPending,
  groupMonogram,
  matchMembers,
  membersByRole,
  mentionQuery,
  mergeMessages,
  newLineIndex,
  remainingLabel,
  retryPending,
  settlePending,
  splitMentions,
} from './model'
import type { PendingMessage } from './model'
import type { GroupMember, GroupMessage } from './server'

const me = '00000000-0000-0000-0000-000000000001'
const ana = '00000000-0000-0000-0000-000000000002'

let counter = 0
function message(
  author: string | null,
  at: string,
  extra: Partial<GroupMessage> = {},
): GroupMessage {
  counter += 1
  return {
    id: `00000000-0000-0000-0001-${String(counter).padStart(12, '0')}`,
    channelId: 'c',
    author: author
      ? { userId: author, handle: author === me ? 'me_' : 'ana' }
      : undefined,
    body: `m${counter}`,
    mentions: [],
    mentionsAgent: false,
    fromBlocked: false,
    deleted: false,
    veiled: false,
    createdAt: at,
    ...extra,
  }
}

function member(
  userId: string,
  handle: string,
  role: GroupMember['role'] = 'member',
  displayName?: string,
): GroupMember {
  return {
    user: { userId, handle, displayName },
    role,
    joinedAt: '2026-10-01T00:00:00Z',
    shareProgress: false,
  }
}

describe('groups timeline', () => {
  it('groups a run by one author within five minutes', () => {
    const items = buildTimeline(
      [
        message(ana, '2026-10-20T10:00:00'),
        message(ana, '2026-10-20T10:04:00'),
        message(ana, '2026-10-20T10:10:00'),
        message(me, '2026-10-20T10:11:00'),
      ],
      [],
      { meId: me },
    )
    const runs = items.flatMap((i) =>
      i.kind === 'message' ? [i.startsRun] : [],
    )
    expect(runs).toEqual([true, false, true, true])
  })

  it('puts a divider on each new day and breaks the run there', () => {
    const items = buildTimeline(
      [
        message(ana, '2026-10-19T23:58:00'),
        message(ana, '2026-10-20T00:01:00'),
      ],
      [],
      { meId: me },
    )
    expect(items.map((i) => i.kind)).toEqual([
      'day',
      'message',
      'day',
      'message',
    ])
    expect(items[3]).toMatchObject({ startsRun: true })
  })

  it('places the New line and breaks the run under it', () => {
    const list = [
      message(ana, '2026-10-20T10:00:00'),
      message(ana, '2026-10-20T10:01:00'),
      message(me, '2026-10-20T10:02:00'),
      message(ana, '2026-10-20T10:03:00'),
    ]
    // Two unread from others: m2 and m4, skipping my own m3.
    const at = newLineIndex(list, 2, me)
    expect(at).toBe(1)
    const items = buildTimeline(list, [], { meId: me, newLineAt: at })
    expect(items.map((i) => i.kind)).toEqual([
      'day',
      'message',
      'new',
      'message',
      'message',
      'message',
    ])
    expect(items[3]).toMatchObject({ startsRun: true })
    expect(newLineIndex(list, 0, me)).toBe(-1)
    expect(newLineIndex(list, 9, me)).toBe(0)
  })

  it('continues my run with my pending sends', () => {
    const pending: PendingMessage[] = [
      {
        nonce: 'n',
        body: 'hi',
        createdAt: '2026-10-20T10:01:00',
        state: 'sending',
      },
    ]
    const items = buildTimeline([message(me, '2026-10-20T10:00:00')], pending, {
      meId: me,
    })
    expect(items.at(-1)).toMatchObject({ kind: 'pending', startsRun: false })
  })

  it('never continues a run from a deleted account', () => {
    const items = buildTimeline(
      [
        message(null, '2026-10-20T10:00:00'),
        message(null, '2026-10-20T10:01:00'),
      ],
      [],
      { meId: me },
    )
    expect(
      items.flatMap((i) => (i.kind === 'message' ? [i.startsRun] : [])),
    ).toEqual([true, true])
  })

  it('labels today and yesterday', () => {
    const now = new Date('2026-10-20T12:00:00')
    expect(dayLabel('2026-10-20T08:00:00', now)).toBe('Today')
    expect(dayLabel('2026-10-19T08:00:00', now)).toBe('Yesterday')
    expect(dayLabel('2026-10-12T08:00:00', now)).not.toBe('Yesterday')
  })
})

describe('groups polling and optimistic sends', () => {
  it('merges a page by id, newer copy wins, oldest first', () => {
    const a = message(ana, '2026-10-20T10:00:00')
    const b = message(ana, '2026-10-20T10:01:00')
    const editedA = { ...a, body: 'edited', editedAt: '2026-10-20T10:05:00' }
    const c = message(me, '2026-10-20T10:02:00')
    const merged = mergeMessages([a, b], [c, editedA])
    expect(merged.map((m) => m.id)).toEqual([a.id, b.id, c.id])
    expect(merged[0].body).toBe('edited')
  })

  it('keeps the server order for messages sent in the same second', () => {
    // Ids sort the other way round, as random UUIDs often do.
    const first = message(ana, '2026-10-20T10:00:00Z', { id: 'ffff' })
    const second = message(ana, '2026-10-20T10:00:00Z', { id: '0000' })
    expect(mergeMessages([], [first, second]).map((m) => m.id)).toEqual([
      'ffff',
      '0000',
    ])
    expect(mergeMessages([first], [second]).map((m) => m.id)).toEqual([
      'ffff',
      '0000',
    ])
  })

  it('settles, fails and retries sends by nonce', () => {
    const pending: PendingMessage[] = [
      { nonce: 'a', body: '1', createdAt: '', state: 'sending' },
      { nonce: 'b', body: '2', createdAt: '', state: 'sending' },
    ]
    const failed = failPending(pending, 'b')
    expect(failed[1].state).toBe('failed')
    expect(retryPending(failed, 'b')[1].state).toBe('sending')
    expect(settlePending(pending, 'a').map((p) => p.nonce)).toEqual(['b'])
  })
})

describe('groups mentions', () => {
  const handles = new Set(['ana', 'me_'])

  it('highlights members and Aaru, not emails or strangers', () => {
    const segments = splitMentions(
      'hey @Ana and @aaru, mail@ana @nobody',
      handles,
      'me_',
    )
    expect(segments).toEqual([
      { kind: 'text', text: 'hey ' },
      { kind: 'mention', text: '@Ana', handle: 'ana', me: false },
      { kind: 'text', text: ' and ' },
      { kind: 'mention', text: '@aaru', handle: 'aaru', me: false },
      { kind: 'text', text: ', mail@ana @nobody' },
    ])
  })

  it('marks a mention of me', () => {
    expect(splitMentions('@me_ look', handles, 'me_')[0]).toMatchObject({
      kind: 'mention',
      me: true,
    })
  })

  it('finds the tag being typed at the caret', () => {
    expect(mentionQuery('hi @an', 6)).toEqual({ start: 3, query: 'an' })
    expect(mentionQuery('hi @', 4)).toEqual({ start: 3, query: '' })
    expect(mentionQuery('mail@an', 7)).toBeNull()
    expect(mentionQuery('hi @an there', 12)).toBeNull()
    expect(mentionQuery('no tag', 6)).toBeNull()
  })

  it('suggests members by handle prefix, then contains, never me', () => {
    const members = [
      member(me, 'me_'),
      member(ana, 'ana'),
      member('3', 'banana', 'member', 'Bea'),
      member('4', 'kai', 'member', 'Anabel'),
    ]
    expect(matchMembers(members, 'an', me).map((m) => m.user.handle)).toEqual([
      'ana',
      'banana',
      'kai',
    ])
    expect(matchMembers(members, '', me)).toHaveLength(3)
  })

  it('replaces the partial tag and moves the caret past it', () => {
    expect(applyMention('hi @an x', 3, 6, 'ana')).toEqual({
      text: 'hi @ana  x',
      caret: 8,
    })
  })
})

describe('groups labels', () => {
  it('caps badges at 99+ and hides zero', () => {
    expect(badgeText(0)).toBe('')
    expect(badgeText(7)).toBe('7')
    expect(badgeText(120)).toBe('99+')
  })

  it('makes group monograms', () => {
    expect(groupMonogram('Film club')).toBe('FC')
    expect(groupMonogram('séries')).toBe('S')
    expect(groupMonogram('  ')).toBe('?')
  })

  it('counts down only near the limit', () => {
    expect(remainingLabel('hi')).toBeNull()
    expect(remainingLabel('a'.repeat(3900))).toBe('100')
  })

  it('sorts members by role then handle', () => {
    const grouped = membersByRole([
      member('1', 'zed'),
      member('2', 'own', 'owner'),
      member('3', 'amy'),
      member('4', 'adm', 'admin'),
    ])
    expect(grouped.owner.map((m) => m.user.handle)).toEqual(['own'])
    expect(grouped.admins.map((m) => m.user.handle)).toEqual(['adm'])
    expect(grouped.members.map((m) => m.user.handle)).toEqual(['amy', 'zed'])
  })
})
