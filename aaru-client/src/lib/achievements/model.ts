import type { components } from '../api/schema'

// GAM-001…005 on the web: what the Achievements page, the Home strip, Friends and the unlock
// toast say, from `/v1/me/progress`, `/v1/me/badges`, `/v1/me/points` and the board. Pure, so
// it is tested without a browser (DESIGN.md §17 "Achievements").

export type Progress = components['schemas']['Progress']
export type StreakState = components['schemas']['StreakState']
export type Badge = components['schemas']['Badge']
export type BadgeAward = components['schemas']['BadgeAward']
export type BadgeFamily = components['schemas']['BadgeFamily']
export type PointsEvent = components['schemas']['PointsEventItem']
export type PointsPage = components['schemas']['PointsPage']
export type Leaderboard = components['schemas']['Leaderboard']
export type LeaderboardEntry = components['schemas']['LeaderboardEntry']
export type FriendAchievements = components['schemas']['FriendAchievements']

/** Display order of the families on the page. */
export const FAMILIES: { family: BadgeFamily; label: string }[] = [
  { family: 'films', label: 'Films' },
  { family: 'shows', label: 'Shows' },
  { family: 'anime', label: 'Anime' },
  { family: 'books', label: 'Books' },
  { family: 'music', label: 'Music' },
  { family: 'ratings', label: 'Ratings' },
  { family: 'lists', label: 'Lists' },
  { family: 'imports', label: 'Imports' },
  { family: 'discovery', label: 'Discovery' },
  { family: 'streaks', label: 'Streaks' },
  { family: 'social', label: 'Social' },
]

const TIERS = ['Bronze', 'Silver', 'Gold', 'Platinum'] as const

/** The eyebrow over a tiered badge's name; null for a one-tier badge or none earned. */
export function tierName(tier: number, maxTier: number): string | null {
  if (maxTier <= 1 || tier < 1) return null
  return TIERS[Math.min(tier, TIERS.length) - 1]
}

const count = (n: number) => n.toLocaleString('en-US')

/** "62 / 100" toward the next tier, or null once every tier is earned (or the badge is hidden). */
export function progressText(badge: Badge): string | null {
  if (!badge.progress) return null
  return `${count(badge.progress.current)} / ${count(badge.progress.target)}`
}

/** 0…1 toward the next tier, for the thin bar under a medallion. */
export function progressFraction(badge: Badge): number {
  if (!badge.progress || badge.progress.target <= 0) return badge.earned ? 1 : 0
  return Math.min(1, badge.progress.current / badge.progress.target)
}

/** A hidden badge not yet earned is "???", and says nothing about how to get it. */
export function badgeName(badge: Badge): string {
  return badge.name ?? '???'
}

export type FamilyGroup = {
  family: BadgeFamily
  label: string
  badges: Badge[]
}

/** The badges by family in display order, earned first within each, empty families left out. */
export function byFamily(badges: Badge[]): FamilyGroup[] {
  return FAMILIES.map(({ family, label }) => {
    const mine = badges.filter((b) => b.family === family)
    return {
      family,
      label,
      badges: [
        ...mine.filter((b) => b.earned),
        ...mine.filter((b) => !b.earned),
      ],
    }
  }).filter((group) => group.badges.length > 0)
}

/** "18 of 62 earned". */
export function earnedLine(badges: Badge[]): string {
  const earned = badges.filter((b) => b.earned).length
  return `${earned} of ${badges.length} earned`
}

/** How far into this level, 0…1. */
export function levelFraction(progress: Progress): number {
  const span = progress.nextLevelAt - progress.levelStart
  if (span <= 0) return 1
  return Math.min(1, Math.max(0, (progress.total - progress.levelStart) / span))
}

/** "120 points to level 4". */
export function nextLevelLine(progress: Progress): string {
  const left = Math.max(0, progress.nextLevelAt - progress.total)
  return `${count(left)} ${left === 1 ? 'point' : 'points'} to level ${progress.level + 1}`
}

/** "12-day streak", or what to do when there is none. */
export function streakLine(streak: StreakState): string {
  if (streak.current === 0)
    return streak.longest > 0
      ? `Longest streak: ${dayCount(streak.longest)}`
      : 'Watch or read something to start a streak'
  return `${dayCount(streak.current)} in a row`
}

/** Whether today still needs a tick to keep the streak going. */
export function streakHint(streak: StreakState): string | null {
  if (streak.current === 0) return null
  return streak.today ? 'Today counts' : 'Today is still open'
}

export function dayCount(days: number): string {
  return days === 1 ? '1 day' : `${count(days)} days`
}

/** Single-letter weekday labels for the streak's seven dates ("2026-10-22" → "T"). */
export function weekdayLetter(date: string): string {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay()
  return ['S', 'M', 'T', 'W', 'T', 'F', 'S'][day] ?? ''
}

/** The toast for what the server has not shown yet: one line for a whole batch. */
export function unlockSummary(unseen: Progress['unseen']): string | null {
  if (unseen.count === 0) return null
  const badges =
    unseen.count === 1 ? 'a badge' : `${count(unseen.count)} badges`
  if (unseen.origin === 'backfill')
    return `Aaru gives badges now. You’ve already earned ${unseen.count === 1 ? 'one' : count(unseen.count)}.`
  if (unseen.origin === 'batch') return `Your history earned you ${badges}.`
  if (unseen.count === 1 && unseen.items[0])
    return `${unseen.items[0].name} · earned`
  return `${count(unseen.count)} badges earned`
}

/** The award shown on its own full card: a live top tier (or hidden badge), once. */
export function revealOf(unseen: Progress['unseen']): BadgeAward | null {
  if (unseen.origin !== 'live') return null
  return unseen.items.find((item) => item.reveal) ?? null
}

const KINDS: Record<string, string> = {
  episode: 'Episode',
  movie_finished: 'Film finished',
  book_finished: 'Book finished',
  album_finished: 'Album finished',
  season_bonus: 'Season complete',
  scrobble_bonus: 'Played in a player',
  book_progress: 'Reading',
  listen: 'Listen',
  room_attended: 'Watch party',
  friend_added: 'New friend',
  import_first: 'First import',
  streak_milestone: 'Streak milestone',
}

/** "Episode", "Film finished"… for one row of the points ledger. */
export function pointsKind(kind: string): string {
  return KINDS[kind] ?? 'Points'
}

/** "+10", "−10" (a true minus) for one ledger row. */
export function pointsDelta(points: number): string {
  return points < 0 ? `−${count(-points)}` : `+${count(points)}`
}

/** "Oct 19 – 25", or "Oct 27 – Nov 2" across a month. */
export function weekRange(from: string, until: string): string {
  const start = new Date(`${from}T00:00:00Z`)
  const end = new Date(`${until}T00:00:00Z`)
  const month = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  })
  const same = start.getUTCMonth() === end.getUTCMonth()
  return `${month.format(start)} – ${same ? String(end.getUTCDate()) : month.format(end)}`
}

/** A friend's shelf on their profile: the newest few, then "See all". */
export const FRIEND_SHELF = 6
