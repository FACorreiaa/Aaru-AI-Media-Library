import { describe, expect, it } from 'vitest'
import { malConnectedLabel, malResult } from './model'

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
        username: 'ana',
        connectedAt: '2026-10-23T10:00:00Z',
      }),
    ).toBe('Connected as ana · since 23 Oct')
  })

  it('leaves out what it does not know', () => {
    expect(malConnectedLabel({ connected: true, needsReconnect: false })).toBe(
      'Connected',
    )
  })
})
