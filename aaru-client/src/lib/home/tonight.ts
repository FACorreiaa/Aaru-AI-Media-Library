import { entryDay, localDayKey } from '../calendar/model'
import type { CalendarEntry } from '../calendar/model'
import { nextLine, runtimeLabel } from './model'
import type { ContinueEntry } from './model'

// Tonight on the Field (VIEWS.md `TonightStrip`, pulled forward 2026-10-21): one thing to watch
// now and at most one more, composed in the browser from rows Home already has: Continue
// watching (every next episode there has aired) and today's airings. It ranks nothing new and
// writes nothing; the agent-composed Tonight, with "not tonight", stays in M13.

export type TonightPick =
  | { kind: 'continue'; entry: ContinueEntry }
  | { kind: 'airing'; entry: CalendarEntry }

export interface Tonight {
  primary: TonightPick
  also: TonightPick | null
}

const pickId = (pick: TonightPick) => pick.entry.libraryItemId

/** Unwatched episodes of the user's shows that air today, earliest first. */
export function airingToday(
  airings: CalendarEntry[],
  now: Date,
  timeZone?: string,
): CalendarEntry[] {
  const today = localDayKey(now, timeZone)
  return airings
    .filter((a) => !a.watched && entryDay(a, timeZone) === today)
    .sort((a, b) => (a.airsAt < b.airsAt ? -1 : a.airsAt > b.airsAt ? 1 : 0))
}

/**
 * The next episode of the show at the top of Continue watching, else the first airing today;
 * then one more from the other source, never the same show twice. Null when there is nothing.
 */
export function composeTonight(
  continuing: ContinueEntry[],
  airings: CalendarEntry[],
  now: Date,
  timeZone?: string,
): Tonight | null {
  const today = airingToday(airings, now, timeZone)
  const candidates: TonightPick[] = [
    ...continuing
      .slice(0, 1)
      .map((entry) => ({ kind: 'continue', entry }) as const),
    ...today.map((entry) => ({ kind: 'airing', entry }) as const),
    ...continuing
      .slice(1)
      .map((entry) => ({ kind: 'continue', entry }) as const),
  ]
  const [primary, ...rest] = candidates
  if (!primary) return null
  const also = rest.find((pick) => pickId(pick) !== pickId(primary)) ?? null
  return { primary, also }
}

/** "S4 · E3 · Name". */
export function pickEpisode(pick: TonightPick): string {
  if (pick.kind === 'continue') return nextLine(pick.entry)
  return [
    `S${pick.entry.season}`,
    `E${pick.entry.number}`,
    pick.entry.episodeName,
  ]
    .filter(Boolean)
    .join(' · ')
}

/** Why it is here: "47m · 3 left · Finale next", or "Airs 21:00 · 44m". */
export function pickReason(pick: TonightPick, timeZone?: string): string {
  if (pick.kind === 'continue') {
    const e = pick.entry
    return [
      runtimeLabel(e.nextRuntimeMinutes),
      e.remainingCount > 1 ? `${e.remainingCount} left` : 'Last one aired',
      e.isFinale ? 'Season finale' : '',
    ]
      .filter(Boolean)
      .join(' · ')
  }
  const e = pick.entry
  const when = e.airTimeKnown
    ? `Airs ${new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(e.airsAt))}`
    : 'Airs today'
  return [
    when,
    runtimeLabel(e.runtimeMinutes),
    e.kind === 'premiere' ? 'Premiere' : e.kind === 'finale' ? 'Finale' : '',
  ]
    .filter(Boolean)
    .join(' · ')
}

/** The Field's line under its heading: "Tuesday evening · 3 in progress · 2 airing today". */
export function fieldLine(
  heading: string,
  inProgress: number,
  airingTodayCount: number,
): string {
  return [
    heading,
    inProgress > 0 ? `${inProgress} in progress` : '',
    airingTodayCount === 1
      ? '1 airing today'
      : airingTodayCount > 1
        ? `${airingTodayCount} airing today`
        : '',
  ]
    .filter(Boolean)
    .join(' · ')
}
