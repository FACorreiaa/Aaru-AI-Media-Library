import { describe, expect, it, vi } from 'vitest'
import { BUILD_CONFIG, createBrowserReporter } from './browser'
import { scrubBreadcrumb, scrubEvent } from './scrub'
import { startSentry } from './sdk'
import { serverReportingOptions } from './server'

const FAKE_DSN = 'https://public@o0.ingest.de.sentry.io/0'

const sentry = vi.hoisted(() => {
  const integration = (name: string) => () => ({ name })
  return {
    init: vi.fn(),
    captureException: vi.fn(),
    eventFiltersIntegration: integration('EventFilters'),
    functionToStringIntegration: integration('FunctionToString'),
    browserApiErrorsIntegration: integration('BrowserApiErrors'),
    globalHandlersIntegration: integration('GlobalHandlers'),
    linkedErrorsIntegration: integration('LinkedErrors'),
    dedupeIntegration: integration('Dedupe'),
    httpContextIntegration: integration('HttpContext'),
    breadcrumbsIntegration: integration('Breadcrumbs'),
  }
})
vi.mock('@sentry/browser', () => sentry)

describe('browser error reporting', () => {
  it('has no DSN in a build without one', () => {
    expect(BUILD_CONFIG.dsn).toBe('')
  })

  it('loads nothing when the DSN is empty', async () => {
    const load = vi.fn()
    const reporter = createBrowserReporter(
      { dsn: '', environment: 'production', release: undefined },
      load,
    )
    await reporter.start()
    reporter.report(new Error('boom'))
    expect(load).not.toHaveBeenCalled()
  })

  it('loads the SDK once and sends what was caught before it arrived', async () => {
    const send = vi.fn()
    const load = vi.fn(() => Promise.resolve({ startSentry: () => send }))
    const reporter = createBrowserReporter(
      { dsn: FAKE_DSN, environment: 'beta', release: 'abc123' },
      load,
    )
    const early = new Error('before load')
    reporter.report(early)
    await Promise.all([reporter.start(), reporter.start()])
    expect(load).toHaveBeenCalledTimes(1)
    expect(send).toHaveBeenCalledWith(early)

    const late = new Error('after load')
    reporter.report(late)
    expect(send).toHaveBeenCalledWith(late)
  })

  it('keeps working without reporting when the chunk does not load', async () => {
    const reporter = createBrowserReporter(
      { dsn: FAKE_DSN, environment: 'beta', release: undefined },
      () => Promise.reject(new Error('offline')),
    )
    await expect(reporter.start()).resolves.toBeUndefined()
  })
})

describe('the Sentry chunk', () => {
  it('reports errors only, scrubbed', () => {
    const capture = startSentry({
      dsn: FAKE_DSN,
      environment: 'beta',
      release: 'abc123',
    })
    const options = sentry.init.mock.calls[0]?.[0]
    expect(options).toMatchObject({
      dsn: FAKE_DSN,
      environment: 'beta',
      release: 'abc123',
      tracesSampleRate: 0,
      defaultIntegrations: false,
      sendClientReports: false,
      dataCollection: { userInfo: false, cookies: false, httpHeaders: false },
      beforeSend: scrubEvent,
      beforeBreadcrumb: scrubBreadcrumb,
    })
    const names = (options.integrations as { name: string }[]).map(
      (i) => i.name,
    )
    for (const unwanted of [
      'Replay',
      'BrowserTracing',
      'BrowserSession',
      'Console',
      'Feedback',
      'BrowserProfiling',
      'CultureContext',
    ])
      expect(names).not.toContain(unwanted)

    const error = new Error('boom')
    capture(error)
    expect(sentry.captureException).toHaveBeenCalledWith(error)
  })
})

describe('Worker error reporting', () => {
  it('is off without a DSN', () => {
    expect(serverReportingOptions({ SENTRY_DSN: '' }, 'abc')).toBeUndefined()
  })

  it('keeps only the integrations that report errors', () => {
    const options = serverReportingOptions(
      { SENTRY_DSN: FAKE_DSN, CHANNEL: 'beta' },
      'abc',
    )
    expect(options).toMatchObject({
      dsn: FAKE_DSN,
      environment: 'beta',
      release: 'abc',
      tracesSampleRate: 0,
    })
    const pick = options?.integrations as (
      defaults: { name: string }[],
    ) => { name: string }[]
    const kept = pick(
      [
        'Dedupe',
        'EventFilters',
        'FunctionToString',
        'ConversationId',
        'LinkedErrors',
        'Fetch',
        'HttpServer',
        'RequestData',
        'Console',
      ].map((name) => ({ name })),
    ).map((i) => i.name)
    expect(kept).toEqual([
      'Dedupe',
      'EventFilters',
      'FunctionToString',
      'LinkedErrors',
      'RequestData',
    ])
  })
})
