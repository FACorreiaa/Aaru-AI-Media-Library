import type { MediaKind } from '../library/model'
import type {
  ActivityItem,
  Reaction,
  FriendItem,
  FriendProfile,
  SocialUser,
} from './server'

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
  if (kind === 'book' || kind === 'manga') return `Read ${title} with me.`
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

/** What a friend did on one day: "watched S1 · E3", "watched 3 episodes, up to S1 · E5", "finished". */
export function activityVerb(item: ActivityItem): string {
  const episode =
    item.lastSeason != null && item.lastEpisode != null
      ? `S${item.lastSeason} · E${item.lastEpisode}`
      : null
  const watched = !episode
    ? null
    : item.episodes > 1
      ? `watched ${item.episodes} episodes, up to ${episode}`
      : `watched ${episode}`
  if (item.finished) return watched ? `${watched} and finished` : 'finished'
  return watched ?? 'watched'
}

/** "Today", "Yesterday", else "Mon 19 Oct". `day` is the UTC day the server grouped by. */
export function activityDay(day: string, now = new Date()): string {
  const today = now.toISOString().slice(0, 10)
  const yesterday = new Date(now.getTime() - 86_400_000)
    .toISOString()
    .slice(0, 10)
  if (day === today) return 'Today'
  if (day === yesterday) return 'Yesterday'
  return new Date(`${day}T12:00:00Z`).toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  })
}

/** Where a friend is in a title: "S2 · E4", "Page 120", or nothing. */
export function itemProgress(item: FriendItem): string | null {
  if (item.lastSeason != null && item.lastEpisode != null)
    return `S${item.lastSeason} · E${item.lastEpisode}`
  if (item.bookPage != null) return `Page ${item.bookPage}`
  if (item.mangaChapter != null) return `Ch. ${item.mangaChapter}`
  return null
}

/** "42 films · 12 shows · 8 books", leaving out kinds they have none of. */
export function countsLine(counts: FriendProfile['counts']): string | null {
  if (!counts) return null
  const parts: Array<[number, string, string]> = [
    [counts.movie, 'film', 'films'],
    [counts.show, 'show', 'shows'],
    [counts.anime, 'anime', 'anime'],
    [counts.manga ?? 0, 'manga', 'manga'],
    [counts.book, 'book', 'books'],
    [counts.album, 'album', 'albums'],
  ]
  const shown = parts
    .filter(([n]) => n > 0)
    .map(([n, one, many]) => `${n} ${n === 1 ? one : many}`)
  return shown.length ? shown.join(' · ') : null
}

/** "Friends since October 2026". */
export function friendsSince(date: string): string {
  return `Friends since ${new Date(date).toLocaleDateString('en-GB', {
    month: 'long',
    year: 'numeric',
  })}`
}

/** The row with the viewer's reaction set to `emoji` (or cleared), counts kept in step. */
export function withReaction(
  item: ActivityItem,
  emoji: Reaction | null,
): ActivityItem {
  const counts = new Map((item.reactions ?? []).map((r) => [r.emoji, r.count]))
  if (item.myReaction)
    counts.set(item.myReaction, (counts.get(item.myReaction) ?? 1) - 1)
  if (emoji) counts.set(emoji, (counts.get(emoji) ?? 0) + 1)
  const reactions = [...counts]
    .filter(([, count]) => count > 0)
    .map(([e, count]) => ({ emoji: e, count }))
    .sort((a, b) => b.count - a.count)
  return {
    ...item,
    myReaction: emoji ?? undefined,
    reactions: reactions.length ? reactions : undefined,
  }
}
