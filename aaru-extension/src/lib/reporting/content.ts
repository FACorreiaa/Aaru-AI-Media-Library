import { browser } from '#imports'
import { REPORT } from '../protocol'
import { BUILD_REPORTING, OFF, reporterFrom, toContentError } from './config'
import type { Reporter, ReportingConfig } from './config'

/**
 * The content scripts' reporter. It loads no Sentry code and installs nothing on the page:
 * no global handlers, no wrapped timers or listeners. Code that can fail runs inside
 * `guard`, and an error goes to the background as name, message and stack. The background
 * sends it, from the extension's own origin, tagged with the site's origin only.
 */
export function contentReporter(
  config: ReportingConfig = BUILD_REPORTING,
): Reporter {
  if (!config.dsn) return OFF
  return reporterFrom((error) => {
    browser.runtime
      .sendMessage({ type: REPORT, error: toContentError(error) })
      .catch(() => {
        // The background is restarting or the extension was updated: drop it.
      })
  })
}
