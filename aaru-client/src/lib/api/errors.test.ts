import { describe, expect, it } from 'vitest'
import { errorMessage } from './errors'

describe('errorMessage', () => {
  it('uses the server message from the shared error shape', () => {
    expect(
      errorMessage(
        { code: 'unauthorized', message: 'This code is wrong.' },
        'x',
      ),
    ).toBe('This code is wrong.')
  })

  it('falls back when the body is missing, empty, or not an error', () => {
    expect(errorMessage(undefined, 'fallback')).toBe('fallback')
    expect(errorMessage({ code: 'x', message: '' }, 'fallback')).toBe(
      'fallback',
    )
    expect(errorMessage('boom', 'fallback')).toBe('fallback')
  })
})
