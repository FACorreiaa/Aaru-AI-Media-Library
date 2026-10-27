import { sessionFromCookie } from '../export/proxy'

const USER_ID = /^[0-9a-f-]{36}$/i

/**
 * `GET /app/avatars/{userId}?v=`: someone's avatar as a same-origin image (SOC-001b). The
 * session stays in its HttpOnly cookie and goes to the API as a bearer token; the API decides
 * who may see it. Any refusal is an empty answer, so the page shows the monogram instead.
 */
export async function proxyAvatar(
  request: Request,
  userId: string,
  apiBaseURL: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Response> {
  const token = sessionFromCookie(request.headers.get('Cookie'))
  if (!token) return empty(401)
  if (!USER_ID.test(userId)) return empty(404)
  const version = new URL(request.url).searchParams.get('v')
  const query = version && /^\d+$/.test(version) ? `?v=${version}` : ''

  let upstream: Response
  try {
    upstream = await fetchImpl(
      `${apiBaseURL}/v1/users/${userId}/avatar${query}`,
      { headers: { Authorization: `Bearer ${token}` } },
    )
  } catch {
    return empty(502)
  }
  if (!upstream.ok) return empty(upstream.status === 401 ? 401 : 404)

  return new Response(upstream.body, {
    status: 200,
    headers: {
      'Content-Type': 'image/jpeg',
      'Cache-Control':
        upstream.headers.get('Cache-Control') ?? 'private, max-age=604800',
      // Another account signing in on this browser asks again.
      Vary: 'Cookie',
    },
  })
}

function empty(status: number): Response {
  return new Response(null, {
    status,
    headers: { 'Cache-Control': 'no-store' },
  })
}
