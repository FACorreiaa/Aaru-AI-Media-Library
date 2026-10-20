import { errorMessage } from '../api/errors'
import { sessionRejected } from '../session/guard'

// Server-only: called inside server-function handlers, never from client code. Kept out of
// `server.ts` so its exports carry no server-only import into the client bundle.

/** The response body, or the API's message as an error; a 401 signs the visitor out. */
export function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** For bodiless responses: throws the API's message unless it succeeded. */
export function checkEmpty(
  result: { error?: unknown; response: Response },
  fallback: string,
) {
  if (result.response.status === 401) sessionRejected()
  if (!result.response.ok) throw new Error(errorMessage(result.error, fallback))
}
