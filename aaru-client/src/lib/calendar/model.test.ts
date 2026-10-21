import { describe, expect, it } from 'vitest'
import {
  MAX_FETCH_DAYS,
  addDays,
  addMonths,
  agendaDayLabel,
  agendaDays,
  badge,
  daysFrom,
  daysInMonth,
  entryDay,
  episodeCode,
  fetchWindow,
  fetchWindows,
  groupByDay,
  metaLine,
  mondayOf,
  monthGrid,
  monthLabel,
  monthOf,
  rangeLabel,
  shortCode,
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

  it('asks for a padded window around the visible days', () => {
    const { from, to } = fetchWindow('2026-10-05', '2026-10-26')
    const days = (Date.parse(to) - Date.parse(from)) / 86_400_000
    expect(from).toBe('2026-10-03T00:00:00Z')
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

const span = (w: { from: string; to: string }) =>
  (Date.parse(w.to) - Date.parse(w.from)) / 86_400_000

describe('month view model', () => {
  it('covers a month with Monday-start weeks: five rows when it fits', () => {
    const grid = monthGrid('2026-10') // 1 Oct 2026 is a Thursday
    expect(grid).toHaveLength(35)
    expect(grid[0]).toBe('2026-09-28')
    expect(grid.at(-1)).toBe('2026-11-01')
  })

  it('takes six rows when the month spills over', () => {
    const grid = monthGrid('2026-08') // starts Saturday, ends Monday
    expect(grid).toHaveLength(42)
    expect(grid[0]).toBe('2026-07-27')
    expect(grid.at(-1)).toBe('2026-09-06')
  })

  it('takes four rows for a February that starts on a Monday', () => {
    expect(monthGrid('2027-02')).toEqual(daysFrom('2027-02-01', 28))
  })

  it('knows leap Februaries', () => {
    expect(daysInMonth('2028-02')).toBe(29)
    expect(daysInMonth('2026-02')).toBe(28)
    const grid = monthGrid('2028-02')
    expect(grid).toContain('2028-02-29')
    expect(grid[0]).toBe('2028-01-31')
    expect(grid.at(-1)).toBe('2028-03-05')
  })

  it('has one key per day across a DST change', () => {
    const grid = monthGrid('2026-03') // Europe moves its clocks on 29 March
    expect(new Set(grid).size).toBe(grid.length)
    expect(grid).toContain('2026-03-29')
    expect(grid).toContain('2026-03-30')
    expect(grid).toHaveLength(42)
  })

  it('steps months across years', () => {
    expect(addMonths('2026-12', 1)).toBe('2027-01')
    expect(addMonths('2026-01', -1)).toBe('2025-12')
    expect(addMonths('2026-10', -14)).toBe('2025-08')
    expect(monthOf('2026-10-15')).toBe('2026-10')
  })

  it('fetches a five-row month in one request and a six-row one in two', () => {
    const five = monthGrid('2026-10')
    expect(fetchWindows(five[0], five.at(-1) ?? '')).toHaveLength(1)

    const six = monthGrid('2026-08')
    const windows = fetchWindows(six[0], six.at(-1) ?? '')
    expect(windows).toHaveLength(2)
    expect(windows.every((w) => span(w) <= MAX_FETCH_DAYS)).toBe(true)
    // Back to back, no gap and no overlap, covering the padded range.
    expect(windows[1].from).toBe(windows[0].to)
    const whole = fetchWindow(six[0], six.at(-1) ?? '')
    expect(windows[0].from).toBe(whole.from)
    expect(windows[1].to).toBe(whole.to)
  })

  it('runs the agenda from the selected day to the end of the range', () => {
    const grid = monthGrid('2026-10')
    expect(agendaDays(grid, '2026-10-30')).toEqual([
      '2026-10-30',
      '2026-10-31',
      '2026-11-01',
    ])
    expect(agendaDays(grid, '2027-01-01')).toEqual(grid)
  })

  it('labels months, agenda days and short codes', () => {
    expect(monthLabel('2026-10', 'en-GB')).toBe('October 2026')
    expect(monthLabel('2026-10', 'en-GB', false)).toBe('October')
    expect(agendaDayLabel('2026-10-13', 'en-GB')).toBe('Tue 13 Oct')
    expect(shortCode(2, 5)).toBe('S2 · E5')
  })
})
