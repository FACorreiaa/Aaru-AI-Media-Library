import { Link } from '@tanstack/solid-router'
import { For } from 'solid-js'
import type { WeekStrip } from '../lib/home/model'
import { cardClass } from '~/components/ui'
import { cn } from '~/lib/utils'

// GAM-006d on the Field: the last 7 days in numbers, across the main column under Tonight
// (owner, 2026-10-21: "should be horizontal", not a small block in the side column). Four
// figures in a row, the week's bars with their days, and the way into Insights.
export function WeekStripCard(props: { week: WeekStrip }) {
  return (
    <section class="mt-8" aria-labelledby="home-week">
      <div class="flex items-baseline justify-between gap-4">
        <h2 id="home-week" class="eyebrow">
          Last 7 days
        </h2>
        <Link
          to="/app/insights"
          search={{ span: 'last7' }}
          class="text-sm font-semibold text-accent hover:underline"
        >
          Insights →
        </Link>
      </div>
      <div
        class={cn(
          cardClass,
          'mt-3 flex flex-col gap-5 px-5 py-4 sm:flex-row sm:items-end sm:gap-8',
        )}
      >
        <dl class="grid flex-1 grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-4">
          <For each={props.week.figures}>
            {(figure) => (
              <div class="flex flex-col-reverse">
                <dt class="text-sm text-muted">{figure.label}</dt>
                <dd class="font-display text-3xl leading-none font-medium tabular-nums">
                  {figure.value}
                </dd>
              </div>
            )}
          </For>
        </dl>
        <div class="flex shrink-0 gap-1.5 sm:w-56" aria-hidden="true">
          <For each={props.week.days}>
            {(height, i) => (
              <span class="flex flex-1 flex-col items-center gap-1">
                <span class="flex h-12 w-full items-end text-accent">
                  <span
                    class="w-full rounded-xs"
                    classList={{
                      'bg-current': height > 0,
                      'bg-line': height === 0,
                    }}
                    style={{
                      height:
                        height > 0 ? `${Math.max(height * 100, 12)}%` : '3px',
                    }}
                  />
                </span>
                <span class="text-xs text-muted">
                  {props.week.dayLabels[i()]}
                </span>
              </span>
            )}
          </For>
        </div>
      </div>
    </section>
  )
}
