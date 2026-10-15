import { describe, expect, it } from 'vitest'
import {
  addDays,
  badge,
  daysFrom,
  entryDay,
  episodeCode,
  fetchWindow,
  groupByDay,
  metaLine,
  mondayOf,
  rangeLabel,
  withWatched,
} from './model'
import type { CalendarEntry } from './model'

function entry(overrides: Partial<CalendarEntry> = {}): CalendarEntry {
  return {
    libraryItemId: '00000000-0000-4000-8000-000000000001',
    title: {
      id: '00000000-0000-4000-8000-0000000000aa',
      type: 'show',
      title: 'Severance',
      isAnime: false,
      ids: {},
      network: 'Apple TV+',
    },
    season: 2,
    number: 3,
    episodeName: 'Who Is Alive?',
    airsAt: '2026-10-16T00:00:00Z',
    airTimeKnown: false,
    watched: false,
    kind: 'regular',
    ...overrides,
  }
}

describe('week grid model', () => {
  it('keeps a date-only episode on its UTC date in every timezone', () => {
    const e = entry({ airsAt: '2026-10-16T00:00:00Z', airTimeKnown: false })
    expect(entryDay(e, 'America/Los_Angeles')).toBe('2026-10-16')
    expect(entryDay(e, 'Asia/Tokyo')).toBe('2026-10-16')
  })

  it('moves an exactly-timed episode to the viewer’s local day', () => {
    const e = entry({ airsAt: '2026-10-16T02:00:00Z', airTimeKnown: true })
    expect(entryDay(e, 'America/New_York')).toBe('2026-10-15')
    expect(entryDay(e, 'Europe/Lisbon')).toBe('2026-10-16')
  })

  it('pages by day across month and DST edges', () => {
    expect(addDays('2026-10-31', 1)).toBe('2026-11-01')
    expect(addDays('2026-03-29', -1)).toBe('2026-03-28')
    expect(mondayOf('2026-10-15')).toBe('2026-10-12') // Thursday → Monday
    expect(mondayOf('2026-10-18')).toBe('2026-10-12') // Sunday belongs to the same week
    expect(daysFrom('2026-10-12')).toHaveLength(7)
  })

  it('asks for a padded window the server accepts (≤ 35 days)', () => {
    const { from, to } = fetchWindow('2026-10-05', '2026-10-26')
    const days = (Date.parse(to) - Date.parse(from)) / 86_400_000
    expect(from).toBe('2026-10-03T00:00:00.000Z')
    expect(days).toBeLessThanOrEqual(35)
  })

  it('groups into the visible days only, by time then title', () => {
    const days = daysFrom('2026-10-12')
    const grouped = groupByDay(
      [
        entry({ title: { ...entry().title, title: 'Zorro' } }),
        entry({ title: { ...entry().title, title: 'Andor' } }),
        entry({ airsAt: '2026-10-30T00:00:00Z' }), // outside the week
      ],
      days,
      'UTC',
    )
    expect(grouped.get('2026-10-16')?.map((e) => e.title.title)).toEqual([
      'Andor',
      'Zorro',
    ])
    expect([...grouped.values()].flat()).toHaveLength(2)
  })

  it('labels episodes the CAT way', () => {
    expect(episodeCode(1, 5)).toBe('S01E05')
    expect(badge(entry({ kind: 'premiere', season: 1 }))).toBe('Premiere')
    expect(badge(entry({ kind: 'premiere', season: 3 }))).toBe('New season')
    expect(badge(entry({ kind: 'finale' }))).toBe('Finale')
    expect(badge(entry())).toBeNull()
  })

  it('shows the time only when it is exact, and the network when known', () => {
    expect(metaLine(entry(), 'UTC', 'en-US')).toBe('Apple TV+')
    expect(
      metaLine(
        entry({ airsAt: '2026-10-16T21:00:00Z', airTimeKnown: true }),
        'UTC',
        'en-US',
      ),
    ).toBe('Apple TV+ · 9:00 PM')
    expect(
      metaLine(
        entry({ title: { ...entry().title, network: undefined } }),
        'UTC',
        'en-US',
      ),
    ).toBe('')
  })

  it('formats the visible range', () => {
    expect(rangeLabel('2026-10-12', '2026-10-18', 'en-GB')).toBe(
      '12 – 18 Oct 2026',
    )
    expect(rangeLabel('2026-10-29', '2026-11-04', 'en-GB')).toBe(
      '29 Oct – 4 Nov 2026',
    )
  })

  it('ticks one episode and leaves the rest', () => {
    const a = entry()
    const b = entry({ number: 4 })
    const ticked = withWatched([a, b], a, true)
    expect(ticked.map((e) => e.watched)).toEqual([true, false])
  })
})
