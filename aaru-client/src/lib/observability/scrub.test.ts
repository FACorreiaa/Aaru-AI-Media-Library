import { describe, expect, it } from 'vitest'
import type { ErrorEvent } from '@sentry/browser'
import { scrubBreadcrumb, scrubEvent, scrubText, scrubUrl } from './scrub'

describe('scrubUrl', () => {
  it('drops the query string and the fragment', () => {
    expect(
      scrubUrl('https://aaruapp.com/app/library?status=finished#top'),
    ).toBe('https://aaruapp.com/app/library')
  })

  it('keeps an address without either as it is', () => {
    expect(scrubUrl('https://aaruapp.com/app/title/42')).toBe(
      'https://aaruapp.com/app/title/42',
    )
  })

  it('cuts relative addresses at the first ? or #', () => {
    expect(scrubUrl('/assets/main.js?v=3')).toBe('/assets/main.js')
    expect(scrubUrl('/app#token=abc')).toBe('/app')
  })
})

describe('scrubText', () => {
  it('scrubs every URL inside a message', () => {
    expect(
      scrubText(
        'GET https://api.aaruapp.com/v1/search?q=dune failed, from https://aaruapp.com/a#b',
      ),
    ).toBe(
      'GET https://api.aaruapp.com/v1/search failed, from https://aaruapp.com/a',
    )
  })
})

describe('scrubEvent', () => {
  const event: ErrorEvent = {
    type: undefined,
    message: 'Failed at https://aaruapp.com/app?session=secret',
    request: {
      url: 'https://aaruapp.com/app/library?q=private#frag',
      method: 'GET',
      cookies: { aaru_session: 'aaru_tok_123' },
      headers: { Cookie: 'aaru_session=aaru_tok_123', Referer: 'x' },
      data: { password: 'hunter2' },
      query_string: 'q=private',
    },
    user: { id: '1', email: 'someone@example.com', ip_address: '1.2.3.4' },
    exception: {
      values: [
        {
          type: 'Error',
          value: 'Could not load https://aaruapp.com/app/title/1?ref=mail',
          stacktrace: {
            frames: [
              {
                filename: 'https://aaruapp.com/assets/app.js?v=1',
                abs_path: 'https://aaruapp.com/assets/app.js?v=1',
                vars: { token: 'aaru_tok_123' },
              },
            ],
          },
        },
      ],
    },
    breadcrumbs: [
      {
        category: 'navigation',
        data: { from: '/app?x=1', to: '/app/library?status=finished' },
      },
      { category: 'console', message: 'token aaru_tok_123' },
      { category: 'ui.click', message: 'button.sign-in' },
      { category: 'fetch', data: { url: 'https://api.aaruapp.com/v1?x=1' } },
    ],
  }

  const scrubbed = scrubEvent(structuredClone(event))

  it('keeps only the scrubbed URL and the method of the request', () => {
    expect(scrubbed.request).toEqual({
      url: 'https://aaruapp.com/app/library',
      method: 'GET',
    })
  })

  it('drops cookies, headers and the body', () => {
    const request = scrubbed.request as Record<string, unknown>
    expect(request.cookies).toBeUndefined()
    expect(request.headers).toBeUndefined()
    expect(request.data).toBeUndefined()
    expect(request.query_string).toBeUndefined()
  })

  it('sends no user', () => {
    expect(scrubbed.user).toBeUndefined()
  })

  it('scrubs URLs in the message, exceptions and stack frames', () => {
    expect(scrubbed.message).toBe('Failed at https://aaruapp.com/app')
    const value = scrubbed.exception?.values?.[0]
    expect(value?.value).toBe('Could not load https://aaruapp.com/app/title/1')
    const frame = value?.stacktrace?.frames?.[0]
    expect(frame?.filename).toBe('https://aaruapp.com/assets/app.js')
    expect(frame?.abs_path).toBe('https://aaruapp.com/assets/app.js')
    expect(frame?.vars).toBeUndefined()
  })

  it('keeps navigation breadcrumbs without their query, and drops the rest', () => {
    expect(scrubbed.breadcrumbs).toEqual([
      {
        category: 'navigation',
        data: { from: '/app', to: '/app/library' },
        message: undefined,
      },
    ])
  })

  it('never sends the session token', () => {
    expect(JSON.stringify(scrubbed)).not.toContain('aaru_tok_123')
    expect(JSON.stringify(scrubbed)).not.toContain('secret')
  })
})

describe('scrubBreadcrumb', () => {
  it('drops console breadcrumbs', () => {
    expect(scrubBreadcrumb({ category: 'console', message: 'x' })).toBeNull()
  })
})
