import { describe, expect, it, vi } from 'vitest'
import { BUSY_TRIES, ChatThread, IDLE_MS } from './thread'

function stream(text: string) {
  return new Response(text, {
    headers: { 'Content-Type': 'text/event-stream' },
  })
}

function thread(responses: Array<() => Response>, now = { t: 0 }) {
  const chats: string[] = []
  const fetchImpl = vi.fn(async () => {
    const next = responses.shift()
    if (!next) throw new Error('no more responses')
    return next()
  })
  let n = 0
  const t = new ChatThread({
    createChat: async () => {
      const id = `c${++n}`
      chats.push(id)
      return id
    },
    fetch: fetchImpl,
    now: () => now.t,
    delay: async () => undefined,
    busyRetryMs: 0,
  })
  return { t, chats, fetchImpl }
}

const answer =
  'event: delta\ndata: {"text":"Hi"}\n\nevent: done\ndata: {"turnId":"t"}\n\n'

describe('chat thread', () => {
  it('starts a chat, streams the answer and keeps the chat', async () => {
    const { t, chats, fetchImpl } = thread([
      () => stream(answer),
      () => stream(answer),
    ])
    const updates: string[] = []
    const reply = await t.send(
      'hi',
      { screen: 'home' },
      new AbortController().signal,
      (r) => updates.push(r.text),
    )
    expect(reply).toMatchObject({ text: 'Hi', state: 'answered' })
    expect(updates).toContain('Hi')
    await t.send(
      'again',
      undefined,
      new AbortController().signal,
      () => undefined,
    )
    expect(chats).toEqual(['c1'])
    const body = JSON.parse(
      (fetchImpl.mock.calls[0] as unknown as [string, RequestInit])[1]
        .body as string,
    )
    expect(body).toEqual({ body: 'hi', hint: { screen: 'home' } })
  })

  it('makes a new chat once after a 404, and waits out a busy one', async () => {
    const { t, chats } = thread([
      () => Response.json({ message: 'gone' }, { status: 404 }),
      () => Response.json({ message: 'busy' }, { status: 409 }),
      () => stream(answer),
    ])
    const reply = await t.send(
      'hi',
      undefined,
      new AbortController().signal,
      () => undefined,
    )
    expect(reply.state).toBe('answered')
    expect(chats).toEqual(['c1', 'c2'])
  })

  it('gives up on a chat that stays busy, and shows other refusals', async () => {
    const busy = () => Response.json({ message: 'busy' }, { status: 409 })
    const { t } = thread(Array.from({ length: BUSY_TRIES }, () => busy))
    expect(
      (
        await t.send(
          'hi',
          undefined,
          new AbortController().signal,
          () => undefined,
        )
      ).state,
    ).toBe('failed')
    const other = thread([
      () => Response.json({ message: 'Too long.' }, { status: 422 }),
    ])
    expect(
      await other.t.send(
        'hi',
        undefined,
        new AbortController().signal,
        () => undefined,
      ),
    ).toMatchObject({
      state: 'failed',
      problem: 'Too long.',
    })
  })

  it('starts over after 15 minutes away', async () => {
    const now = { t: 0 }
    const { t, chats } = thread(
      [() => stream(answer), () => stream(answer)],
      now,
    )
    await t.send('hi', undefined, new AbortController().signal, () => undefined)
    now.t = IDLE_MS - 1
    expect(t.reopen()).toBe(true)
    now.t += IDLE_MS + 1
    expect(t.reopen()).toBe(false)
    await t.send('hi', undefined, new AbortController().signal, () => undefined)
    expect(chats).toEqual(['c1', 'c2'])
  })

  it('continues a chat opened from history and restarts its 15 minutes', async () => {
    const now = { t: 0 }
    const { t, chats, fetchImpl } = thread(
      [() => stream(answer), () => stream(answer)],
      now,
    )
    now.t = IDLE_MS * 3
    t.adopt('old')
    expect(t.current()).toBe('old')
    expect(t.reopen()).toBe(true)
    await t.send('hi', undefined, new AbortController().signal, () => undefined)
    expect(chats).toEqual([])
    expect(JSON.stringify(fetchImpl.mock.calls)).toContain('chat=old')
  })

  it('New chat forgets the chat, so the next question starts another', async () => {
    const { t, chats } = thread([() => stream(answer), () => stream(answer)])
    await t.send('hi', undefined, new AbortController().signal, () => undefined)
    t.reset()
    expect(t.current()).toBeNull()
    await t.send('hi', undefined, new AbortController().signal, () => undefined)
    expect(chats).toEqual(['c1', 'c2'])
  })

  it('a cancelled turn says so', async () => {
    const controller = new AbortController()
    controller.abort()
    const { t } = thread([() => stream(answer)])
    expect(
      (await t.send('hi', undefined, controller.signal, () => undefined)).state,
    ).toBe('cancelled')
  })
})
