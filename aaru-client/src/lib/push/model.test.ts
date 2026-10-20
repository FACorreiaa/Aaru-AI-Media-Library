import { describe, expect, it } from 'vitest'
import { keyBytes, pushSupport } from './model'

const full = {
  serviceWorker: true,
  pushManager: true,
  notification: true,
  iOS: false,
  standalone: false,
}

describe('push model', () => {
  it('needs the Home Screen on iOS, and every API elsewhere', () => {
    expect(pushSupport(full)).toBe('supported')
    expect(pushSupport({ ...full, iOS: true })).toBe('needs-install')
    expect(pushSupport({ ...full, iOS: true, standalone: true })).toBe(
      'supported',
    )
    expect(pushSupport({ ...full, pushManager: false })).toBe('unsupported')
  })

  it('decodes a base64url key without padding', () => {
    expect(Array.from(keyBytes('AQID_-8'))).toEqual([1, 2, 3, 255, 239])
  })
})
