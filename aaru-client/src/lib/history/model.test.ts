import { describe, expect, it } from 'vitest'
import { actionBy, canUndo, whenLabel } from './model'
import type { Action } from './model'

const action = (patch: Partial<Action>): Action => ({
  id: '00000000-0000-0000-0000-000000000001',
  actor: 'user',
  kind: 'update',
  summary: 'Marked Severance watched',
  itemIds: [],
  createdAt: '2026-10-21T12:00:00Z',
  ...patch,
})

describe('actionBy', () => {
  it('names who made the write', () => {
    expect(actionBy(action({}))).toBe('You')
    expect(actionBy(action({ kind: 'import' }))).toBe('An import')
    expect(actionBy(action({ actor: 'agent' }))).toBe('Aaru')
    expect(
      actionBy(action({ actor: 'external_agent', agentName: 'Stremio' })),
    ).toBe('Stremio')
    expect(actionBy(action({ actor: 'external_agent' }))).toBe('A connection')
  })
})

describe('canUndo', () => {
  it('offers undo once, and never on an undo', () => {
    expect(canUndo(action({}))).toBe(true)
    expect(canUndo(action({ undoneAt: '2026-10-21T12:05:00Z' }))).toBe(false)
    expect(canUndo(action({ kind: 'undo' }))).toBe(false)
  })
})

describe('whenLabel', () => {
  const now = new Date(2026, 9, 21, 18, 0)
  it('says today and yesterday', () => {
    expect(
      whenLabel(new Date(2026, 9, 21, 9, 5).toISOString(), now, 'en-GB'),
    ).toBe('Today, 09:05')
    expect(
      whenLabel(new Date(2026, 9, 20, 23, 30).toISOString(), now, 'en-GB'),
    ).toBe('Yesterday, 23:30')
  })
  it('adds the year only when it is not this one', () => {
    expect(
      whenLabel(new Date(2026, 9, 3, 18, 40).toISOString(), now, 'en-GB'),
    ).toBe('3 Oct, 18:40')
    expect(
      whenLabel(new Date(2025, 9, 3, 18, 40).toISOString(), now, 'en-GB'),
    ).toBe('3 Oct 2025, 18:40')
  })
})
