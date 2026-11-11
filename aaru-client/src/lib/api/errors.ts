import type { components } from './schema'

export type ApiError = components['schemas']['ErrorResponse']

/** The server's own message when it sent one, else a plain fallback. Never internal detail. */
export function errorMessage(error: unknown, fallback: string): string {
  if (
    typeof error === 'object' &&
    error !== null &&
    'message' in error &&
    typeof error.message === 'string' &&
    error.message.length > 0
  ) {
    return error.message
  }
  return fallback
}

/** The message shown when deleting an account needs a fresh sign-in (R1). */
export const REAUTH_MESSAGE =
  'For your safety, sign in again, then delete your account.'

/** True when `DELETE /v1/me` answered 403 `reauth_required`: the session is too old to delete with. */
export function isReauthRequired(status: number, error: unknown): boolean {
  return (
    status === 403 &&
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'reauth_required'
  )
}
