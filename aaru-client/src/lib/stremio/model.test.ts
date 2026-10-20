import { describe, expect, it } from 'vitest'
import { canChangeLibrary, lastUsedLabel } from './model'
import type { AgentToken } from './server'

const token = (overrides: Partial<AgentToken> = {}): AgentToken => ({
  id: '00000000-0000-0000-0000-000000000001',
  name: 'Stremio',
  kind: 'stremio',
  scopes: ['library:read', 'scrobble:write'],
  createdAt: '2026-10-01T00:00:00Z',
  ...overrides,
})

describe('stremio model', () => {
  const now = new Date('2026-10-20T12:00:00Z')

  it('labels when a link was last used', () => {
    expect(lastUsedLabel(token(), now)).toBe('Not used yet')
    expect(
      lastUsedLabel(token({ lastUsedAt: '2026-10-20T09:00:00Z' }), now),
    ).toBe('Used today')
    expect(
      lastUsedLabel(token({ lastUsedAt: '2026-10-19T09:00:00Z' }), now),
    ).toBe('Used yesterday')
    expect(
      lastUsedLabel(token({ lastUsedAt: '2026-10-15T12:00:00Z' }), now),
    ).toBe('Used 5 days ago')
  })

  it('knows whether a link may change the library', () => {
    expect(canChangeLibrary(token())).toBe(false)
    expect(
      canChangeLibrary(
        token({ scopes: ['library:read', 'library:write', 'scrobble:write'] }),
      ),
    ).toBe(true)
  })
})
