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
