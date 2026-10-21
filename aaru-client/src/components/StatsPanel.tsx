import { Link } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  chartBars,
  isRolling,
  kindDetail,
  kindShares,
  ratingBars,
  recapPeriod,
  timeLabel,
  totals,
  windowLabel,
} from '../lib/insights/model'
import type { InsightsPeriod } from '../lib/insights/model'
import { kindOf } from '../lib/library/model'
import { dayLabel } from '../lib/recap/model'
import type { Stats } from '../lib/recap/model'
import { cn } from '../lib/cn'
import { Poster } from './Poster'
import { buttonVariants } from './ui/button'
import { cardClass } from './ui/card'

// Insights: one period's numbers, drawn plainly. Bars are static CSS, no chart library; the
// Recap is where the same numbers move.

function Section(props: { title: string; children: JSX.Element }) {
  return (
    <section class="mt-10">
      <h2 class="font-display text-2xl font-medium tracking-tight">
        {props.title}
      </h2>
      <div class="mt-4">{props.children}</div>
    </section>
  )
}

/** Day of a run; all time spans years, so it says which. */
function runDay(day: string, withYear: boolean): string {
  return withYear ? `${dayLabel(day)}, ${day.slice(0, 4)}` : dayLabel(day)
}

export function StatsPanel(props: { stats: Stats; period: InsightsPeriod }) {
  const s = () => props.stats
  const bars = () => chartBars(s())
  const showLabel = (i: number) =>
    bars().length <= 12 || i === 0 || (i + 1) % 5 === 0
  const recap = () => recapPeriod(props.period)
  const ratings = () => ratingBars(s().ratings.distribution)
  const rolling = () => isRolling(s().span)
  const chartUnit = () =>
    rolling() || s().span === 'month'
      ? 'day'
      : s().span === 'year'
        ? 'month'
        : 'year'

  return (
    <div>
      <Show when={windowLabel(s())}>
        {(days) => (
          <p class="mt-6 text-sm text-muted">
            {days()} · Private to you
            <Show when={s().prior}>
              {' '}
              · compared with the {s().span === 'last7' ? '7' : '30'} days
              before
            </Show>
          </p>
        )}
      </Show>

      <dl class="mt-8 grid grid-cols-2 gap-3 md:grid-cols-4">
        <For each={totals(s())}>
          {(total) => (
            <div class={cn(cardClass, 'p-5')}>
              <dt class="text-sm text-muted">{total.label}</dt>
              <dd class="mt-1 flex items-baseline gap-2">
                <span class="font-display text-3xl font-medium tabular-nums">
                  {total.value}
                </span>
                <Show when={total.delta}>
                  {(change) => (
                    <span
                      class="text-xs font-medium tabular-nums"
                      classList={{
                        'text-accent': change().up,
                        'text-muted': !change().up,
                      }}
                    >
                      <span aria-hidden="true">{change().up ? '↗' : '↘'}</span>{' '}
                      {change().text}
                      <span class="sr-only"> from the period before</span>
                    </span>
                  )}
                </Show>
              </dd>
            </div>
          )}
        </For>
      </dl>

      <Show when={recap()}>
        {(period) => (
          <Link
            to="/app/recap"
            search={period()}
            class={cn(buttonVariants({ variant: 'ink' }), 'mt-4')}
          >
            Play as a story
          </Link>
        )}
      </Show>

      <Show
        when={
          rolling()
            ? s().totals.minutesWatched > 0
            : s().totals.episodesWatched > 0
        }
      >
        <Section title={rolling() ? 'Time per day' : 'Episodes'}>
          <div
            class="flex h-40 items-end gap-[3px] text-accent"
            role="img"
            aria-label={`${rolling() ? 'Time' : 'Episodes'} per ${chartUnit()}`}
          >
            <For each={bars()}>
              {(bar, i) => (
                <div class="flex h-full min-w-0 flex-1 flex-col justify-end gap-1">
                  <div
                    class="rounded-t-[3px]"
                    classList={{
                      'bg-current': bar.busiest,
                      'bg-current/35': !bar.busiest && bar.height > 0,
                      'bg-line': bar.height === 0,
                    }}
                    style={{
                      height: `${Math.max(bar.height * 100, bar.height > 0 ? 4 : 1)}%`,
                    }}
                  />
                  <span class="h-4 text-center text-[11px] text-muted">
                    {showLabel(i()) ? bar.label : ''}
                  </span>
                </div>
              )}
            </For>
          </div>
        </Section>
      </Show>

      <Show when={s().byKind.some((k) => k.minutes > 0 || k.finished > 0)}>
        <Section title="By kind">
          <ul class="space-y-4">
            <For each={kindShares(s())}>
              {(kind) => (
                <li>
                  <div class="flex items-baseline justify-between gap-4 text-sm">
                    <span class="font-medium">{kind.label}</span>
                    <span class="text-muted tabular-nums">
                      {kindDetail(kind)}
                    </span>
                  </div>
                  <div class="mt-2 h-2 overflow-hidden rounded-full bg-surface">
                    <div
                      class="h-full rounded-full bg-accent"
                      style={{ width: `${Math.round(kind.share * 100)}%` }}
                    />
                  </div>
                </li>
              )}
            </For>
          </ul>
        </Section>
      </Show>

      <Show when={s().topTitles.length > 0}>
        <Section title="Most time with">
          <ol class="divide-y divide-line">
            <For each={s().topTitles.slice(0, 5)}>
              {(top, i) => (
                <li class="flex items-center gap-4 py-3">
                  <span class="w-5 text-right font-display text-lg text-muted tabular-nums">
                    {i() + 1}
                  </span>
                  <Poster
                    url={top.title.posterUrl}
                    kind={kindOf(top.title.type, top.title.isAnime)}
                    class="w-10 shrink-0"
                  />
                  <div class="min-w-0">
                    <p class="truncate font-medium">{top.title.title}</p>
                    <p class="text-sm text-muted">
                      {[
                        top.episodes > 0
                          ? `${top.episodes} episode${top.episodes === 1 ? '' : 's'}`
                          : null,
                        top.minutes > 0 ? timeLabel(top.minutes) : null,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </p>
                  </div>
                </li>
              )}
            </For>
          </ol>
        </Section>
      </Show>

      <Show when={s().ratings.count > 0}>
        <Section title="Ratings">
          <Show when={s().ratings.mean}>
            {(mean) => (
              <p class="mb-4 text-sm text-muted">
                Average {mean().toFixed(1)} out of 10 across {s().ratings.count}{' '}
                rating{s().ratings.count === 1 ? '' : 's'}
              </p>
            )}
          </Show>
          <div
            class="flex h-28 items-end gap-1.5 text-accent"
            role="img"
            aria-label="Ratings from 1 to 10"
          >
            <For each={ratings()}>
              {(bar) => (
                <div class="flex h-full flex-1 flex-col justify-end gap-1">
                  <div
                    class="rounded-t-[3px] bg-current/60"
                    style={{
                      height: `${Math.max(bar.height * 100, bar.count > 0 ? 4 : 1)}%`,
                    }}
                    title={`${bar.count} rated ${bar.label}`}
                  />
                  <span class="text-center text-[11px] text-muted">
                    {bar.label}
                  </span>
                </div>
              )}
            </For>
          </div>
        </Section>
      </Show>

      <Show when={s().longestRun}>
        {(run) => (
          <Section title="Longest run">
            <p>
              <span class="font-display text-3xl font-medium tabular-nums">
                {run().days}
              </span>{' '}
              <span class="text-muted">
                day{run().days === 1 ? '' : 's'} in a row ·{' '}
                {runDay(run().start, s().span === 'all')} –{' '}
                {runDay(run().end, s().span === 'all')}
              </span>
            </p>
          </Section>
        )}
      </Show>

      <p class="mt-12 text-sm text-muted">
        Counts what you tracked in Aaru. Imported history without dates isn’t
        activity.
      </p>
    </div>
  )
}
