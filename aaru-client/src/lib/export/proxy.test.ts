import { describe, expect, it, vi } from 'vitest'
import { exportFormat, proxyExport, sessionFromCookie } from './proxy'

const API = 'https://api.test'

function request(path: string, cookie?: string) {
  return new Request(`https://aaruapp.test${path}`, {
    headers: cookie ? { Cookie: cookie } : {},
  })
}

describe('export proxy', () => {
  it('reads the session cookie among others', () => {
    expect(sessionFromCookie('a=1; aaru_session=tok%3Den; b=2')).toBe('tok=en')
    expect(sessionFromCookie('a=1')).toBeNull()
    expect(sessionFromCookie(null)).toBeNull()
  })

  it('defaults to json and only takes csv otherwise', () => {
    expect(exportFormat(new URL('https://x/app/export'))).toBe('json')
    expect(exportFormat(new URL('https://x/app/export?format=csv'))).toBe('csv')
    expect(exportFormat(new URL('https://x/app/export?format=xml'))).toBe(
      'json',
    )
  })

  it('streams the body with the type and attachment name, never cached', async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response('Title,Year\r\nArrival,2016\r\n', {
          status: 200,
          headers: {
            'Content-Type': 'text/csv',
            'Content-Disposition':
              'attachment; filename="aaru-library-2026-10-16.csv"',
            'X-Internal': 'dropped',
          },
        }),
    )
    const response = await proxyExport(
      request('/app/export?format=csv', 'aaru_session=tok'),
      API,
      fetchImpl,
    )
    expect(fetchImpl).toHaveBeenCalledWith(`${API}/v1/me/export?format=csv`, {
      headers: { Authorization: 'Bearer tok' },
    })
    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toBe('text/csv')
    expect(response.headers.get('Content-Disposition')).toContain(
      'aaru-library-2026-10-16.csv',
    )
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(response.headers.get('X-Internal')).toBeNull()
    expect(await response.text()).toContain('Arrival,2016')
  })

  it('sends a missing or refused session to sign-in', async () => {
    const noCookie = await proxyExport(request('/app/export'), API, vi.fn())
    expect(noCookie.status).toBe(302)
    expect(noCookie.headers.get('Location')).toBe(
      'https://aaruapp.test/sign-in',
    )
    const refused = await proxyExport(
      request('/app/export', 'aaru_session=old'),
      API,
      async () => new Response('', { status: 401 }),
    )
    expect(refused.status).toBe(302)
  })

  it('turns an API failure or outage into a plain 502', async () => {
    const failed = await proxyExport(
      request('/app/export', 'aaru_session=tok'),
      API,
      async () => new Response('', { status: 500 }),
    )
    expect(failed.status).toBe(502)
    const down = await proxyExport(
      request('/app/export', 'aaru_session=tok'),
      API,
      async () => {
        throw new Error('network')
      },
    )
    expect(down.status).toBe(502)
    expect(await down.text()).toContain('could not reach')
  })
})
