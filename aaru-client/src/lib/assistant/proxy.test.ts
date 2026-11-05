import { describe, expect, it, vi } from 'vitest'
import { proxyChatTurn, proxyTranscribe } from './proxy'

const API = 'https://api.test'
const CHAT = '11111111-1111-4111-8111-111111111111'

function post(
  path: string,
  init: {
    cookie?: string
    origin?: string
    type?: string
    body?: BodyInit
  } = {},
) {
  const headers: Record<string, string> = {}
  if (init.cookie) headers.Cookie = init.cookie
  if (init.origin) headers.Origin = init.origin
  if (init.type) headers['Content-Type'] = init.type
  return new Request(`https://aaruapp.test${path}`, {
    method: 'POST',
    headers,
    body: init.body,
  })
}

describe('assistant proxy', () => {
  it('streams a turn through with the session and the time zone', async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response('event: done\ndata: {"turnId":"t"}\n\n', {
          headers: { 'Content-Type': 'text/event-stream' },
        }),
    )
    const response = await proxyChatTurn(
      post(`/app/assistant/turn?chat=${CHAT}`, {
        cookie: 'aaru_session=tok; aaru_tz=Europe%2FLisbon',
        origin: 'https://aaruapp.test',
        type: 'application/json',
        body: '{"body":"hi"}',
      }),
      API,
      fetchImpl,
    )
    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toBe('text/event-stream')
    expect(await response.text()).toContain('turnId')
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ]
    expect(url).toBe(`${API}/v1/chats/${CHAT}/turns`)
    expect(init.headers).toMatchObject({
      Authorization: 'Bearer tok',
      'X-Timezone': 'Europe/Lisbon',
    })
    expect(init.body).toBe('{"body":"hi"}')
  })

  it('passes a refusal on with its status', async () => {
    const fetchImpl = vi.fn(async () =>
      Response.json({ code: 'chat_busy', message: 'Busy' }, { status: 409 }),
    )
    const response = await proxyChatTurn(
      post(`/app/assistant/turn?chat=${CHAT}`, {
        cookie: 'aaru_session=tok',
        type: 'application/json',
        body: '{}',
      }),
      API,
      fetchImpl,
    )
    expect(response.status).toBe(409)
    expect(await response.json()).toMatchObject({ code: 'chat_busy' })
  })

  it('refuses without a session, from another site, or without a chat', async () => {
    const fetchImpl = vi.fn()
    const f = fetchImpl as unknown as typeof fetch
    const json = { type: 'application/json', body: '{}' }
    expect(
      (
        await proxyChatTurn(
          post(`/app/assistant/turn?chat=${CHAT}`, json),
          API,
          f,
        )
      ).status,
    ).toBe(401)
    expect(
      (
        await proxyChatTurn(
          post(`/app/assistant/turn?chat=${CHAT}`, {
            ...json,
            cookie: 'aaru_session=t',
            origin: 'https://evil.test',
          }),
          API,
          f,
        )
      ).status,
    ).toBe(403)
    expect(
      (
        await proxyChatTurn(
          post('/app/assistant/turn?chat=x', {
            ...json,
            cookie: 'aaru_session=t',
          }),
          API,
          f,
        )
      ).status,
    ).toBe(400)
    expect(fetchImpl).not.toHaveBeenCalled()
  })

  it('sends audio on with its length, and refuses anything else', async () => {
    const fetchImpl = vi.fn(async () =>
      Response.json({ text: 'hello', language: 'en' }),
    )
    const ok = await proxyTranscribe(
      new Request('https://aaruapp.test/app/assistant/voice', {
        method: 'POST',
        headers: {
          Cookie: 'aaru_session=t',
          'Content-Type': 'audio/webm;codecs=opus',
          'X-Audio-Seconds': '3.2',
        },
        body: new Uint8Array([1, 2, 3]),
      }),
      API,
      fetchImpl,
    )
    expect(await ok.json()).toEqual({ text: 'hello', language: 'en' })
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ]
    expect(url).toBe(`${API}/v1/chats/transcribe`)
    expect(init.headers).toMatchObject({
      'Content-Type': 'audio/webm;codecs=opus',
      'X-Audio-Seconds': '3.2',
    })
    const wrong = await proxyTranscribe(
      post('/app/assistant/voice', {
        cookie: 'aaru_session=t',
        type: 'text/plain',
        body: 'x',
      }),
      API,
      fetchImpl,
    )
    expect(wrong.status).toBe(415)
  })
})
