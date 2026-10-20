import type { components } from '../api/schema'

// Discover's pure parts: what each section is called and the date badge on a card. "Today" is
// the viewer's, so the badge is worked out in the browser from a local `YYYY-MM-DD`.

export type Discover = components['schemas']['Discover']
export type DiscoverSection = components['schemas']['DiscoverSection']
export type DiscoverSectionId = components['schemas']['DiscoverSectionId']
export type AnimeSeason = components['schemas']['AnimeSeason']

const TITLES: Record<DiscoverSectionId, string> = {
  trending: 'Trending this week',
  upcoming_movies: 'Coming to cinemas',
  new_shows: 'New shows',
  on_the_air: 'Airing this week',
  anime_season: 'Anime this season',
  anime_next_season: 'Anime next season',
}

const SEASONS: Record<AnimeSeason['season'], string> = {
  winter: 'Winter',
  spring: 'Spring',
  summer: 'Summer',
  fall: 'Fall',
}

const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
]

/** "Trending this week", "Anime · Fall 2026"… An anime section without its season keeps a
 * plain name. */
export function sectionTitle(section: {
  id: DiscoverSectionId
  animeSeason?: AnimeSeason
}): string {
  const season = section.animeSeason
  if (season) return `Anime · ${SEASONS[season.season]} ${season.year}`
  return TITLES[section.id]
}

/** The day difference between two "YYYY-MM-DD" keys (b − a), DST-proof. */
function daysBetween(a: string, b: string): number {
  return Math.round(
    (Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / 86_400_000,
  )
}

/**
 * A release date against the viewer's today: "Out now", "Today", "Tomorrow", "In 3 days",
 * then a date — "Nov 14", or "Jan 3, 2027" in another year. Null without a usable date.
 */
export function releaseBadge(
  releaseDate: string | undefined,
  today: string,
): string | null {
  if (!releaseDate || !/^\d{4}-\d{2}-\d{2}$/.test(releaseDate)) return null
  const days = daysBetween(today, releaseDate)
  if (days < 0) return 'Out now'
  if (days === 0) return 'Today'
  if (days === 1) return 'Tomorrow'
  if (days < 7) return `In ${days} days`
  const [year, month, day] = releaseDate.split('-').map(Number)
  const date = `${MONTHS[month - 1]} ${day}`
  return year === Number(today.slice(0, 4)) ? date : `${date}, ${year}`
}

/**
 * The badge a card in this section wears. Coming to cinemas says "Out now" once a film opens;
 * elsewhere a past date says nothing (everything trending is out), only a future one shows.
 */
export function cardBadge(
  section: DiscoverSectionId,
  releaseDate: string | undefined,
  today: string,
): string | null {
  const badge = releaseBadge(releaseDate, today)
  if (badge === 'Out now' && section !== 'upcoming_movies') return null
  return badge
}
