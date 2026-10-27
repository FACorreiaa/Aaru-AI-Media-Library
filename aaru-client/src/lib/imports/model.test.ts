import { describe, expect, it } from 'vitest'
import {
  appliedMessage,
  importSteps,
  isListens,
  isWorking,
  listensAppliedMessage,
  sourceLabel,
  stateLabel,
  traktResult,
} from './model'
import type { components } from '../api/schema'

type Job = components['schemas']['ImportJob']

const job = (state: Job['state'], extra: Partial<Job> = {}): Job => ({
  id: 'j',
  source: 'goodreads_csv',
  state,
  stats: { created: 3, updated: 1, skipped: 0, unmatched: 2 },
  createdAt: '2026-10-15T00:00:00Z',
  updatedAt: '2026-10-15T00:00:00Z',
  rowsTotal: 0,
  rowsMatched: 0,
  ...extra,
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

describe('Trakt sign-in result', () => {
  it('reads what Trakt sent back and ignores anything else', () => {
    expect(traktResult('connected')?.ok).toBe(true)
    expect(traktResult('denied')?.ok).toBe(false)
    expect(traktResult('failed')?.message).toContain('two apps')
    expect(traktResult(undefined)).toBeNull()
    expect(traktResult('<script>')).toBeNull()
  })
})

describe('import ledger (IMP-017)', () => {
  const mal = (state: Job['state'], extra: Partial<Job> = {}) =>
    job(state, { source: 'mal_xml', rowsTotal: 2001, ...extra })
  const states = (j: Job) => importSteps(j).map((s) => s.state)

  it('starts with the file read and the job in line', () => {
    const steps = importSteps(mal('queued'))
    expect(steps[0]).toMatchObject({
      label: 'Read your file',
      detail: '2,001 entries',
      state: 'done',
    })
    expect(steps[1]).toMatchObject({
      state: 'current',
      detail: 'Starts in a few seconds.',
    })
    expect(states(mal('queued'))).toEqual([
      'done',
      'current',
      'todo',
      'todo',
      'todo',
    ])
    expect(stateLabel(mal('queued'))).toBe('In line')
  })

  it('shows a retry as a pause, with the reason', () => {
    const paused = mal('queued', {
      errorSummary: 'anilist could not be reached while matching titles.',
    })
    expect(importSteps(paused)[1].detail).toContain('Paused: anilist')
    expect(stateLabel(paused)).toBe('Paused, retrying soon')
  })

  it('counts matched rows while running, then checks the shelf', () => {
    const running = mal('running', { rowsMatched: 840 })
    const match = importSteps(running)[2]
    expect(match).toMatchObject({ state: 'current', detail: '840 of 2,001' })
    expect(match.progress).toBeCloseTo(840 / 2001)
    expect(stateLabel(running)).toBe('Matching titles… 41%')
    expect(states(mal('running', { rowsMatched: 2001 }))).toEqual([
      'done',
      'done',
      'done',
      'current',
      'todo',
    ])
  })

  it('reads an account first when the rows are not known yet', () => {
    const trakt = job('running', { source: 'trakt' })
    expect(importSteps(trakt)[0]).toMatchObject({
      label: 'Read your Trakt library',
      state: 'current',
    })
    expect(stateLabel(trakt)).toBe('Matching titles…')
  })

  it('has no ledger once there is a plan', () => {
    expect(importSteps(mal('planned'))).toEqual([])
  })
})

describe('applied import toast', () => {
  it('counts what was added, and what was filled in when there is any', () => {
    const stats = { created: 12, updated: 0, skipped: 4, unmatched: 1 }
    expect(appliedMessage(stats)).toBe('Imported 12 titles')
    expect(appliedMessage({ ...stats, created: 1, updated: 3 })).toBe(
      'Imported 1 title · filled in 3',
    )
  })
})

describe('listening history imports (MUS-004)', () => {
  const lastfm = (state: Job['state'], extra: Partial<Job> = {}) =>
    job(state, { source: 'lastfm', filename: 'rj', ...extra })

  it('tells a listening import from a library one', () => {
    expect(isListens(lastfm('queued'))).toBe(true)
    expect(isListens(job('queued', { source: 'spotify_json' }))).toBe(true)
    expect(isListens(job('queued'))).toBe(false)
    expect(sourceLabel(job('planned', { source: 'youtube_takeout' }))).toBe(
      'YouTube',
    )
  })

  it('reads an account page by page, then checks the log', () => {
    const reading = importSteps(lastfm('running', { rowsTotal: 400 }))
    expect(reading[0]).toMatchObject({
      label: 'Read your Last.fm listens',
      detail: '400 plays so far',
      state: 'current',
    })
    expect(reading[2]).toMatchObject({
      label: 'Check against your listening log',
      state: 'todo',
    })
    expect(stateLabel(lastfm('running'))).toBe('Reading listens…')
    expect(importSteps(lastfm('queued'))[0]?.state).toBe('todo')
  })

  it('has read a file before it is in line', () => {
    const steps = importSteps(
      job('running', { source: 'spotify_json', rowsTotal: 1 }),
    )
    expect(steps[0]).toMatchObject({ detail: '1 play', state: 'done' })
    expect(steps[2]?.state).toBe('current')
  })

  it('says how many listens were added', () => {
    expect(
      listensAppliedMessage({
        created: 1204,
        updated: 0,
        skipped: 3,
        unmatched: 0,
      }),
    ).toBe('Added 1,204 listens')
    expect(
      listensAppliedMessage({
        created: 1,
        updated: 0,
        skipped: 0,
        unmatched: 0,
      }),
    ).toBe('Added 1 listen')
  })
})
