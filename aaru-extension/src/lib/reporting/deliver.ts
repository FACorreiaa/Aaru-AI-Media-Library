import { browser } from '#imports'
import { BUILD_REPORTING } from './config'
import type { ReportingConfig } from './config'
import { ENVELOPE_MAX_BYTES, envelopeEndpoint } from './reporter'
import type { SendEnvelope } from './reporter'

/**
 * Firefox asks at install whether the extension may send technical and interaction data
 * (`data_collection_permissions.optional`, wxt.config.ts); the user can change it later in
 * about:addons. Without that yes nothing is sent. Chrome has no such switch; its store
 * listing discloses error reports instead.
 */
export async function reportingAllowed(
  isFirefox: boolean = import.meta.env.FIREFOX,
): Promise<boolean> {
  if (!isFirefox) return true
  try {
    const granted = (await browser.permissions.getAll()) as {
      data_collection?: string[]
    }
    return granted.data_collection?.includes('technicalAndInteraction') ?? false
  } catch {
    return false
  }
}

/**
 * Posts envelopes to Sentry from the background, for the background's own errors and for
 * the content scripts' (which hand theirs over a runtime message). No cookies, no referrer.
 */
export function makeDeliver(
  config: ReportingConfig = BUILD_REPORTING,
  allowed: () => Promise<boolean> = () => reportingAllowed(),
  post: typeof fetch = (input, init) => fetch(input, init),
): SendEnvelope {
  const endpoint = config.dsn ? envelopeEndpoint(config.dsn) : null
  return async (body) => {
    if (!endpoint || body.length > ENVELOPE_MAX_BYTES) return undefined
    if (!(await allowed())) return undefined
    try {
      const response = await post(endpoint, {
        method: 'POST',
        body,
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
      })
      return { statusCode: response.status }
    } catch {
      return undefined
    }
  }
}
