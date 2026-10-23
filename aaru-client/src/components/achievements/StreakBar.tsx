import { For, Show } from 'solid-js'
import {
  dayCount,
  streakHint,
  streakLine,
  weekdayLetter,
} from '../../lib/achievements/model'
import type { StreakState } from '../../lib/achievements/model'

// `StreakBar` (VIEWS.md, GAM-003): the streak's day count and the last seven days as ticks.
// Calm: no countdown, no red. Today's tick is outlined until something lands on it.
export function StreakBar(props: { streak: StreakState; compact?: boolean }) {
  const last = () => props.streak.days.length - 1
  return (
    <div class="flex items-end gap-5">
      <div class="flex min-w-0 flex-1 items-center gap-3">
        <span
          aria-hidden="true"
          class="grid size-10 shrink-0 place-items-center rounded-full"
          classList={{
            'bg-accent/12 text-accent': props.streak.current > 0,
            'bg-stone/60 text-muted': props.streak.current === 0,
          }}
        >
          <Flame />
        </span>
        <div class="min-w-0">
          <p class="font-display text-2xl leading-none font-medium tabular-nums">
            {props.streak.current > 0
              ? dayCount(props.streak.current)
              : 'No streak'}
          </p>
          <p class="mt-1 truncate text-sm text-muted">
            {props.streak.current > 0
              ? (streakHint(props.streak) ?? streakLine(props.streak))
              : streakLine(props.streak)}
          </p>
          <Show when={!props.compact && props.streak.longest > 0}>
            <p class="text-xs text-muted">
              Longest {dayCount(props.streak.longest)}
            </p>
          </Show>
        </div>
      </div>
      <ol
        class="flex shrink-0 gap-1.5"
        aria-label={`Last 7 days: ${props.streak.days.filter((d) => d.active).length} with progress`}
      >
        <For each={props.streak.days}>
          {(day, i) => (
            <li class="flex flex-col items-center gap-1">
              <span
                class="block h-6 w-2.5 rounded-xs"
                classList={{
                  'bg-accent': day.active,
                  'bg-line': !day.active && i() !== last(),
                  'border border-dashed border-line-strong':
                    !day.active && i() === last(),
                }}
              />
              <span class="text-[0.6875rem] text-muted" aria-hidden="true">
                {weekdayLetter(day.date)}
              </span>
            </li>
          )}
        </For>
      </ol>
    </div>
  )
}

/** The streaks glyph, drawn here so Home's strip does not load every badge glyph. */
function Flame() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="size-5"
    >
      <path d="M12 21a6 6 0 0 0 6-6c0-4-3-6-4-10-2 2-3 4-3 6-1-1-1.5-2-1.5-3C7 10 6 12.5 6 15a6 6 0 0 0 6 6z" />
    </svg>
  )
}
