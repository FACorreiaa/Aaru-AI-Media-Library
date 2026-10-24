import { describe, expect, it } from 'vitest'
import { malConnectedLabel, malLastRead, malResult } from './model'

describe('malResult', () => {
  it('reads the redirect back', () => {
    expect(malResult('connected')?.ok).toBe(true)
    expect(malResult('denied')?.ok).toBe(false)
    expect(malResult('failed')?.message).toContain('Try again')
    expect(malResult(undefined)).toBeNull()
    expect(malResult('other')).toBeNull()
  })
})

describe('malConnectedLabel', () => {
  it('names the account and the day it connected', () => {
    expect(
      malConnectedLabel({
        connected: true,
        needsReconnect: false,
        removed: [],
        username: 'ana',
        connectedAt: '2026-10-23T10:00:00Z',
      }),
    ).toBe('Connected as ana · since 23 Oct')
  })

  it('leaves out what it does not know', () => {
    expect(
      malConnectedLabel({
        connected: true,
        needsReconnect: false,
        removed: [],
      }),
    ).toBe('Connected')
  })
})

describe('malLastRead', () => {
  const now = new Date('2026-10-24T12:00:00Z')
  const read = (pulledAt?: string) =>
    malLastRead(
      { connected: true, needsReconnect: false, removed: [], pulledAt },
      now,
    )

  it('says how long ago the list was read back', () => {
    expect(read()).toBeNull()
    expect(read('2026-10-24T11:59:40Z')).toBe('Last read just now')
    expect(read('2026-10-24T11:55:00Z')).toBe('Last read 5 min ago')
    expect(read('2026-10-24T06:00:00Z')).toBe('Last read 6 h ago')
    expect(read('2026-10-23T11:00:00Z')).toBe('Last read yesterday')
    expect(read('2026-10-20T12:00:00Z')).toBe('Last read 4 days ago')
  })
})
