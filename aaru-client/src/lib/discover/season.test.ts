import { describe, expect, it } from 'vitest'
import {
  canShift,
  countLabel,
  direction,
  monthSpan,
  pageKey,
  seasonLabel,
  seasonOf,
  shiftSeason,
} from './season'

describe('seasonOf', () => {
  it('follows the calendar quarter', () => {
    expect(seasonOf('2026-01-01')).toEqual({ season: 'winter', year: 2026 })
    expect(seasonOf('2026-03-31')).toEqual({ season: 'winter', year: 2026 })
    expect(seasonOf('2026-04-01')).toEqual({ season: 'spring', year: 2026 })
    expect(seasonOf('2026-09-30')).toEqual({ season: 'summer', year: 2026 })
    expect(seasonOf('2026-12-31')).toEqual({ season: 'fall', year: 2026 })
  })
})

describe('shiftSeason', () => {
  it('crosses the year end both ways', () => {
    expect(shiftSeason({ season: 'fall', year: 2026 }, 1)).toEqual({
      season: 'winter',
      year: 2027,
    })
    expect(shiftSeason({ season: 'winter', year: 2026 }, -1)).toEqual({
      season: 'fall',
      year: 2025,
    })
    expect(shiftSeason({ season: 'spring', year: 2026 }, 1)).toEqual({
      season: 'summer',
      year: 2026,
    })
  })

  it('stops at 1970 and at next year', () => {
    const today = '2026-10-21'
    expect(canShift({ season: 'fall', year: 2027 }, 1, today)).toBe(false)
    expect(canShift({ season: 'summer', year: 2027 }, 1, today)).toBe(true)
    expect(canShift({ season: 'winter', year: 1970 }, -1, today)).toBe(false)
    expect(canShift({ season: 'spring', year: 1970 }, -1, today)).toBe(true)
  })
})

describe('labels', () => {
  it('names the season and its months', () => {
    expect(seasonLabel({ season: 'fall', year: 2026 })).toBe('Fall 2026')
    expect(monthSpan('winter')).toBe('Jan – Mar')
    expect(monthSpan('fall')).toBe('Oct – Dec')
  })

  it('counts in the kind’s noun', () => {
    expect(countLabel('anime', 84)).toBe('84 anime')
    expect(countLabel('shows_new', 1)).toBe('1 new show')
    expect(countLabel('movies', 9870)).toBe('9,870 films')
    expect(countLabel('movies', undefined)).toBeNull()
  })
})

describe('keys and direction', () => {
  it('keys a page by kind, season and page', () => {
    expect(pageKey('anime', { season: 'fall', year: 2026 }, 2)).toBe(
      'anime:2026-fall:2',
    )
  })

  it('says which way a season lies', () => {
    const fall = { season: 'fall', year: 2026 } as const
    expect(direction(fall, { season: 'winter', year: 2027 })).toBe(1)
    expect(direction(fall, { season: 'summer', year: 2026 })).toBe(-1)
    expect(direction(fall, fall)).toBe(0)
  })
})
