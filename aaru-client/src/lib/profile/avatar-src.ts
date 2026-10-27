// SOC-001b: an avatar lives behind sign-in. The API points to `/v1/users/{id}/avatar?v=…`; the
// browser reads it through the Worker's same-origin route, which adds the session cookie.

const API_PATH = /^\/v1\/users\/([0-9a-f-]{36})\/avatar(?:\?v=(\d+))?$/i

/** The same-origin address of an avatar the API pointed to, or null without one. */
export function avatarSrc(avatarUrl: string | null | undefined): string | null {
  const match = avatarUrl ? API_PATH.exec(avatarUrl) : null
  if (!match) return null
  return `/app/avatars/${match[1]}${match[2] ? `?v=${match[2]}` : ''}`
}
