import { agendaDayLabel, airTime, entryDay } from './model'
import type { CalendarEntry } from './model'

// CAL-005, "Group by: Channel": the calendar's episodes by where they air. Its own module, not
// model.ts: that one is a chunk other routes share, and only the calendar needs this.

/** CAL-005: where episodes air when the title names no network. Always the last group. */
export const OTHER_CHANNEL = 'Other'

export interface AiringChannel {
  channel: string
  entries: CalendarEntry[]
}

/** Entries by where they air (the title's network or streamer), for "Group by: Channel". The
 * busiest channel first, then by name; "Other" (no network) last. Each channel's episodes in
 * air order, then by season and episode. */
export function groupByChannel(entries: CalendarEntry[]): AiringChannel[] {
  const byChannel = new Map<string, CalendarEntry[]>()
  for (const entry of entries) {
    const channel = entry.title.network?.trim() || OTHER_CHANNEL
    const list = byChannel.get(channel)
    if (list) list.push(entry)
    else byChannel.set(channel, [entry])
  }
  const groups = [...byChannel].map(([channel, list]) => ({
    channel,
    entries: list.sort(
      (a, b) =>
        a.airsAt.localeCompare(b.airsAt) ||
        a.season - b.season ||
        a.number - b.number,
    ),
  }))
  return groups.sort(
    (a, b) =>
      Number(a.channel === OTHER_CHANNEL) -
        Number(b.channel === OTHER_CHANNEL) ||
      b.entries.length - a.entries.length ||
      a.channel.localeCompare(b.channel),
  )
}

/** "Thu 15 Oct · 9:00 PM", or "Thu 15 Oct" when only the date is known: a row's meta line when
 * the calendar is grouped by channel, where the channel is already the heading. */
export function dayAndTime(
  entry: CalendarEntry,
  timeZone?: string,
  locale?: string,
): string {
  return [
    agendaDayLabel(entryDay(entry, timeZone), locale),
    airTime(entry, timeZone, locale),
  ]
    .filter(Boolean)
    .join(' · ')
}
