import { describe, expect, it } from 'vitest'
import {
  NO_FILTER,
  activeCount,
  applyFilter,
  catchUp,
  missedLine,
} from './filters'
import type { CalendarEntry } from './model'

const entry = (overrides: Partial<CalendarEntry> = {}): CalendarEntry => ({
  libraryItemId: 'andor',
  title: { id: 't1', type: 'show', title: 'Andor', isAnime: false, ids: {} },
  season: 1,
  number: 2,
  airsAt: '2026-10-14T00:00:00Z',
  airTimeKnown: false,
  watched: false,
  kind: 'regular',
  runtimeMinutes: 45,
  ...overrides,
})

describe('calendar filters', () => {
  const premiere = entry({ number: 1, kind: 'premiere' })
  const finale = entry({ number: 12, kind: 'finale', watched: true })
  const anime = entry({
    libraryItemId: 'frieren',
    title: { id: 't2', type: 'show', title: 'Frieren', isAnime: true, ids: {} },
  })

  it('keeps everything with no filter on', () => {
    expect(applyFilter([premiere, finale, anime], NO_FILTER)).toHaveLength(3)
    expect(activeCount(NO_FILTER)).toBe(0)
  })

  it('hides watched, keeps premieres or finales, and splits anime from shows', () => {
    const all = [premiere, finale, anime]
    expect(applyFilter(all, { hideWatched: true })).toEqual([premiere, anime])
    expect(applyFilter(all, { hideWatched: false, only: 'finales' })).toEqual([
      finale,
    ])
    expect(applyFilter(all, { hideWatched: false, kind: 'anime' })).toEqual([
      anime,
    ])
    expect(applyFilter(all, { hideWatched: false, kind: 'show' })).toEqual([
      premiere,
      finale,
    ])
    expect(activeCount({ hideWatched: true, only: 'premieres' })).toBe(2)
  })

  it('does not count grouping by channel as a filter (CAL-005)', () => {
    const grouped = { hideWatched: false, group: 'channel' } as const
    expect(activeCount(grouped)).toBe(0)
    expect(applyFilter([premiere, finale, anime], grouped)).toHaveLength(3)
  })
})

describe('catch-up', () => {
  const now = new Date('2026-10-21T12:00:00Z')

  it('groups aired, unwatched episodes by show, oldest miss first', () => {
    const shows = catchUp(
      [
        entry({ number: 3, airsAt: '2026-10-20T00:00:00Z' }),
        entry({ number: 2, airsAt: '2026-10-13T00:00:00Z' }),
        entry({ number: 4, airsAt: '2026-10-27T00:00:00Z' }),
        entry({ number: 1, airsAt: '2026-10-06T00:00:00Z', watched: true }),
        entry({
          libraryItemId: 'frieren',
          title: {
            id: 't2',
            type: 'show',
            title: 'Frieren',
            isAnime: true,
            ids: {},
          },
          airsAt: '2026-10-18T15:00:00Z',
        }),
      ],
      now,
    )
    expect(shows.map((show) => show.title.title)).toEqual(['Andor', 'Frieren'])
    expect(shows[0].episodes.map((e) => e.number)).toEqual([2, 3])
  })

  it('sums the time left only when every runtime is known', () => {
    const [show] = catchUp(
      [
        entry({
          number: 2,
          airsAt: '2026-10-13T00:00:00Z',
          runtimeMinutes: 50,
        }),
        entry({
          number: 3,
          airsAt: '2026-10-20T00:00:00Z',
          runtimeMinutes: 85,
        }),
      ],
      now,
    )
    expect(missedLine(show)).toBe('2 episodes · 2 h 15 min')
    const [unknown] = catchUp(
      [entry({ airsAt: '2026-10-13T00:00:00Z', runtimeMinutes: undefined })],
      now,
    )
    expect(missedLine(unknown)).toBe('1 episode')
  })
})
