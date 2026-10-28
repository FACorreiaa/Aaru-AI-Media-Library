import { describe, expect, it } from 'vitest'
import { visitorHeaders } from './visitor'

describe('visitorHeaders', () => {
  it('names the visitor with the Worker secret', () => {
    expect(visitorHeaders('203.0.113.7', 's3cret')).toEqual({
      'X-Aaru-Visitor': '203.0.113.7',
      'X-Aaru-Web-Secret': 's3cret',
    })
    expect(visitorHeaders('2001:db8::1', 's3cret')).toEqual({
      'X-Aaru-Visitor': '2001:db8::1',
      'X-Aaru-Web-Secret': 's3cret',
    })
  })

  it('sends nothing without a secret or a plain address', () => {
    for (const [address, secret] of [
      ['203.0.113.7', undefined],
      ['203.0.113.7', ''],
      [undefined, 's3cret'],
      [null, 's3cret'],
      ['not an ip', 's3cret'],
      ['1.2.3.4, 5.6.7.8', 's3cret'],
    ] as const)
      expect(visitorHeaders(address, secret)).toEqual({})
  })
})
