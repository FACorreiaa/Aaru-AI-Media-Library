import { describe, expect, it } from 'vitest'
import { captureHeadline, captureSend, waitingCaptures } from './model'
import type { components } from '../api/schema'

type Job = components['schemas']['ImportJob']

const job = (state: Job['state'], extra: Partial<Job> = {}): Job => ({
  id: 'j',
  source: 'capture',
  state,
  stats: { created: 5, updated: 2, skipped: 1, unmatched: 2 },
  createdAt: '2026-10-23T00:00:00Z',
  updatedAt: '2026-10-23T00:00:00Z',
  rowsTotal: 0,
  rowsMatched: 0,
  ...extra,
})

describe('capture', () => {
  it('sends a lone link as a link and anything else as text', () => {
    expect(captureSend('  ')).toBeNull()
    expect(captureSend(' https://www.themoviedb.org/movie/603 ')).toEqual({
      url: 'https://www.themoviedb.org/movie/603',
    })
    expect(captureSend('watch https://boxd.it/abc')).toEqual({
      text: 'watch https://boxd.it/abc',
    })
    expect(captureSend('Dune\nArrival')).toEqual({ text: 'Dune\nArrival' })
  })

  it('heads a plan with what it adds and what needs a pick', () => {
    expect(captureHeadline(job('running'))).toBeNull()
    expect(captureHeadline(job('planned'))).toBe('Add 7 · 2 need a pick')
    expect(
      captureHeadline(
        job('planned', {
          stats: { created: 1, updated: 0, skipped: 0, unmatched: 1 },
        }),
      ),
    ).toBe('Add 1 · 1 needs a pick')
    expect(
      captureHeadline(
        job('planned', {
          stats: { created: 0, updated: 0, skipped: 3, unmatched: 0 },
        }),
      ),
    ).toBe('Already in your library')
  })

  it('keeps captures being read or waiting for approval', () => {
    const jobs = [
      job('planned', { id: 'a' }),
      job('running', { id: 'b' }),
      job('succeeded', { id: 'c' }),
      job('failed', { id: 'd' }),
      job('planned', { id: 'e', source: 'letterboxd_csv' }),
    ]
    expect(waitingCaptures(jobs).map((j) => j.id)).toEqual(['a', 'b'])
  })
})
