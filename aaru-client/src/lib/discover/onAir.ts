import type { components } from '../api/schema'
import { hitKey } from '../library/model'

// The On air view's pure part (DISC-003): shows airing this week, one group per channel or
// streamer, each with its next episode and, for the viewer's region, where else it streams.
// The server groups and orders; this only words what it sends.

export type OnAirGuide = components['schemas']['DiscoverOnAir']
export type OnAirChannel = components['schemas']['OnAirChannel']
export type OnAirShow = components['schemas']['OnAirShow']
export type OnAirEpisode = components['schemas']['OnAirEpisode']

/** The region the device's language names ("en-US" → "US"), or undefined. Never stored. */
export function viewerRegion(language: string | undefined): string | undefined {
  if (!language) return undefined
  try {
    const region = new Intl.Locale(language).maximize().region
    return region && /^[A-Z]{2}$/.test(region) ? region : undefined
  } catch {
    return undefined
  }
}

/**
 * "S2 E5 · Thu 9:00 PM", or "S2 E5 · Thu 22 Oct" while only the day is known. The day is the
 * viewer's for an exact time and the listed (UTC) day otherwise, as on the calendar.
 */
export function episodeLine(
  episode: OnAirEpisode,
  timeZone?: string,
  locale?: string,
): string {
  const date = new Date(episode.airsAt)
  const when = episode.airTimeKnown
    ? new Intl.DateTimeFormat(locale, {
        timeZone,
        weekday: 'short',
        hour: 'numeric',
        minute: '2-digit',
      }).format(date)
    : new Intl.DateTimeFormat(locale, {
        timeZone: 'UTC',
        weekday: 'short',
        day: 'numeric',
        month: 'short',
      }).format(date)
  return `S${episode.season} E${episode.number} · ${when}`
}

/** "Also on Hulu and Max", or null with nothing to list. */
export function streamsLine(show: OnAirShow): string | null {
  const names = (show.streamsOn ?? []).map((provider) => provider.name)
  if (names.length === 0) return null
  const list =
    names.length === 1
      ? names[0]
      : `${names.slice(0, -1).join(', ')} and ${names.at(-1)}`
  return `Also on ${list}`
}

/** "1 show", "4 shows". */
export const showCount = (n: number) => (n === 1 ? '1 show' : `${n} shows`)

/** After an add, every card for that title links to the new entry. */
export function markOnAir(
  guide: OnAirGuide,
  key: string,
  libraryItemId: string,
): OnAirGuide {
  return {
    ...guide,
    channels: guide.channels.map((channel) => ({
      ...channel,
      shows: channel.shows.map((show) =>
        hitKey(show.item) === key
          ? { ...show, item: { ...show.item, libraryItemId } }
          : show,
      ),
    })),
  }
}
