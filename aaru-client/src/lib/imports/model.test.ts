import { describe, expect, it } from 'vitest'
import { isWorking, sourceLabel, stateLabel } from './model'
import type { components } from '../api/schema'

const job = (
  state: components['schemas']['ImportJob']['state'],
): components['schemas']['ImportJob'] => ({
  id: 'j',
  source: 'goodreads_csv',
  state,
  stats: { created: 3, updated: 1, skipped: 0, unmatched: 2 },
  createdAt: '2026-10-15T00:00:00Z',
  updatedAt: '2026-10-15T00:00:00Z',
})

describe('import labels', () => {
  it('polls only while the server is still matching', () => {
    expect(isWorking(job('queued'))).toBe(true)
    expect(isWorking(job('running'))).toBe(true)
    expect(isWorking(job('planned'))).toBe(false)
  })

  it('surfaces the unmatched count on a partial import', () => {
    expect(stateLabel(job('partial'))).toBe('Imported, 2 unmatched')
    expect(sourceLabel(job('planned'))).toBe('Goodreads')
  })
})
