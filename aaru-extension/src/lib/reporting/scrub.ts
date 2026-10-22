import type { Breadcrumb, ErrorEvent } from '@sentry/browser'

/**
 * What an error report may say about where it happened. On a streaming site the path names
 * what the user watches (`/watch/80100172`), so only the site's origin goes. Anywhere else a
 * URL keeps its path and loses its query string and fragment. There is no user, no cookies,
 * no headers and no request body.
 */

const STREAMING_HOST =
  /(^|\.)(netflix\.com|disneyplus\.com|primevideo\.com|amazon\.[a-z.]+)$/

/** `https://www.netflix.com/watch/12345?trackId=9` → `https://www.netflix.com`. */
export function scrubUrl(url: string): string {
  try {
    const parsed = new URL(url)
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
      if (STREAMING_HOST.test(parsed.hostname)) return parsed.origin
      return `${parsed.origin}${parsed.pathname}`
    }
    // The extension's own files (chrome-extension://, moz-extension://) keep their path.
    parsed.search = ''
    parsed.hash = ''
    return parsed.toString()
  } catch {
    return url.split(/[?#]/, 1)[0] ?? ''
  }
}

const URL_IN_TEXT =
  /\b(?:https?|wss?|chrome-extension|moz-extension):\/\/[^\s"'<>`)\]]+/g

/** Scrubs every URL inside free text, such as an error message. */
export function scrubText(text: string): string {
  return text.replace(URL_IN_TEXT, (match) => scrubUrl(match))
}

/** The extension sends no breadcrumbs at all: every one could name a page. */
export function dropBreadcrumb(_breadcrumb: Breadcrumb): null {
  return null
}

/**
 * The event as it may leave the extension. `site` is the origin of the streaming page a
 * content script ran on, when there is one.
 */
export function scrubEvent(event: ErrorEvent): ErrorEvent {
  const scrubbed: ErrorEvent = {
    ...event,
    request: event.request?.url
      ? { url: scrubUrl(event.request.url) }
      : undefined,
    user: undefined,
    breadcrumbs: undefined,
    message: event.message ? scrubText(event.message) : undefined,
    transaction: event.transaction ? scrubText(event.transaction) : undefined,
    extra: undefined,
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
  return scrubbed
}
