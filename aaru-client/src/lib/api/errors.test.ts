import { describe, expect, it } from 'vitest'
import { errorMessage, isReauthRequired } from './errors'

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

describe('isReauthRequired', () => {
  const body = { code: 'reauth_required', message: 'Sign in again.' }
  it('is true for a 403 reauth_required', () => {
    expect(isReauthRequired(403, body)).toBe(true)
  })
  it('is false for other statuses, codes or bodies', () => {
    expect(isReauthRequired(401, body)).toBe(false)
    expect(isReauthRequired(403, { code: 'forbidden', message: 'No.' })).toBe(
      false,
    )
    expect(isReauthRequired(403, undefined)).toBe(false)
    expect(isReauthRequired(403, 'reauth_required')).toBe(false)
  })
})
