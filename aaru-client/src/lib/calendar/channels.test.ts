import { describe, expect, it } from 'vitest'
import { OTHER_CHANNEL, dayAndTime, groupByChannel } from './channels'
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

describe('group by channel (CAL-005)', () => {
  const on = (network: string | undefined, overrides: Partial<CalendarEntry>) =>
    entry({
      ...overrides,
      title: { ...entry().title, network, title: network ?? 'Untitled' },
    })

  it('orders channels by episode count, then name, with "Other" last', () => {
    const groups = groupByChannel([
      on(undefined, { number: 1 }),
      on(undefined, { number: 2 }),
      on(undefined, { number: 3 }),
      on('HBO', { number: 1 }),
      on('Netflix', { number: 1 }),
      on('Netflix', { number: 2 }),
      on('Apple TV+', { number: 1 }),
    ])
    expect(groups.map((g) => g.channel)).toEqual([
      'Netflix',
      'Apple TV+',
      'HBO',
      OTHER_CHANNEL,
    ])
    expect(groups.map((g) => g.entries.length)).toEqual([2, 1, 1, 3])
  })

  it('puts a blank network under "Other"', () => {
    const groups = groupByChannel([on('  ', {}), on(undefined, { number: 4 })])
    expect(groups).toHaveLength(1)
    expect(groups[0].channel).toBe(OTHER_CHANNEL)
  })

  it('orders a channel’s episodes by air time, then season and episode', () => {
    const groups = groupByChannel([
      on('FX', { airsAt: '2026-10-17T01:00:00Z', season: 1, number: 1 }),
      on('FX', { airsAt: '2026-10-16T00:00:00Z', season: 2, number: 2 }),
      on('FX', { airsAt: '2026-10-16T00:00:00Z', season: 2, number: 1 }),
      on('FX', { airsAt: '2026-10-16T00:00:00Z', season: 1, number: 9 }),
    ])
    expect(
      groups[0].entries.map((e) => `${e.airsAt} ${e.season}x${e.number}`),
    ).toEqual([
      '2026-10-16T00:00:00Z 1x9',
      '2026-10-16T00:00:00Z 2x1',
      '2026-10-16T00:00:00Z 2x2',
      '2026-10-17T01:00:00Z 1x1',
    ])
  })

  it('is empty for no entries', () => {
    expect(groupByChannel([])).toEqual([])
  })

  it('shows the day and, when exact, the time in the viewer’s zone', () => {
    const timed = entry({ airsAt: '2026-10-16T02:00:00Z', airTimeKnown: true })
    expect(dayAndTime(timed, 'America/New_York', 'en-GB')).toBe(
      'Thu 15 Oct · 22:00',
    )
    const dateOnly = entry({ airsAt: '2026-10-16T00:00:00Z' })
    expect(dayAndTime(dateOnly, 'America/Los_Angeles', 'en-GB')).toBe(
      'Fri 16 Oct',
    )
  })
})
