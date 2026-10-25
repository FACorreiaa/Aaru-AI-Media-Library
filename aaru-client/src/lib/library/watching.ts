import type { components } from '../api/schema'
import { airingBadge, remainingLabel } from '../home/model'
import { episodeCode, showStatusLabel } from '../title/model'
import type { NowItem } from './now'

// APP-018: the facts a Watching page row shows, from `GET /v1/library/watching`. Apart from
// `now.ts` so Library's Now, which shows none of them, does not carry these labels.

export type WatchingItem = components['schemas']['WatchingItem']

/**
 * A Watching row's facts, one line each, empty ones left out: "Apple TV+ · Returning",
 * "Next S2 · E3 · Who Is Alive", "7 left · 5h 40m", "Airs S2 · E10 · Tomorrow · 9:00 PM", or
 * "Caught up" when every aired episode is watched.
 */
export function watchingLines(
  item: NowItem,
  watching: WatchingItem | undefined,
  now: Date,
  timeZone?: string,
): string[] {
  const progress = item.entry.progress
  const next = progress?.nextEpisode
  const airing = watching?.nextAiring
  const caughtUp = !!progress && progress.airedCount > 0 && !next
  const when = airing
    ? [
        airingBadge(airing, now, timeZone) ??
          new Date(airing.airsAt).toLocaleDateString(undefined, {
            timeZone,
            day: 'numeric',
            month: 'short',
          }),
        airing.airTimeKnown
          ? new Intl.DateTimeFormat(undefined, {
              timeZone,
              hour: 'numeric',
              minute: '2-digit',
            }).format(new Date(airing.airsAt))
          : null,
      ]
        .filter(Boolean)
        .join(' · ')
    : null
  return [
    [item.entry.title.network, showStatusLabel(watching?.showStatus)]
      .filter(Boolean)
      .join(' · '),
    next
      ? ['Next', episodeCode(next.season, next.number), watching?.nextName]
          .filter(Boolean)
          .join(' · ')
          .replace('Next · ', 'Next ')
      : '',
    watching?.remainingCount
      ? remainingLabel(watching.remainingCount, watching.remainingMinutes ?? 0)
      : '',
    airing ? `Airs ${episodeCode(airing.season, airing.number)} · ${when}` : '',
    caughtUp ? 'Caught up' : '',
  ].filter(Boolean)
}
