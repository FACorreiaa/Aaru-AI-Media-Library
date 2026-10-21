import { describe, expect, it } from 'vitest'
import {
  DAYPART_SCRIPT,
  appearanceCookie,
  appearanceFromCookieHeader,
  daypart,
  daypartHeading,
  parseAppearance,
  themeColorMeta,
} from './appearance'
import { PAPER } from './tokens.gen'

describe('parseAppearance', () => {
  it('keeps a pinned scheme and treats anything else as system', () => {
    expect(parseAppearance('dark')).toBe('dark')
    expect(parseAppearance('light')).toBe('light')
    expect(parseAppearance('sepia')).toBe('system')
    expect(parseAppearance(undefined)).toBe('system')
  })
})

describe('appearanceFromCookieHeader', () => {
  it('finds the cookie among others', () => {
    expect(appearanceFromCookieHeader('a=1; aaru_appearance=dark; b=2')).toBe(
      'dark',
    )
    expect(appearanceFromCookieHeader('a=1')).toBe('system')
    expect(appearanceFromCookieHeader('')).toBe('system')
  })
})

describe('appearanceCookie', () => {
  it('stores a pinned scheme for a year', () => {
    expect(appearanceCookie('light')).toBe(
      'aaru_appearance=light; Path=/; SameSite=Lax; Max-Age=31536000',
    )
  })
  it('clears the cookie for system', () => {
    expect(appearanceCookie('system')).toContain('Max-Age=0')
  })
})

describe('themeColorMeta', () => {
  it('pins one colour, or follows the system with two', () => {
    expect(themeColorMeta('dark')).toEqual([
      { name: 'theme-color', content: PAPER.dark },
    ])
    expect(themeColorMeta('system').map((m) => m.media)).toEqual([
      '(prefers-color-scheme: light)',
      '(prefers-color-scheme: dark)',
    ])
  })
})

describe('daypart', () => {
  it('splits the day at 5, 8, 17 and 21', () => {
    expect(daypart(0)).toBe('night')
    expect(daypart(4)).toBe('night')
    expect(daypart(5)).toBe('dawn')
    expect(daypart(12)).toBe('day')
    expect(daypart(17)).toBe('dusk')
    expect(daypart(21)).toBe('night')
    expect(daypart(23)).toBe('night')
  })

  it('agrees with the inline script for every hour', () => {
    for (let hour = 0; hour < 24; hour++) {
      const dataset: Record<string, string> = {}
      const fakeDate = class {
        getHours() {
          return hour
        }
      }
      new Function('Date', 'document', DAYPART_SCRIPT)(fakeDate, {
        documentElement: { dataset },
      })
      expect(dataset.daypart).toBe(daypart(hour))
    }
  })
})

describe('daypartHeading', () => {
  it('names the weekday and the part of the day', () => {
    expect(daypartHeading(new Date('2026-10-20T19:00:00Z'), 'UTC')).toBe(
      'Tuesday evening',
    )
    expect(daypartHeading(new Date('2026-10-20T12:00:00Z'), 'UTC')).toBe(
      'Tuesday',
    )
    expect(daypartHeading(new Date('2026-10-20T06:00:00Z'), 'UTC')).toBe(
      'Tuesday morning',
    )
    expect(daypartHeading(new Date('2026-10-20T23:30:00Z'), 'UTC')).toBe(
      'Tuesday night',
    )
  })
})
