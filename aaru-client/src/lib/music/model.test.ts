import { describe, expect, it } from 'vitest'
import {
  SCROBBLERS,
  isNewListen,
  listenDetail,
  listenTitle,
  scrobblerLabel,
} from './model'
import type { Listen } from './server'

const listen = (overrides: Partial<Listen> = {}): Listen => ({
  id: '00000000-0000-0000-0000-000000000001',
  listenedAt: '2026-10-21T12:00:00Z',
  artist: 'Beastie Boys',
  track: 'Sabotage',
  ...overrides,
})

describe('music model', () => {
  it('offers every scrobbler, Web Scrobbler first', () => {
    expect(SCROBBLERS.map(scrobblerLabel)).toEqual([
      'Web Scrobbler',
      'Pano Scrobbler',
      'Navidrome',
      'Jellyfin',
      'Other',
    ])
  })

  it('names a listen by track and artist', () => {
    expect(listenTitle(listen())).toBe('Sabotage — Beastie Boys')
  })

  it('says when a listen played and what sent it', () => {
    const now = new Date('2026-10-21T12:03:00Z')
    expect(
      listenDetail(
        listen({ client: 'Web Scrobbler', musicService: 'YouTube Music' }),
        now,
      ),
    ).toBe('3 min ago · Web Scrobbler · YouTube Music')
    expect(listenDetail(listen(), new Date('2026-10-21T12:00:20Z'))).toBe(
      'Just now',
    )
    expect(listenDetail(listen(), new Date('2026-10-21T14:00:00Z'))).toBe(
      '2 hours ago',
    )
    expect(listenDetail(listen(), new Date('2026-10-22T12:00:00Z'))).toBe(
      'Yesterday',
    )
  })

  it('counts only a listen newer than the one seen when connecting', () => {
    const seen = listen()
    expect(isNewListen(seen, null)).toBe(false)
    expect(isNewListen(seen, listen())).toBe(false)
    expect(isNewListen(seen, listen({ id: 'other' }))).toBe(true)
    expect(isNewListen(null, listen())).toBe(true)
  })
})
