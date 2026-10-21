import { describe, expect, it } from 'vitest'
import {
  byDay,
  dayHeading,
  listenSubtitle,
  playsLabel,
  topRowLines,
} from './listening-model'
import type { Listen, TopRow } from './listening'

const listen = (at: string, overrides: Partial<Listen> = {}): Listen => ({
  id: at,
  listenedAt: at,
  artist: 'Massive Attack',
  track: 'Teardrop',
  ...overrides,
})

describe('listening model', () => {
  it('reads a listen by artist and album, else where it played', () => {
    expect(
      listenSubtitle(listen('2026-10-21T12:00:00', { album: 'Mezzanine' })),
    ).toBe('Massive Attack · Mezzanine')
    expect(
      listenSubtitle(
        listen('2026-10-21T12:00:00', { musicService: 'YouTube Music' }),
      ),
    ).toBe('Massive Attack · YouTube Music')
    expect(listenSubtitle(listen('2026-10-21T12:00:00'))).toBe('Massive Attack')
  })

  it('groups listens under their local day', () => {
    const now = new Date(2026, 9, 21, 18)
    const groups = byDay(
      [
        listen(new Date(2026, 9, 21, 14).toISOString()),
        listen(new Date(2026, 9, 21, 9).toISOString()),
        listen(new Date(2026, 9, 20, 22).toISOString()),
        listen(new Date(2025, 11, 31, 22).toISOString()),
      ],
      now,
    )
    expect(groups.map((g) => [g.heading, g.listens.length])).toEqual([
      ['Today', 2],
      ['Yesterday', 1],
      ['Dec 31, 2025', 1],
    ])
    expect(dayHeading(new Date(2026, 9, 19), now)).toBe('Mon, Oct 19')
  })

  it('labels top rows by what they rank', () => {
    const row: TopRow = {
      artist: 'Massive Attack',
      track: 'Teardrop',
      album: 'Mezzanine',
      count: 1,
      minutes: 5,
    }
    expect(topRowLines(row, 'artist')).toEqual(['Massive Attack'])
    expect(topRowLines(row, 'track')).toEqual(['Teardrop', 'Massive Attack'])
    expect(topRowLines(row, 'album')).toEqual(['Mezzanine', 'Massive Attack'])
    expect(playsLabel(1)).toBe('1 play')
    expect(playsLabel(1200)).toBe('1,200 plays')
  })
})
