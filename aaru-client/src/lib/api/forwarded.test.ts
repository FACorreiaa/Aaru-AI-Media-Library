import { describe, expect, it } from 'vitest'
import { forwardedFor } from './forwarded'

describe('forwardedFor', () => {
  it('passes a visitor address on', () => {
    expect(forwardedFor('203.0.113.7')).toEqual({
      'X-Forwarded-For': '203.0.113.7',
    })
    expect(forwardedFor('2001:db8::1')).toEqual({
      'X-Forwarded-For': '2001:db8::1',
    })
  })

  it('sends nothing for a missing or odd value', () => {
    for (const value of [undefined, null, '', 'not an ip', '1.2.3.4, 5.6.7.8'])
      expect(forwardedFor(value)).toEqual({})
  })
})
