import { SESSION_COOKIE } from '../session/cookie'

export type ExportFormat = 'json' | 'csv'

/** `?format=` on the request, `json` unless it says `csv`. */
export function exportFormat(url: URL): ExportFormat {
  return url.searchParams.get('format') === 'csv' ? 'csv' : 'json'
}

/** The session token from a raw `Cookie` header, if any. */
export function sessionFromCookie(header: string | null): string | null {
  if (!header) return null
  for (const part of header.split(';')) {
    const [name, ...rest] = part.trim().split('=')
    if (name === SESSION_COOKIE) {
      const value = rest.join('=')
      return value ? decodeURIComponent(value) : null
    }
  }
  return null
}

/**
 * `GET /app/export`: the account export as a same-origin download. The session stays in its
 * HttpOnly cookie; the API's body streams through with its type and attachment name, so the
 * browser saves the file itself. No session, or a session the API refuses, goes to sign-in.
 */
export async function proxyExport(
  request: Request,
  apiBaseURL: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Response> {
  const url = new URL(request.url)
  const token = sessionFromCookie(request.headers.get('Cookie'))
  const signIn = new URL('/sign-in', url).toString()
  if (!token) return redirect(signIn)

  let upstream: Response
  try {
    upstream = await fetchImpl(
      `${apiBaseURL}/v1/me/export?format=${exportFormat(url)}`,
      { headers: { Authorization: `Bearer ${token}` } },
    )
  } catch {
    return plain(502, 'Aaru could not reach the server. Try again in a moment.')
  }
  if (upstream.status === 401) return redirect(signIn)
  if (!upstream.ok) {
    return plain(
      502,
      'Your export could not be prepared. Try again in a moment.',
    )
  }

  const headers = new Headers({ 'Cache-Control': 'no-store' })
  for (const name of ['Content-Type', 'Content-Disposition']) {
    const value = upstream.headers.get(name)
    if (value) headers.set(name, value)
  }
  return new Response(upstream.body, { status: 200, headers })
}

/** A redirect with ordinary (mutable) headers, unlike `Response.redirect`. */
function redirect(location: string): Response {
  return new Response(null, {
    status: 302,
    headers: { Location: location, 'Cache-Control': 'no-store' },
  })
}

function plain(status: number, message: string): Response {
  return new Response(message, {
    status,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  })
}
