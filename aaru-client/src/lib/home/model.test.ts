import { describe, expect, it } from 'vitest'
import {
  advance,
  airingBadge,
  nextLine,
  remainingLabel,
  runtimeLabel,
  upcoming,
} from './model'
import type { ContinueEntry } from './model'
import type { CalendarEntry } from '../calendar/model'

function airing(overrides: Partial<CalendarEntry> = {}): CalendarEntry {
  return {
    libraryItemId: '00000000-0000-4000-8000-000000000001',
    title: {
      id: '00000000-0000-4000-8000-0000000000aa',
      type: 'show',
      title: 'Severance',
      isAnime: false,
      ids: {},
    },
    season: 2,
    number: 3,
    airsAt: '2026-10-16T00:00:00Z',
    airTimeKnown: false,
    watched: false,
    kind: 'regular',
    ...overrides,
  }
}

function continuing(overrides: Partial<ContinueEntry> = {}): ContinueEntry {
  return {
    libraryItemId: '00000000-0000-4000-8000-000000000002',
    title: {
      id: '00000000-0000-4000-8000-0000000000bb',
      type: 'show',
      title: 'The Bear',
      isAnime: false,
      ids: {},
    },
    next: { season: 1, number: 8 },
    nextName: 'Braciole',
    nextRuntimeMinutes: 30,
    remainingCount: 3,
    remainingMinutes: 90,
    isFinale: false,
    ...overrides,
  }
}

describe('home labels', () => {
  it('formats runtimes the way the cards read them', () => {
    expect(runtimeLabel(57)).toBe('57m')
    expect(runtimeLabel(87)).toBe('1h 27m')
    expect(runtimeLabel(120)).toBe('2h')
    expect(runtimeLabel(0)).toBe('')
    expect(runtimeLabel(undefined)).toBe('')
  })

  it('says what is left of a show', () => {
    expect(remainingLabel(10, 520)).toBe('10 left · 8h 40m')
    expect(remainingLabel(2, 0)).toBe('2 left')
  })

  it('names the next episode, without an empty name', () => {
    expect(nextLine(continuing())).toBe('S1 · E8 · Braciole')
    expect(nextLine(continuing({ nextName: undefined }))).toBe('S1 · E8')
  })
})

describe('calendar row badge', () => {
  // Thursday 15 October 2026, 18:00 in Lisbon (UTC+1).
  const now = new Date('2026-10-15T17:00:00Z')
  const lisbon = 'Europe/Lisbon'

  it('counts hours only for an exact time within twelve hours', () => {
    const soon = airing({ airTimeKnown: true, airsAt: '2026-10-15T20:00:00Z' })
    expect(airingBadge(soon, now, lisbon)).toBe('In 3 hours')
    const minutes = airing({
      airTimeKnown: true,
      airsAt: '2026-10-15T17:20:00Z',
    })
    expect(airingBadge(minutes, now, lisbon)).toBe('Within the hour')
    const late = airing({ airTimeKnown: true, airsAt: '2026-10-16T19:00:00Z' })
    expect(airingBadge(late, now, lisbon)).toBe('Tomorrow')
  })

  it('reads a date-only airing by its date, never in hours', () => {
    expect(
      airingBadge(airing({ airsAt: '2026-10-15T00:00:00Z' }), now, lisbon),
    ).toBe('Today · New')
    expect(
      airingBadge(airing({ airsAt: '2026-10-16T00:00:00Z' }), now, lisbon),
    ).toBe('Tomorrow')
    expect(
      airingBadge(airing({ airsAt: '2026-10-18T00:00:00Z' }), now, lisbon),
    ).toBe('In 3 days')
  })

  it('keeps a date-only airing on its date west of UTC', () => {
    // 20:00 on the 15th in Los Angeles is already the 16th in UTC.
    const evening = new Date('2026-10-16T03:00:00Z')
    expect(
      airingBadge(
        airing({ airsAt: '2026-10-15T00:00:00Z' }),
        evening,
        'America/Los_Angeles',
      ),
    ).toBe('Today · New')
  })

  it('says "Today · New" for an exact time already aired today', () => {
    const aired = airing({ airTimeKnown: true, airsAt: '2026-10-15T09:00:00Z' })
    expect(airingBadge(aired, now, lisbon)).toBe('Today · New')
  })

  it('has no badge for an airing before today', () => {
    expect(
      airingBadge(airing({ airsAt: '2026-10-14T00:00:00Z' }), now, lisbon),
    ).toBeNull()
  })

  it('lists airings from today on, soonest first, date-only before timed', () => {
    const rows = upcoming(
      [
        airing({ number: 9, airsAt: '2026-10-17T00:00:00Z' }),
        airing({ number: 1, airsAt: '2026-10-14T00:00:00Z' }),
        airing({
          number: 5,
          airTimeKnown: true,
          airsAt: '2026-10-15T20:00:00Z',
        }),
        airing({ number: 4, airsAt: '2026-10-15T00:00:00Z' }),
      ],
      now,
      lisbon,
    )
    expect(rows.map((r) => r.number)).toEqual([4, 5, 9])
    expect(upcoming(rows, now, lisbon, 2)).toHaveLength(2)
  })
})

describe('continue watching tick', () => {
  it('moves the card to the next episode and takes off its runtime', () => {
    const [row] = advance([continuing()], continuing())
    expect(row.next).toEqual({ season: 1, number: 9 })
    expect(row.nextName).toBeUndefined()
    expect(row.remainingCount).toBe(2)
    expect(row.remainingMinutes).toBe(60)
  })

  it('drops a show with nothing left and leaves the others alone', () => {
    const other = continuing({ libraryItemId: 'other' })
    expect(
      advance([continuing({ remainingCount: 1 }), other], continuing()),
    ).toEqual([other])
  })
})
