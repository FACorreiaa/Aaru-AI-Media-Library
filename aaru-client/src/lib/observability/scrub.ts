import type { BrowserOptions, Breadcrumb, ErrorEvent } from '@sentry/browser'

/**
 * Error reporting sees errors and nothing else (docs/privacy.md). Every event and breadcrumb
 * passes through here on its way to Sentry, in the browser and in the Worker alike: URLs lose
 * their query string and fragment, the request keeps only its scrubbed URL and method (no
 * cookies, headers, query or body), and there is no user.
 */

/** Sentry's own collection switches, all off: what we keep is decided by `scrubEvent`. */
export const PRIVATE_DATA_COLLECTION: NonNullable<
  BrowserOptions['dataCollection']
> = {
  userInfo: false,
  cookies: false,
  httpHeaders: false,
  httpBodies: [],
  urlQueryParams: false,
  graphQL: { document: false, variables: false },
  genAI: { inputs: false, outputs: false },
  databaseQueryData: false,
  queues: false,
  stackFrameVariables: false,
}

/** `https://aaruapp.com/app/title/1?q=x#y` → `https://aaruapp.com/app/title/1`. */
export function scrubUrl(url: string): string {
  try {
    const parsed = new URL(url)
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:')
      return `${parsed.origin}${parsed.pathname}`
    parsed.search = ''
    parsed.hash = ''
    return parsed.toString()
  } catch {
    // A relative URL or a bare path: cut at the first `?` or `#`.
    return url.split(/[?#]/, 1)[0] ?? ''
  }
}

const URL_IN_TEXT = /\b(?:https?|wss?):\/\/[^\s"'<>`)\]]+/g

/** Scrubs every URL inside free text, such as an error message. */
export function scrubText(text: string): string {
  return text.replace(URL_IN_TEXT, (match) => scrubUrl(match))
}

/** Breadcrumb kinds that can carry what the user typed, saw or fetched. */
const DROPPED_CATEGORIES = new Set([
  'console',
  'ui.click',
  'ui.input',
  'fetch',
  'xhr',
])

/** Breadcrumb fields that hold an address, often a relative one (`/app?x=1`). */
const URL_KEYS = new Set(['url', 'from', 'to', 'href'])

export function scrubBreadcrumb(breadcrumb: Breadcrumb): Breadcrumb | null {
  if (breadcrumb.category && DROPPED_CATEGORIES.has(breadcrumb.category))
    return null
  const data: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(breadcrumb.data ?? {}))
    data[key] =
      typeof value !== 'string'
        ? value
        : URL_KEYS.has(key)
          ? scrubUrl(value)
          : scrubText(value)
  return {
    ...breadcrumb,
    message: breadcrumb.message ? scrubText(breadcrumb.message) : undefined,
    data: breadcrumb.data ? data : undefined,
  }
}

export function scrubEvent(event: ErrorEvent): ErrorEvent {
  const request = event.request
  const scrubbed: ErrorEvent = {
    ...event,
    // Only the address and method: no cookies, headers, query string, body or env.
    request: request
      ? {
          url: request.url ? scrubUrl(request.url) : undefined,
          method: request.method,
        }
      : undefined,
    user: undefined,
    message: event.message ? scrubText(event.message) : undefined,
    transaction: event.transaction ? scrubText(event.transaction) : undefined,
    breadcrumbs: event.breadcrumbs
      ?.map(scrubBreadcrumb)
      .filter((b): b is Breadcrumb => b !== null),
  }
  if (event.exception?.values)
    scrubbed.exception = {
      ...event.exception,
      values: event.exception.values.map((value) => ({
        ...value,
        value: value.value ? scrubText(value.value) : value.value,
        stacktrace: value.stacktrace
          ? {
              ...value.stacktrace,
              frames: value.stacktrace.frames?.map((frame) => ({
                ...frame,
                filename: frame.filename
                  ? scrubUrl(frame.filename)
                  : frame.filename,
                abs_path: frame.abs_path
                  ? scrubUrl(frame.abs_path)
                  : frame.abs_path,
                vars: undefined,
              })),
            }
          : undefined,
      })),
    }
  if (scrubbed.tags?.url && typeof scrubbed.tags.url === 'string')
    scrubbed.tags = { ...scrubbed.tags, url: scrubUrl(scrubbed.tags.url) }
  return scrubbed
}
