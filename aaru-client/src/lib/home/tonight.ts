import { entryDay, localDayKey } from '../calendar/model'
import type { CalendarEntry } from '../calendar/model'
import type { components } from '../api/schema'
import { nextLine, runtimeLabel } from './model'
import type { ContinueEntry } from './model'

// Tonight on the Field (VIEWS.md `TonightStrip`, AG-005): one thing to watch or read now and at
// most one more. The server ranks it (`/v1/tonight`, with "not tonight" and "not for me");
// without an answer for today it is composed in the browser from rows Home already has:
// Continue watching (every next episode there has aired) and today's airings. The Apple apps'
// `Home/Tonight.swift` follows the same rule.

export type RankedTonight = components['schemas']['Tonight']
export type RankedPick = components['schemas']['TonightPick']
export type TonightVerdict = components['schemas']['TonightFeedback']['verdict']

export type TonightPick =
  | { kind: 'continue'; entry: ContinueEntry }
  | { kind: 'airing'; entry: CalendarEntry }
  /** A server pick; `next` is Continue watching's card for the same show, so the tick works. */
  | { kind: 'ranked'; entry: RankedPick; next: ContinueEntry | null }

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
  if (candidates.length === 0) return null
  const [primary, ...rest] = candidates
  const also = rest.find((pick) => pickId(pick) !== pickId(primary)) ?? null
  return { primary, also }
}

/**
 * The server's picks in its order, less what is hidden (playing now, or set aside since it
 * loaded); each show's pick carries its Continue watching card. Null when none is left.
 */
export function rankedTonight(
  ranked: RankedTonight,
  continuing: ContinueEntry[],
  hidden: ReadonlySet<string>,
): Tonight | null {
  const picks: TonightPick[] = ranked.picks
    .filter((pick) => !hidden.has(pick.libraryItemId))
    .map((entry) => ({
      kind: 'ranked',
      entry,
      next:
        entry.kind === 'continue'
          ? (continuing.find((c) => c.libraryItemId === entry.libraryItemId) ??
            null)
          : null,
    }))
  if (picks.length === 0) return null
  return { primary: picks[0], also: picks[1] ?? null }
}

/** The episode the tick marks, when there is one to mark. */
export function pickMarkable(pick: TonightPick): ContinueEntry | null {
  if (pick.kind === 'continue') return pick.entry
  if (pick.kind === 'ranked') return pick.next
  return null
}

/** "S4 · E3 · Name". Empty for a book or a film. */
export function pickEpisode(pick: TonightPick): string {
  if (pick.kind === 'continue') return nextLine(pick.entry)
  if (pick.kind === 'ranked') {
    if (pick.next) return nextLine(pick.next)
    const { episode, episodeName } = pick.entry
    return [
      episode ? `S${episode.season}` : '',
      episode ? `E${episode.number}` : '',
      episodeName ?? '',
    ]
      .filter(Boolean)
      .join(' · ')
  }
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
  if (pick.kind === 'ranked') return pick.entry.reason
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
