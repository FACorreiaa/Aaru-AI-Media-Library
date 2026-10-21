import type { MediaKind } from '../library/model'
import type { SocialUser } from './server'

// SOC-001 / SOC-002 on the web. The server is the judge of every rule; these only shape input
// and labels so the form can say what is wrong before a round trip.

/** What a person typed into a handle field, the way the server stores it. */
export function normalizeHandle(input: string): string {
  return input.trim().replace(/^@/, '').toLowerCase()
}

/** Why a handle would be refused, or null when it is well formed. Taken handles are the server's call. */
export function handleProblem(input: string): string | null {
  const handle = normalizeHandle(input)
  if (handle.length === 0) return 'Enter a handle.'
  if (!/^[a-z0-9_]{3,20}$/.test(handle))
    return 'Use 3–20 letters, numbers or underscores.'
  return null
}

/** "Ana · @ana", or "@ana" when there is no name. */
export function personLabel(user: SocialUser): string {
  return user.displayName
    ? `${user.displayName} · @${user.handle}`
    : `@${user.handle}`
}

/** One or two letters for a monogram: the name's initials, else the handle's first letter. */
export function monogram(user: SocialUser): string {
  const words = (user.displayName ?? '').split(/\s+/).filter(Boolean)
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase()
  if (words.length === 1) return words[0][0].toUpperCase()
  return user.handle[0].toUpperCase()
}

/** What to tell the sender after asking someone. */
export function requestOutcome(
  user: SocialUser,
  relationship: 'none' | 'friend' | 'outgoing' | 'incoming' | 'self',
): string {
  if (relationship === 'friend') return `You and @${user.handle} are friends.`
  return `Request sent to @${user.handle}.`
}

/** How an invite names its sender: their name, else their handle. */
export function inviterName(user: SocialUser): string {
  return user.displayName?.trim() || `@${user.handle}`
}

/** The line an invite carrying a title says, in the sender's voice. */
export function invitePlea(title: string, kind: MediaKind): string {
  if (kind === 'book') return `Read ${title} with me.`
  if (kind === 'album') return `Listen to ${title} with me.`
  return `Watch ${title} with me.`
}

/** "Expires in 13 days", "Expires tomorrow", "Expires today". */
export function inviteExpiry(expiresAt: string, now = Date.now()): string {
  const days = Math.floor((Date.parse(expiresAt) - now) / 86_400_000)
  if (days <= 0) return 'Expires today'
  if (days === 1) return 'Expires tomorrow'
  return `Expires in ${days} days`
}
