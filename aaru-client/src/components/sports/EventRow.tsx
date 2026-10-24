import { Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { Button } from '~/components/ui'
import { cn } from '~/lib/utils'
import {
  clockLabel,
  dayName,
  eventTitle,
  hasScore,
  isCard,
  localDay,
  statusLabel,
} from '../../lib/sports/model'
import type { SportEvent, SportSide } from '../../lib/sports/model'
import { SportBadge } from './SportBadge'

/**
 * One event as a row (DESIGN.md §13a, SofaScore's density): the time or the live clock in a
 * narrow column, the two sides with badges, the score at the end. A UFC or WWE card shows its
 * poster and name instead of sides. A followed team's row carries the amber edge.
 */
export function EventRow(props: {
  event: SportEvent
  timeZone: string
  today: string
  /** Name the day over the time (Favorites); the Schedule's rows are all one day. */
  showDay?: boolean
  muted?: boolean
  onOpen: (event: SportEvent) => void
}) {
  const live = () => props.event.status === 'live'
  const scored = () => hasScore(props.event)
  const day = () => {
    if (!props.showDay) return null
    const local = props.event.startsAt
      ? localDay(props.event.startsAt, props.timeZone)
      : null
    return dayName(local ?? props.event.day, props.today)
  }
  const label = () =>
    `${eventTitle(props.event)}, ${[day(), spoken(props.event, props.timeZone)]
      .filter(Boolean)
      .join(', ')}`

  return (
    <Button
      variant="ghost"
      size="bare"
      aria-label={label()}
      onClick={() => props.onOpen(props.event)}
      class={cn(
        'flex w-full items-center gap-3 rounded-row border-l-2 py-2 pr-3 pl-2.5 text-left font-normal text-ink hover:bg-surface hover:text-ink',
        props.event.isFavorite ? 'border-gold' : 'border-transparent',
        props.muted && 'text-muted hover:text-ink',
      )}
    >
      <span class="flex w-16 shrink-0 flex-col text-xs tabular-nums">
        <Show when={day()}>
          {(name) => <span class="truncate text-muted">{name()}</span>}
        </Show>
        <Show
          when={live()}
          fallback={
            <span
              class={cn(
                props.event.status === 'scheduled' ? 'text-ink' : 'text-muted',
                (props.event.status === 'postponed' ||
                  props.event.status === 'cancelled') &&
                  'text-danger',
              )}
            >
              {statusLabel(props.event, props.timeZone)}
            </span>
          }
        >
          <span class="flex items-center gap-1.5 font-semibold text-accent">
            <span aria-hidden="true" class="size-1.5 rounded-full bg-accent" />
            {clockLabel(props.event.progress) ?? 'Live'}
          </span>
        </Show>
      </span>

      <Show
        when={!isCard(props.event)}
        fallback={<CardName event={props.event} />}
      >
        <span class="flex min-w-0 flex-1 flex-col gap-1">
          <Side side={props.event.home} />
          <Side side={props.event.away} />
        </span>
        <Show when={scored()}>
          <span
            class={cn(
              'flex shrink-0 flex-col items-end gap-1 text-sm font-semibold tabular-nums',
              live() && 'text-accent',
            )}
          >
            <span>{props.event.home?.score}</span>
            <span>{props.event.away?.score}</span>
          </span>
        </Show>
      </Show>
      <Show when={props.event.isFavorite}>
        <span class="sr-only">, followed</span>
      </Show>
    </Button>
  )
}

function Side(props: { side?: SportSide }): JSX.Element {
  return (
    <span class="flex min-w-0 items-center gap-2 text-sm">
      <SportBadge
        url={props.side?.badgeUrl}
        name={props.side?.name ?? '?'}
        class="size-5"
      />
      <span class="truncate">{props.side?.name ?? 'To be decided'}</span>
    </span>
  )
}

function CardName(props: { event: SportEvent }) {
  return (
    <span class="flex min-w-0 flex-1 items-center gap-3">
      <Show when={props.event.imageUrl}>
        {(src) => (
          <img
            src={src()}
            alt=""
            loading="lazy"
            decoding="async"
            referrerpolicy="no-referrer"
            class="h-10 w-16 shrink-0 rounded-thumb bg-surface object-cover"
          />
        )}
      </Show>
      <span class="line-clamp-2 min-w-0 text-sm font-medium">
        {props.event.name}
      </span>
    </span>
  )
}

/** The status as a screen reader hears it: "live, 67′", "kick-off 20:45", "full time 2–1". */
function spoken(event: SportEvent, timeZone: string): string {
  const status = statusLabel(event, timeZone)
  const score = hasScore(event)
    ? `${event.home?.score}–${event.away?.score}`
    : null
  if (event.status === 'scheduled') return `starts ${status}`
  return [status, score].filter(Boolean).join(' ')
}
