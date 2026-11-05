import { describe, expect, it } from 'vitest'
import { plusLine } from './model'

describe('plus', () => {
  it('reads Plus as active with its renewal', () => {
    expect(
      plusLine({
        plus: true,
        expiresAt: '2026-11-03T12:00:00Z',
        appAccountToken: 'u',
        capture: { used: 7, resetsAt: '2026-11-01T00:00:00Z' },
      }),
    ).toBe('Active · renews November 3')
  })
})
