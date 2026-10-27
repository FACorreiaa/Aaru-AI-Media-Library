import { describe, expect, it, vi } from 'vitest'
import { proxyAvatar } from './avatar-proxy'
import { avatarSrc } from './avatar-src'

const API = 'https://api.test'
const ID = '0b6f6c2e-6f1a-4f3e-9a51-6c1d2b3a4e5f'

function request(path: string, cookie?: string) {
  return new Request(`https://aaruapp.test${path}`, {
    headers: cookie ? { Cookie: cookie } : {},
  })
}

describe('avatarSrc', () => {
  it('maps the API path to the same-origin route, version and all', () => {
    expect(avatarSrc(`/v1/users/${ID}/avatar?v=1730000000000`)).toBe(
      `/app/avatars/${ID}?v=1730000000000`,
    )
    expect(avatarSrc(`/v1/users/${ID}/avatar`)).toBe(`/app/avatars/${ID}`)
  })

  it('is null without an avatar, or for anything else', () => {
    expect(avatarSrc(undefined)).toBeNull()
    expect(avatarSrc(null)).toBeNull()
    expect(avatarSrc('')).toBeNull()
    expect(avatarSrc('https://evil.test/a.jpg')).toBeNull()
    expect(avatarSrc(`/v1/users/${ID}/avatar?v=1&x=2`)).toBeNull()
  })
})

describe('avatar proxy', () => {
  it('forwards the session and the version, and passes the image and its caching through', async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(new Uint8Array([0xff, 0xd8, 0xff]), {
          status: 200,
          headers: {
            'Content-Type': 'image/jpeg',
            'Cache-Control': 'private, max-age=604800',
          },
        }),
    )
    const response = await proxyAvatar(
      request(`/app/avatars/${ID}?v=7`, 'aaru_session=tok'),
      ID,
      API,
      fetchImpl,
    )
    expect(fetchImpl).toHaveBeenCalledWith(`${API}/v1/users/${ID}/avatar?v=7`, {
      headers: { Authorization: 'Bearer tok' },
    })
    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toBe('image/jpeg')
    expect(response.headers.get('Cache-Control')).toBe(
      'private, max-age=604800',
    )
    expect(response.headers.get('Vary')).toBe('Cookie')
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(
      new Uint8Array([0xff, 0xd8, 0xff]),
    )
  })

  it('answers empty without a session, for a bad id, and for any refusal', async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 404 }))
    expect(
      (await proxyAvatar(request(`/app/avatars/${ID}`), ID, API, fetchImpl))
        .status,
    ).toBe(401)
    expect(
      (
        await proxyAvatar(
          request('/app/avatars/x', 'aaru_session=tok'),
          '../me',
          API,
          fetchImpl,
        )
      ).status,
    ).toBe(404)
    expect(fetchImpl).not.toHaveBeenCalled()

    const blocked = await proxyAvatar(
      request(`/app/avatars/${ID}?v=evil`, 'aaru_session=tok'),
      ID,
      API,
      fetchImpl,
    )
    expect(fetchImpl).toHaveBeenCalledWith(`${API}/v1/users/${ID}/avatar`, {
      headers: { Authorization: 'Bearer tok' },
    })
    expect(blocked.status).toBe(404)
    expect(blocked.headers.get('Cache-Control')).toBe('no-store')
  })
})
