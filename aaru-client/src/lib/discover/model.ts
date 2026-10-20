// Discover's pure part: the date badge on a card. The server names and orders the rows; "today"
// is the viewer's, so the badge is worked out in the browser from a local `YYYY-MM-DD`.

/** The one row whose films are opening now: a past date there still says "Out now". */
const IN_THEATERS = 'movies_in_theaters'

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
 * The badge a card in this row wears. In theaters says "Out now" once a film opens; elsewhere
 * a past date says nothing (everything trending is out), only a future one shows. Any row id
 * works, including ones this client does not know yet.
 */
export function cardBadge(
  rowId: string,
  releaseDate: string | undefined,
  today: string,
): string | null {
  const badge = releaseBadge(releaseDate, today)
  if (badge === 'Out now' && rowId !== IN_THEATERS) return null
  return badge
}
