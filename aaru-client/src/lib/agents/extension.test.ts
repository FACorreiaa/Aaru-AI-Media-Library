import { describe, expect, it } from 'vitest'
import { PING, READY, TOKEN, extensionMessage } from './extension'

describe('extension handshake', () => {
  const window = {}
  const self = { origin: 'https://aaruapp.com', window }

  it('reads only its own message types from this window and origin', () => {
    const from = (
      data: unknown,
      origin = self.origin,
      source: unknown = window,
    ) =>
      extensionMessage(
        { data, origin, source: source as MessageEventSource },
        self,
      )
    expect(from({ type: READY, version: '1.0.0' })).toEqual({
      type: READY,
      version: '1.0.0',
    })
    expect(from({ type: PING })).toEqual({ type: PING })
    expect(
      from({ type: TOKEN, secret: 'x' }, 'https://evil.example'),
    ).toBeNull()
    expect(from({ type: READY }, self.origin, {})).toBeNull()
    expect(from({ type: 'something-else' })).toBeNull()
    expect(from('aaru-extension:ready')).toBeNull()
    expect(from(null)).toBeNull()
  })
})
