import { sessionFromCookie } from '../export/proxy'
import { TIMEZONE_COOKIE, validTimeZone } from '../timezone'

// ASK-009 on the web: a Chat turn streams, and a spoken question is raw audio, so neither fits a
// server function. These two Worker routes pass them to `/v1` with the session from its HttpOnly
// cookie, and the answer back as it comes. They hold no rules.

export const UNREACHABLE =
  'Aaru could not reach the server. Try again in a moment.'

/** The largest recording the API reads. */
export const MAX_AUDIO_BYTES = 8 << 20

type Fetch = typeof fetch

/** `POST /app/assistant/turn?chat=…`: one Chat turn, its JSON body passed on, its stream back. */
export async function proxyChatTurn(
  request: Request,
  apiBaseURL: string,
  fetchImpl: Fetch = fetch,
): Promise<Response> {
  const refused = check(request)
  if (refused) return refused
  const chat = new URL(request.url).searchParams.get('chat') ?? ''
  if (!/^[0-9a-f-]{36}$/i.test(chat))
    return problem(400, 'bad_request', 'No chat was named.')
  if (!request.headers.get('Content-Type')?.startsWith('application/json'))
    return problem(415, 'unsupported_media_type', 'Send the question as JSON.')
  return forward(
    request,
    fetchImpl,
    `${apiBaseURL}/v1/chats/${chat}/turns`,
    'application/json',
    await request.text(),
  )
}

/** `POST /app/assistant/voice`: a spoken question's audio, read by the cluster's Whisper. */
export async function proxyTranscribe(
  request: Request,
  apiBaseURL: string,
  fetchImpl: Fetch = fetch,
): Promise<Response> {
  const refused = check(request)
  if (refused) return refused
  const type = request.headers.get('Content-Type') ?? ''
  if (!type.startsWith('audio/'))
    return problem(
      415,
      'unsupported_media_type',
      'Send the recording as audio.',
    )
  const audio = await request.arrayBuffer()
  if (audio.byteLength > MAX_AUDIO_BYTES)
    return problem(413, 'file_too_large', 'That recording is too long.')
  const seconds = request.headers.get('X-Audio-Seconds')
  return forward(
    request,
    fetchImpl,
    `${apiBaseURL}/v1/chats/transcribe`,
    type,
    audio,
    seconds && /^\d+(\.\d+)?$/.test(seconds)
      ? { 'X-Audio-Seconds': seconds }
      : {},
  )
}

/** A session, from this site. The cookie is SameSite=Lax already; the origin check is belt and braces. */
function check(request: Request): Response | null {
  const origin = request.headers.get('Origin')
  if (origin && origin !== new URL(request.url).origin)
    return problem(403, 'forbidden', 'That request came from another site.')
  if (!sessionFromCookie(request.headers.get('Cookie')))
    return problem(401, 'unauthorized', 'Sign in again to ask Aaru.')
  return null
}

async function forward(
  request: Request,
  fetchImpl: Fetch,
  url: string,
  type: string,
  body: BodyInit,
  extra: Record<string, string> = {},
): Promise<Response> {
  const cookie = request.headers.get('Cookie')
  const headers: Record<string, string> = {
    Authorization: `Bearer ${sessionFromCookie(cookie) ?? ''}`,
    'Content-Type': type,
    ...extra,
  }
  const zone = validTimeZone(cookieValue(cookie, TIMEZONE_COOKIE))
  if (zone) headers['X-Timezone'] = zone
  let upstream: Response
  try {
    // Hanging up on the page hangs up here too, which stops the turn.
    upstream = await fetchImpl(url, {
      method: 'POST',
      headers,
      body,
      signal: request.signal,
    })
  } catch {
    return problem(502, 'unreachable', UNREACHABLE)
  }
  const out = new Headers({ 'Cache-Control': 'no-store' })
  const upstreamType = upstream.headers.get('Content-Type')
  if (upstreamType) out.set('Content-Type', upstreamType)
  return new Response(upstream.body, { status: upstream.status, headers: out })
}

function cookieValue(header: string | null, name: string): string | undefined {
  for (const part of (header ?? '').split(';')) {
    const [key, ...rest] = part.trim().split('=')
    if (key === name) return decodeURIComponent(rest.join('='))
  }
  return undefined
}

function problem(status: number, code: string, message: string): Response {
  return new Response(JSON.stringify({ code, message }), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  })
}
