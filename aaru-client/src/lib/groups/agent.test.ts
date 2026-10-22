import { describe, expect, it } from 'vitest'
import {
  AGENT_HANDLE,
  THINKING_TTL_MS,
  agentCards,
  noteThinking,
  replySnippet,
  settleThinking,
  suggestMentions,
  suggestionHandle,
} from './agent'
import { buildTimeline } from './model'
import type { GroupMember, GroupMessage } from './server'

const me = 'me'

function member(userId: string, handle: string): GroupMember {
  return {
    user: { userId, handle },
    role: 'member',
    joinedAt: '2026-10-01T00:00:00Z',
    shareProgress: false,
  }
}

function message(id: string, extra: Partial<GroupMessage> = {}): GroupMessage {
  return {
    id,
    channelId: 'c',
    author: { userId: 'ana', handle: 'ana' },
    body: id,
    mentions: [],
    mentionsAgent: false,
    fromBlocked: false,
    deleted: false,
    veiled: false,
    fromAgent: false,
    createdAt: '2026-10-20T10:00:00Z',
    ...extra,
  }
}

function reply(id: string, replyTo: string): GroupMessage {
  return message(id, { author: undefined, fromAgent: true, replyTo })
}

describe('@aaru suggestions', () => {
  const members = [
    member('me', 'me_'),
    member('ana', 'ana'),
    member('aa', 'aardvark'),
  ]

  it('puts Aaru first when it answers here and the tag could be it', () => {
    const list = suggestMentions(members, 'aa', me, true)
    expect(list.map(suggestionHandle)).toEqual([AGENT_HANDLE, 'aardvark'])
    expect(suggestMentions(members, '', me, true)[0]).toEqual({ kind: 'agent' })
  })

  it('leaves Aaru out when it does not answer, or the tag cannot be it', () => {
    expect(
      suggestMentions(members, 'aa', me, false).map(suggestionHandle),
    ).toEqual(['aardvark'])
    expect(
      suggestMentions(members, 'an', me, true).map(suggestionHandle),
    ).toEqual(['ana'])
  })

  it('keeps to the limit with Aaru counted', () => {
    const many = Array.from({ length: 8 }, (_, i) =>
      member(`u${i}`, `aaron${i}`),
    )
    expect(suggestMentions(many, 'aa', me, true, 3)).toHaveLength(3)
  })
})

describe('Aaru is thinking', () => {
  it('notes a mention once and lets it run out', () => {
    let list = noteThinking([], 'm1', 0)
    list = noteThinking(list, 'm1', 1000)
    expect(list).toEqual([{ mention: 'm1', until: 1000 + THINKING_TTL_MS }])
    expect(settleThinking(list, [], 1000 + THINKING_TTL_MS)).toEqual([])
  })

  it('clears the mention an Aaru reply answers, and only that one', () => {
    const list = noteThinking(noteThinking([], 'm1', 0), 'm2', 0)
    const settled = settleThinking(list, [reply('r1', 'm1')], 10)
    expect(settled.map((t) => t.mention)).toEqual(['m2'])
    // A person's message that happens to reply to nothing changes nothing.
    expect(settleThinking(list, [message('x')], 10)).toBe(list)
  })
})

describe('Aaru replies', () => {
  it('quote who asked and the start of what they asked', () => {
    const long = 'w'.repeat(200)
    const asked = message('m1', { body: `  what   should\nwe ${long}` })
    const snippet = replySnippet('m1', [asked])
    expect(snippet?.who).toBe('@ana')
    expect(snippet?.text.startsWith('what should we w')).toBe(true)
    expect(snippet?.text.endsWith('…')).toBe(true)
    expect(snippet?.text.length).toBeLessThanOrEqual(80)
  })

  it('keep hidden messages hidden, and say nothing when the question is not loaded', () => {
    expect(replySnippet('m1', [message('m1', { veiled: true })])?.text).toBe(
      'something that may spoil',
    )
    expect(
      replySnippet('m1', [message('m1', { deleted: true, body: '' })])?.text,
    ).toBe('something deleted')
    expect(replySnippet('gone', [message('m1')])).toBeNull()
    expect(replySnippet(undefined, [message('m1')])).toBeNull()
  })

  it('carry title cards only', () => {
    const title = {
      id: 't',
      type: 'movie' as const,
      title: 'Heat',
      isAnime: false,
      ids: {},
    }
    const answer = message('r', {
      fromAgent: true,
      components: [{ type: 'title', title }],
    })
    expect(agentCards(answer).map((c) => c.title.title)).toEqual(['Heat'])
    expect(agentCards(message('x'))).toEqual([])
  })

  it('never join a person’s run, and a person never joins theirs', () => {
    const at = '2026-10-20T10:00:00Z'
    const items = buildTimeline(
      [
        message('a', { createdAt: at }),
        reply('r', 'a'),
        message('b', { createdAt: at }),
      ].map((m) => ({ ...m, createdAt: at })),
      [],
      { meId: me },
    )
    const starts = items.flatMap((i) =>
      i.kind === 'message' ? [i.startsRun] : [],
    )
    expect(starts).toEqual([true, true, true])
  })
})
