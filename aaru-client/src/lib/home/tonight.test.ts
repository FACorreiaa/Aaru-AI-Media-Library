import { describe, expect, it } from 'vitest'
import { composeTonight, fieldLine, pickEpisode, pickReason } from './tonight'
import type { ContinueEntry } from './model'
import type { CalendarEntry } from '../calendar/model'

const NOW = new Date('2026-10-21T18:00:00Z')

function show(n: number) {
  return {
    id: `00000000-0000-4000-8000-0000000000${String(n).padStart(2, '0')}`,
    type: 'show' as const,
    title: `Show ${n}`,
    isAnime: false,
    ids: {},
  }
}

function continuing(n: number, overrides: Partial<ContinueEntry> = {}) {
  return {
    libraryItemId: `item-${n}`,
    title: show(n),
    next: { season: 4, number: 3 },
    nextName: 'Hello',
    nextRuntimeMinutes: 47,
    remainingCount: 3,
    remainingMinutes: 140,
    isFinale: false,
    ...overrides,
  } satisfies ContinueEntry
}

function airing(n: number, overrides: Partial<CalendarEntry> = {}) {
  return {
    libraryItemId: `item-${n}`,
    title: show(n),
    season: 2,
    number: 5,
    airsAt: '2026-10-21T20:00:00Z',
    airTimeKnown: true,
    watched: false,
    kind: 'regular',
    ...overrides,
  } satisfies CalendarEntry
}

describe('composeTonight', () => {
  it('is null with nothing to watch', () => {
    expect(composeTonight([], [], NOW, 'UTC')).toBeNull()
  })

  it('leads with Continue watching, then the first airing today', () => {
    const tonight = composeTonight(
      [continuing(1), continuing(2)],
      [airing(3, { airsAt: '2026-10-21T22:00:00Z' }), airing(4)],
      NOW,
      'UTC',
    )
    expect(tonight?.primary).toEqual({ kind: 'continue', entry: continuing(1) })
    expect(tonight?.also).toEqual({ kind: 'airing', entry: airing(4) })
  })

  it('falls back to the second show when nothing airs today', () => {
    const tonight = composeTonight(
      [continuing(1), continuing(2)],
      [airing(3, { airsAt: '2026-10-22T20:00:00Z' })],
      NOW,
      'UTC',
    )
    expect(tonight?.also).toEqual({ kind: 'continue', entry: continuing(2) })
  })

  it('never offers the same show twice, nor a watched airing', () => {
    const tonight = composeTonight(
      [continuing(1)],
      [airing(1), airing(2, { watched: true })],
      NOW,
      'UTC',
    )
    expect(tonight?.also).toBeNull()
  })

  it('starts from an airing when nothing is in progress', () => {
    const tonight = composeTonight([], [airing(5)], NOW, 'UTC')
    expect(tonight).toEqual({
      primary: { kind: 'airing', entry: airing(5) },
      also: null,
    })
  })

  it('takes a date-only airing as today by its date', () => {
    const tonight = composeTonight(
      [],
      [airing(6, { airsAt: '2026-10-21T00:00:00Z', airTimeKnown: false })],
      NOW,
      'Pacific/Honolulu',
    )
    expect(tonight?.primary.entry.libraryItemId).toBe('item-6')
  })
})

describe('labels', () => {
  it('names the episode and says why it is here', () => {
    const next = { kind: 'continue', entry: continuing(1) } as const
    expect(pickEpisode(next)).toBe('S4 · E3 · Hello')
    expect(pickReason(next)).toBe('47m · 3 left')
    const last = {
      kind: 'continue',
      entry: continuing(1, { remainingCount: 1, isFinale: true }),
    } as const
    expect(pickReason(last)).toBe('47m · Last one aired · Season finale')
  })

  it('gives an airing its time, or just the day', () => {
    const timed = {
      kind: 'airing',
      entry: airing(2, { runtimeMinutes: 44, kind: 'premiere' }),
    } as const
    expect(pickEpisode(timed)).toBe('S2 · E5')
    expect(pickReason(timed, 'UTC')).toBe('Airs 20:00 · 44m · Premiere')
    const dated = {
      kind: 'airing',
      entry: airing(2, { airTimeKnown: false }),
    } as const
    expect(pickReason(dated, 'UTC')).toBe('Airs today')
  })
})

describe('fieldLine', () => {
  it('leaves out what is zero', () => {
    expect(fieldLine('Tuesday evening', 3, 2)).toBe(
      'Tuesday evening · 3 in progress · 2 airing today',
    )
    expect(fieldLine('Tuesday', 0, 1)).toBe('Tuesday · 1 airing today')
    expect(fieldLine('Tuesday night', 0, 0)).toBe('Tuesday night')
  })
})
