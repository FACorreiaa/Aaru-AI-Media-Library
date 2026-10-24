import {
  For,
  Index,
  Match,
  Show,
  Switch,
  createEffect,
  createSignal,
  on,
  onMount,
} from 'solid-js'
import { Alert, AlertDescription, Button, Skeleton } from '~/components/ui'
import { cn } from '~/lib/utils'
import { dayStrip, scheduleState } from '../../lib/sports/model'
import type {
  LiveState,
  SportEvent,
  SportSchedule,
} from '../../lib/sports/model'
import { createNearLive } from '../../lib/sports/near-live'
import { getSportSchedule } from '../../lib/sports/server'
import { Segmented } from '../Segmented'
import { EventRow } from './EventRow'
import { SportBadge } from './SportBadge'

const UNAVAILABLE = 'Sports aren’t answering right now.'

/**
 * SPT-003's Schedule: a date strip, three days back to a week ahead with Today marked, and the
 * chosen local day's events grouped by league under its badge (leagues with a followed team
 * first, as the server orders them). A followed team's row carries the amber edge.
 */
export function ScheduleView(props: {
  date: string
  today: string
  timeZone: string
  version: number
  onDateChange: (date: string) => void
  onOpenEvent: (event: SportEvent) => void
  onSearch: () => void
}) {
  const [schedule, setSchedule] = createSignal<SportSchedule | null>(null)
  const [loading, setLoading] = createSignal(true)
  const [problem, setProblem] = createSignal<string | null>(null)
  let strip: HTMLDivElement | undefined
  let latest = 0

  async function load(quiet: boolean): Promise<LiveState | null> {
    const request = ++latest
    const date = props.date
    if (!quiet) {
      setLoading(true)
      setProblem(null)
    }
    try {
      const found = await getSportSchedule({
        data: { date, tz: props.timeZone },
      })
      if (request !== latest) return null
      setSchedule(found)
      setProblem(found.unavailable ? UNAVAILABLE : null)
      return scheduleState(found)
    } catch (error) {
      if (request !== latest) return null
      const shown = schedule()
      if (!quiet || !shown || shown.date !== date)
        setProblem(
          error instanceof Error
            ? error.message
            : 'The schedule could not be loaded.',
        )
      return shown && shown.date === date ? scheduleState(shown) : null
    } finally {
      if (request === latest) setLoading(false)
    }
  }

  const nearLive = createNearLive(() => load(true))

  onMount(() => {
    // The chosen day starts in view on a narrow screen.
    strip
      ?.querySelector('[data-checked]')
      ?.scrollIntoView({ block: 'nearest', inline: 'center' })
  })
  createEffect(
    on(
      () => props.date,
      () => {
        nearLive.reset()
        void load(false).then(nearLive.plan)
      },
    ),
  )
  createEffect(
    on(
      () => props.version,
      () => void load(true).then(nearLive.plan),
      { defer: true },
    ),
  )

  // Another day's answer stays on screen, dimmed, until the chosen day's lands.
  const stale = () => loading() && schedule()?.date !== props.date
  const groups = () => schedule()?.groups ?? []

  return (
    <div class="mt-6">
      <div ref={strip}>
        <Segmented
          label="Day"
          variant="chip"
          trackClass="flex-nowrap overflow-x-auto pb-1 [scrollbar-width:none]"
          itemClass="flex-col gap-0 px-3 py-1.5 text-center leading-tight"
          options={dayStrip(props.today).map((day) => ({
            value: day.key,
            label: (
              <>
                <span aria-hidden="true" class="text-xs font-semibold">
                  {day.name}
                </span>
                <span
                  aria-hidden="true"
                  class="text-2xs font-normal tabular-nums opacity-80"
                >
                  {day.date}
                </span>
                <span class="sr-only">{day.label}</span>
              </>
            ),
          }))}
          value={props.date}
          onChange={props.onDateChange}
        />
      </div>

      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mt-4">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>

      <div
        class={cn('mt-6 transition-opacity', stale() && 'opacity-50')}
        aria-busy={loading()}
      >
        <Switch>
          <Match when={schedule() === null && loading()}>
            <div class="flex flex-col gap-6" aria-hidden="true">
              <Index each={[0, 1]}>
                {() => (
                  <div class="flex flex-col gap-2">
                    <Skeleton class="h-6 w-48 rounded-row" />
                    <Skeleton class="h-14 rounded-row" />
                    <Skeleton class="h-14 rounded-row" />
                  </div>
                )}
              </Index>
            </div>
          </Match>
          <Match when={schedule() && groups().length === 0 && !stale()}>
            <div class="max-w-prose py-8">
              <p class="font-display text-lg font-medium">
                Nothing on this day
              </p>
              <p class="mt-1 text-sm text-muted">
                The schedule shows games in the leagues you follow and your
                teams’ other games.
              </p>
              <Button
                variant="outline"
                class="mt-4"
                onClick={() => props.onSearch()}
              >
                Follow more
              </Button>
            </div>
          </Match>
          <Match when={groups().length > 0}>
            <div class="flex flex-col gap-8">
              <For each={groups()}>
                {(group) => (
                  <section aria-label={group.league}>
                    <div class="flex items-center gap-2 px-2.5">
                      <SportBadge
                        url={group.badgeUrl}
                        name={group.league}
                        class="size-6"
                      />
                      <h2 class="truncate font-display text-base font-medium">
                        {group.league}
                      </h2>
                      <span class="truncate text-xs text-muted">
                        {group.sport}
                      </span>
                    </div>
                    <ul class="mt-2 flex flex-col divide-y divide-line">
                      <For each={group.events}>
                        {(event) => (
                          <li>
                            <EventRow
                              event={event}
                              timeZone={props.timeZone}
                              today={props.today}
                              onOpen={props.onOpenEvent}
                            />
                          </li>
                        )}
                      </For>
                    </ul>
                  </section>
                )}
              </For>
            </div>
          </Match>
        </Switch>
      </div>
    </div>
  )
}
