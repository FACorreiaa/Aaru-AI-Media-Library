import { describe, expect, it, vi } from 'vitest'
import { MAX_ATTACHMENT_BYTES, proxyChatAttachment } from './proxy'
import { ChatThread, FILES_GONE } from './thread'
import { PASTE_AS_FILE, pastedText, piecesOf } from './files'

// ASK-010 on the web: files in a chat.

const API = 'https://api.test'
const CHAT = '11111111-1111-4111-8111-111111111111'
const FILE = '22222222-2222-4222-8222-222222222222'

function request(path: string, init: RequestInit & { cookie?: string } = {}) {
  const headers = new Headers(init.headers)
  headers.set('Cookie', init.cookie ?? 'aaru_session=tok')
  return new Request(`https://aaruapp.test${path}`, { ...init, headers })
}

describe('attach proxy', () => {
  it('passes the file through as it is, with its name and type', async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response('{"id":"x"}', {
          status: 201,
          headers: { 'Content-Type': 'application/json' },
        }),
    )
    const response = await proxyChatAttachment(
      request(`/app/assistant/attach?chat=${CHAT}&filename=watched.csv`, {
        method: 'POST',
        headers: { 'Content-Type': 'text/csv' },
        body: 'Name,Year\nDune,2021\n',
      }),
      API,
      fetchImpl,
    )
    expect(response.status).toBe(201)
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ]
    expect(url).toBe(`${API}/v1/chats/${CHAT}/attachments?filename=watched.csv`)
    expect(init.method).toBe('POST')
    expect(init.headers).toMatchObject({
      Authorization: 'Bearer tok',
      'Content-Type': 'text/csv',
    })
    expect(new TextDecoder().decode(init.body as ArrayBuffer)).toBe(
      'Name,Year\nDune,2021\n',
    )
  })

  it('removes a file', async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }))
    const response = await proxyChatAttachment(
      request(`/app/assistant/attach?chat=${CHAT}&id=${FILE}`, {
        method: 'DELETE',
      }),
      API,
      fetchImpl,
    )
    expect(response.status).toBe(204)
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ]
    expect(url).toBe(`${API}/v1/chats/${CHAT}/attachments/${FILE}`)
    expect(init.method).toBe('DELETE')
  })

  it('refuses without a session, a chat, or past 24 MB, before the API', async () => {
    const fetchImpl = vi.fn()
    const noSession = await proxyChatAttachment(
      request(`/app/assistant/attach?chat=${CHAT}`, {
        method: 'POST',
        body: 'x',
        cookie: '',
      }),
      API,
      fetchImpl,
    )
    expect(noSession.status).toBe(401)
    const noChat = await proxyChatAttachment(
      request('/app/assistant/attach?chat=nope', { method: 'POST', body: 'x' }),
      API,
      fetchImpl,
    )
    expect(noChat.status).toBe(400)
    const big = await proxyChatAttachment(
      request(`/app/assistant/attach?chat=${CHAT}`, {
        method: 'POST',
        body: new Uint8Array(MAX_ATTACHMENT_BYTES + 1),
      }),
      API,
      fetchImpl,
    )
    expect(big.status).toBe(413)
    expect(fetchImpl).not.toHaveBeenCalled()
  })
})

function thread(responses: Array<() => Response>) {
  const fetchImpl = vi.fn(async () => {
    const next = responses.shift()
    if (!next) throw new Error('no more responses')
    return next()
  })
  let n = 0
  const t = new ChatThread({
    createChat: async () => `c${++n}`,
    fetch: fetchImpl,
    now: () => 0,
    delay: async () => undefined,
    busyRetryMs: 0,
  })
  return { t, fetchImpl }
}

const attachment = {
  id: FILE,
  kind: 'export',
  name: 'watched.csv',
  size: 20,
  summary: 'a Letterboxd export of 1 rows',
}

describe('chat thread files', () => {
  it('attaches into the chat it then sends the turn to, with the ids', async () => {
    const { t, fetchImpl } = thread([
      () => new Response(JSON.stringify(attachment), { status: 201 }),
      () =>
        new Response('event: done\ndata: {"turnId":"t"}\n\n', {
          headers: { 'Content-Type': 'text/event-stream' },
        }),
    ])
    const { chat } = await t.attach(
      new Blob(['Name,Year'], { type: 'text/csv' }),
      'watched.csv',
      new AbortController().signal,
    )
    expect(chat).toBe('c1')
    await t.send('', undefined, new AbortController().signal, () => undefined, [
      FILE,
    ])
    const calls = fetchImpl.mock.calls as unknown as Array<
      [string, RequestInit]
    >
    expect(calls[0][0]).toBe(
      '/app/assistant/attach?chat=c1&filename=watched.csv',
    )
    expect(calls[1][0]).toBe('/app/assistant/turn?chat=c1')
    expect(JSON.parse(calls[1][1].body as string)).toEqual({
      body: '',
      attachments: [FILE],
    })
  })

  it("says the server's reason for a file it refuses", async () => {
    const { t } = thread([
      () =>
        new Response(JSON.stringify({ message: 'That file is a program.' }), {
          status: 422,
        }),
    ])
    await expect(
      t.attach(new Blob(['MZ']), 'list.csv', new AbortController().signal),
    ).rejects.toThrow('That file is a program.')
  })

  it('does not start a new chat for a turn whose files are gone', async () => {
    const { t, fetchImpl } = thread([
      () => new Response(JSON.stringify(attachment), { status: 201 }),
      () => new Response('{"message":"gone"}', { status: 404 }),
    ])
    await t.attach(new Blob(['x']), 'a.txt', new AbortController().signal)
    const reply = await t.send(
      'import it',
      undefined,
      new AbortController().signal,
      () => undefined,
      [FILE],
    )
    expect(reply.problem).toBe(FILES_GONE)
    expect(fetchImpl).toHaveBeenCalledTimes(2)
  })
})

describe('files', () => {
  it('sends a long paste as text with no name', () => {
    const piece = pastedText('x'.repeat(PASTE_AS_FILE + 1))
    expect(piece.name).toBe('')
    expect(piece.blob.type).toBe('text/plain')
  })

  it('sends anything but a picture as it is, and refuses past 24 MB', async () => {
    const csv = new File(['Name,Year'], 'watched.csv', { type: 'text/csv' })
    expect(await piecesOf(csv)).toEqual([{ blob: csv, name: 'watched.csv' }])
    const big = new File([new Uint8Array(1)], 'big.json')
    Object.defineProperty(big, 'size', { value: 25 << 20 })
    await expect(piecesOf(big)).rejects.toThrow('larger than 24 MB')
  })
})
