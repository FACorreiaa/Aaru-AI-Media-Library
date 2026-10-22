import { describe, expect, it, vi } from 'vitest'
import { fakeBrowser } from 'wxt/testing/fake-browser'
import type { ErrorEvent } from '@sentry/browser'
import { makeDeliver, reportingAllowed } from './deliver'
import { REPORT } from '../protocol'
import { BUILD_REPORTING, parseContentError, toContentError } from './config'
import { contentReporter } from './content'
import { createReporter, envelopeEndpoint } from './reporter'
import { scrubEvent, scrubText, scrubUrl } from './scrub'

const FAKE_DSN = 'https://publickey@o0.ingest.de.sentry.io/42'
const config = { dsn: FAKE_DSN, environment: 'test', release: 'abc123' }

describe('scrubUrl', () => {
  it('keeps only the origin of a streaming page', () => {
    expect(scrubUrl('https://www.netflix.com/watch/12345?trackId=9')).toBe(
      'https://www.netflix.com',
    )
    expect(scrubUrl('https://www.disneyplus.com/play/0c8f-4e2a#t=120')).toBe(
      'https://www.disneyplus.com',
    )
    expect(
      scrubUrl('https://www.primevideo.com/detail/0ABC/ref=atv_dp?autoplay=1'),
    ).toBe('https://www.primevideo.com')
    expect(
      scrubUrl('https://www.amazon.co.uk/gp/video/detail/B0XYZ/ref=x'),
    ).toBe('https://www.amazon.co.uk')
  })

  it('keeps the path elsewhere, without the query or fragment', () => {
    expect(scrubUrl('https://aaruapp.com/connect/extension?code=1#x')).toBe(
      'https://aaruapp.com/connect/extension',
    )
    expect(
      scrubUrl('chrome-extension://abcdef/content-scripts/streaming.js?v=1'),
    ).toBe('chrome-extension://abcdef/content-scripts/streaming.js')
  })

  it('scrubs URLs inside messages', () => {
    expect(
      scrubText('Cannot read title at https://www.netflix.com/watch/12345?x=1'),
    ).toBe('Cannot read title at https://www.netflix.com')
  })
})

describe('scrubEvent', () => {
  const event: ErrorEvent = {
    type: undefined,
    message: 'failed on https://www.netflix.com/watch/12345',
    request: {
      url: 'https://www.netflix.com/watch/12345?trackId=9',
      headers: { Referer: 'https://www.netflix.com/watch/12345' },
      cookies: { NetflixId: 'secret' },
      data: 'body',
    },
    user: { id: 'someone' },
    breadcrumbs: [{ category: 'navigation', data: { to: '/watch/12345' } }],
    extra: { href: 'https://www.netflix.com/watch/12345' },
  }
  const scrubbed = scrubEvent(structuredClone(event))

  it('reports the page as its origin, with nothing else from the request', () => {
    expect(scrubbed.request).toEqual({ url: 'https://www.netflix.com' })
  })

  it('drops the user, breadcrumbs and extra data', () => {
    expect(scrubbed.user).toBeUndefined()
    expect(scrubbed.breadcrumbs).toBeUndefined()
    expect(scrubbed.extra).toBeUndefined()
  })

  it('leaves no trace of what was playing', () => {
    expect(JSON.stringify(scrubbed)).not.toContain('12345')
    expect(JSON.stringify(scrubbed)).not.toContain('secret')
  })
})

describe('createReporter (background)', () => {
  it('has no DSN in a build without one', () => {
    expect(BUILD_REPORTING.dsn).toBe('')
  })

  it('does nothing without a DSN', () => {
    const send = vi.fn()
    const reporter = createReporter({
      send,
      version: '0.1.0',
      config: { ...config, dsn: '' },
    })
    reporter.capture(new Error('boom'))
    reporter.captureContent({ name: 'Error', message: 'x' }, undefined)
    expect(reporter.guard(() => 1)()).toBe(1)
    expect(send).not.toHaveBeenCalled()
  })

  it('reports its own errors, tagged as the background', async () => {
    const send = vi.fn(() => Promise.resolve({ statusCode: 200 }))
    const reporter = createReporter({ send, version: '0.1.0', config })
    const failing = reporter.guard(() => {
      throw new Error('stop failed')
    })
    expect(failing()).toBeUndefined()
    await vi.waitFor(() => expect(send).toHaveBeenCalledTimes(1))
    const body = (send.mock.calls[0] as unknown as [string])[0]
    expect(body).toContain('"context":"background"')
    expect(body).toContain('"release":"abc123"')
    expect(body).toContain('stop failed')
  })

  it("sends a content script's error with the site origin only", async () => {
    const send = vi.fn(() => Promise.resolve({ statusCode: 200 }))
    const reporter = createReporter({ send, version: '0.1.0', config })
    reporter.captureContent(
      toContentError(
        new Error('no title on https://www.netflix.com/watch/12345?x=1'),
      ),
      'https://www.netflix.com/watch/12345?trackId=9',
    )
    await vi.waitFor(() => expect(send).toHaveBeenCalledTimes(1))
    const body = (send.mock.calls[0] as unknown as [string])[0]
    expect(body).toContain('"site":"https://www.netflix.com"')
    expect(body).toContain('"context":"content"')
    expect(body).not.toContain('12345')
    expect(body).not.toContain('trackId')
  })
})

describe('contentReporter', () => {
  it('sends nothing without a DSN', () => {
    const sendMessage = vi.spyOn(fakeBrowser.runtime, 'sendMessage')
    contentReporter({ ...config, dsn: '' }).capture(new Error('boom'))
    expect(sendMessage).not.toHaveBeenCalled()
  })

  it('hands the background the error, and nothing about the page', () => {
    const sendMessage = vi
      .spyOn(fakeBrowser.runtime, 'sendMessage')
      .mockResolvedValue(undefined)
    const reporter = contentReporter(config)
    reporter.guard(() => {
      throw new TypeError('overlay missing')
    })()
    expect(sendMessage).toHaveBeenCalledWith({
      type: REPORT,
      error: expect.objectContaining({
        name: 'TypeError',
        message: 'overlay missing',
      }),
    })
    const sent = JSON.stringify(sendMessage.mock.calls[0])
    expect(sent).not.toContain('location')
  })
})

describe('parseContentError', () => {
  it('accepts only a name and a message, capped', () => {
    expect(parseContentError({ name: 'Error', message: 'x' })).toEqual({
      name: 'Error',
      message: 'x',
      stack: undefined,
    })
    expect(parseContentError({ message: 1 })).toBeNull()
    expect(parseContentError('boom')).toBeNull()
    expect(
      parseContentError({ name: 'E', message: 'm'.repeat(5000) })?.message,
    ).toHaveLength(1000)
  })
})

describe('envelopeEndpoint', () => {
  it('turns a DSN into its ingest URL', () => {
    expect(envelopeEndpoint(FAKE_DSN)).toBe(
      'https://o0.ingest.de.sentry.io/api/42/envelope/?sentry_version=7&sentry_key=publickey',
    )
    expect(envelopeEndpoint('not a dsn')).toBeNull()
  })
})

describe('makeDeliver', () => {
  const ok = () => Promise.resolve(new Response(null, { status: 200 }))

  it('posts nothing without a DSN', async () => {
    const post = vi.fn(ok)
    const send = makeDeliver(
      { ...config, dsn: '' },
      () => Promise.resolve(true),
      post,
    )
    expect(await send('{}')).toBeUndefined()
    expect(post).not.toHaveBeenCalled()
  })

  it('posts nothing when the user did not allow it', async () => {
    const post = vi.fn(ok)
    const send = makeDeliver(config, () => Promise.resolve(false), post)
    expect(await send('{}')).toBeUndefined()
    expect(post).not.toHaveBeenCalled()
  })

  it('posts without cookies or a referrer', async () => {
    const post = vi.fn(ok)
    const send = makeDeliver(config, () => Promise.resolve(true), post)
    expect(await send('{}')).toEqual({ statusCode: 200 })
    expect(post).toHaveBeenCalledWith(
      'https://o0.ingest.de.sentry.io/api/42/envelope/?sentry_version=7&sentry_key=publickey',
      expect.objectContaining({
        method: 'POST',
        body: '{}',
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
      }),
    )
  })
})

describe('reportingAllowed', () => {
  it('is always yes outside Firefox', async () => {
    expect(await reportingAllowed(false)).toBe(true)
  })

  it('in Firefox, follows the technical-data choice', async () => {
    const getAll = vi.spyOn(fakeBrowser.permissions, 'getAll')
    getAll.mockResolvedValueOnce({ data_collection: [] } as never)
    expect(await reportingAllowed(true)).toBe(false)
    getAll.mockResolvedValueOnce({
      data_collection: ['technicalAndInteraction'],
    } as never)
    expect(await reportingAllowed(true)).toBe(true)
    getAll.mockResolvedValueOnce({} as never)
    expect(await reportingAllowed(true)).toBe(false)
  })
})
