import { Link } from '@tanstack/solid-router'
import { For, Show, createEffect, createSignal, on } from 'solid-js'
import {
  Button,
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
  Dialog,
  DialogContent,
  DialogPortal,
  Skeleton,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import { countryName } from '../../lib/sports/countries'
import {
  clockLabel,
  eventTitle,
  groupBroadcasts,
  hasScore,
  isCard,
  placeLine,
  statusLabel,
  whenLine,
} from '../../lib/sports/model'
import type {
  SportBroadcast,
  SportEvent,
  SportEventDetail,
  SportSide,
} from '../../lib/sports/model'
import { getSportEvent } from '../../lib/sports/server'
import { SportBadge } from './SportBadge'

/**
 * SPT-003's event sheet: the sides with badges, the score or the kick-off, status, venue and
 * round, then "Where to watch": the chosen country's channels first, a pointer to Sports
 * settings when no country is chosen, and "Other countries" folded, grouped by country. `open`
 * false keeps it on its last event while the exit plays (WEB-011).
 */
export function EventSheet(props: {
  event: SportEvent
  open: boolean
  timeZone: string
  today: string
  onClose: () => void
}) {
  const [detail, setDetail] = createSignal<SportEventDetail | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  let latest = 0

  async function load(id: string) {
    const request = ++latest
    setDetail(null)
    setProblem(null)
    try {
      const found = await getSportEvent({ data: { id } })
      if (request === latest) setDetail(found)
    } catch (error) {
      if (request === latest)
        setProblem(
          error instanceof Error
            ? error.message
            : 'That event could not be loaded.',
        )
    }
  }

  createEffect(
    on(
      () => (props.open ? props.event.id : null),
      (id) => {
        if (id) void load(id)
      },
    ),
  )

  // The row's own copy draws at once; the detail's fresher line replaces it when it lands.
  const event = () => {
    const fresh = detail()?.event
    return fresh && fresh.id === props.event.id ? fresh : props.event
  }
  const live = () => event().status === 'live'
  const place = () => placeLine(event())

  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          aria-labelledby="sport-event-title"
          class="block max-h-[90dvh] gap-0 overflow-y-auto p-0 sm:max-w-lg"
        >
          <div class="flex items-start justify-between gap-4 px-5 pt-5">
            <div class="flex min-w-0 items-center gap-2">
              <Show when={event().league}>
                {(league) => (
                  <>
                    <SportBadge
                      url={event().leagueBadgeUrl}
                      name={league()}
                      class="size-5"
                    />
                    <p class="eyebrow truncate">{league()}</p>
                  </>
                )}
              </Show>
            </div>
            <Button
              variant="ghost"
              size="bare"
              class="text-sm"
              onClick={() => props.onClose()}
            >
              Done
            </Button>
          </div>

          <h2 id="sport-event-title" class="sr-only">
            {eventTitle(event())}
          </h2>

          <Show
            when={!isCard(event())}
            fallback={
              <div class="px-5 pt-3">
                <Show when={event().imageUrl}>
                  {(src) => (
                    <img
                      src={src()}
                      alt=""
                      referrerpolicy="no-referrer"
                      class="aspect-video w-full rounded-panel bg-surface object-cover"
                    />
                  )}
                </Show>
                <p
                  aria-hidden="true"
                  class="mt-3 font-display text-2xl leading-tight font-medium"
                >
                  {event().name}
                </p>
              </div>
            }
          >
            <div
              aria-hidden="true"
              class="grid grid-cols-[1fr_auto_1fr] items-start gap-3 px-5 pt-5"
            >
              <SideBlock side={event().home} />
              <div class="flex min-w-24 flex-col items-center pt-3 text-center">
                <Show
                  when={hasScore(event())}
                  fallback={
                    <span class="font-display text-2xl font-medium tabular-nums">
                      {event().status === 'scheduled'
                        ? statusLabel(event(), props.timeZone)
                        : 'v'}
                    </span>
                  }
                >
                  <span
                    class={cn(
                      'font-display text-4xl font-medium tabular-nums',
                      live() && 'text-accent',
                    )}
                  >
                    {event().home?.score}–{event().away?.score}
                  </span>
                </Show>
              </div>
              <SideBlock side={event().away} />
            </div>
          </Show>

          <div class="mt-4 flex flex-col items-center gap-1 px-5 text-center text-sm">
            <Show
              when={live()}
              fallback={
                <p
                  class={cn(
                    'font-medium',
                    (event().status === 'postponed' ||
                      event().status === 'cancelled') &&
                      'text-danger',
                  )}
                >
                  {event().status === 'scheduled'
                    ? whenLine(event(), props.today, props.timeZone)
                    : statusLabel(event(), props.timeZone)}
                </p>
              }
            >
              <p class="flex items-center gap-1.5 font-semibold text-accent">
                <span
                  aria-hidden="true"
                  class="size-2 rounded-full bg-accent"
                />
                Live
                <Show when={clockLabel(event().progress)}>
                  {(clock) => <span>· {clock()}</span>}
                </Show>
              </p>
            </Show>
            <Show when={place()}>
              {(line) => <p class="text-muted">{line()}</p>}
            </Show>
          </div>

          <section
            aria-labelledby="where-to-watch"
            class="mt-6 border-t border-line px-5 pt-4 pb-6"
          >
            <h3 id="where-to-watch" class="font-display text-lg font-medium">
              Where to watch
            </h3>
            <Show
              when={detail()}
              fallback={
                <Show
                  when={problem()}
                  fallback={
                    <div class="mt-3 flex flex-col gap-2" aria-hidden="true">
                      <Skeleton class="h-5 w-40 rounded-row" />
                      <Skeleton class="h-5 w-32 rounded-row" />
                    </div>
                  }
                >
                  {(message) => (
                    <p role="alert" class="mt-2 text-sm text-danger">
                      {message()}
                    </p>
                  )}
                </Show>
              }
            >
              {(found) => <WhereToWatch detail={found()} />}
            </Show>
          </section>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}

function SideBlock(props: { side?: SportSide }) {
  return (
    <div class="flex min-w-0 flex-col items-center gap-2 text-center">
      <SportBadge
        url={props.side?.badgeUrl}
        name={props.side?.name ?? '?'}
        class="size-14"
      />
      <span class="line-clamp-2 text-sm font-semibold">
        {props.side?.name ?? 'To be decided'}
      </span>
    </div>
  )
}

function WhereToWatch(props: { detail: SportEventDetail }) {
  const groups = () => groupBroadcasts(props.detail.elsewhere)
  const code = () => props.detail.watchCountryCode
  const none = () =>
    props.detail.inYourCountry.length === 0 && groups().length === 0
  return (
    <Show
      when={!none()}
      fallback={
        <p class="mt-2 text-sm text-muted">
          No channels are listed for this event.
        </p>
      }
    >
      <Show
        when={props.detail.inYourCountry.length > 0}
        fallback={
          <Show
            when={code()}
            fallback={
              <p class="mt-2 text-sm text-muted">
                Choose your country in{' '}
                <Link
                  to="/app/settings/friends"
                  hash="sports"
                  class="font-medium text-accent hover:underline"
                >
                  Sports settings
                </Link>{' '}
                to see its channels first.
              </p>
            }
          >
            {(country) => (
              <p class="mt-2 text-sm text-muted">
                No channels listed in {countryName(country())}.
              </p>
            )}
          </Show>
        }
      >
        <Show when={code()}>
          {(country) => <p class="eyebrow mt-3">{countryName(country())}</p>}
        </Show>
        <Channels channels={props.detail.inYourCountry} />
      </Show>

      <Show when={groups().length > 0}>
        <Collapsible class="group mt-4 rounded-panel border border-line">
          <CollapsibleTrigger class="flex w-full cursor-pointer items-center justify-between gap-4 rounded-panel px-4 py-3 text-left text-sm font-semibold">
            Other countries
            <span
              aria-hidden="true"
              class="text-lg leading-none text-muted transition-transform group-data-[expanded]:rotate-45"
            >
              +
            </span>
          </CollapsibleTrigger>
          <CollapsibleContent class="px-4 pb-4">
            <For each={groups()}>
              {(group) => (
                <div class="mt-3 first:mt-0">
                  <p class="eyebrow">{group.country}</p>
                  <Channels channels={group.channels} />
                </div>
              )}
            </For>
          </CollapsibleContent>
        </Collapsible>
      </Show>
    </Show>
  )
}

function Channels(props: { channels: SportBroadcast[] }) {
  return (
    <ul class="mt-1.5 flex flex-col gap-1.5">
      <For each={props.channels}>
        {(broadcast) => (
          <li class="flex items-center gap-2 text-sm">
            <Show when={broadcast.logoUrl}>
              {(src) => (
                <img
                  src={src()}
                  alt=""
                  loading="lazy"
                  referrerpolicy="no-referrer"
                  class="h-5 w-8 shrink-0 object-contain"
                />
              )}
            </Show>
            <span>{broadcast.channel}</span>
          </li>
        )}
      </For>
    </ul>
  )
}
