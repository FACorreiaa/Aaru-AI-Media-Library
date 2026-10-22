import { Link } from '@tanstack/solid-router'
import { For, Show, createResource, createSignal } from 'solid-js'
import { musicTotals } from '../../lib/insights/model'
import { TOP_BY } from '../../lib/music/listening-model'
import type { TopBy } from '../../lib/music/listening-model'
import { topListens } from '../../lib/music/listening'
import type { Stats } from '../../lib/recap/model'
import { cn } from '~/lib/utils'
import { cardClass } from '~/components/ui'
import { TopList } from './TopList'
import { Segmented } from '../Segmented'

// MUS-008: Insights' Music section. Its own tiles, apart from the library's: listening never
// adds to them. The top five load for the period Insights shows.
export function MusicInsights(props: {
  music: NonNullable<Stats['music']>
  query: {
    year?: number
    month?: number
    span?: 'all' | 'last7' | 'last30'
    tz: string
  }
}) {
  const [by, setBy] = createSignal<TopBy>('artist')
  const [top] = createResource(
    () => ({ ...props.query, by: by(), limit: 5 }),
    (query) => topListens({ data: query }),
  )

  return (
    <section class="mt-10">
      <h2 class="font-display text-2xl font-medium tracking-tight">Music</h2>
      <dl class="mt-4 grid grid-cols-2 gap-3">
        <For each={musicTotals(props.music)}>
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

      <Segmented
        label="Top list"
        class="mt-6"
        itemClass="px-4 py-1.5 text-sm"
        options={TOP_BY.map((o) => ({ value: o.by, label: o.label }))}
        value={by()}
        onChange={setBy}
      />
      <div class="mt-2 min-h-16" aria-busy={top.loading}>
        <Show
          when={top()}
          fallback={
            <Show when={top.error}>
              <p class="py-3 text-sm text-muted">
                The top list could not be loaded.
              </p>
            </Show>
          }
        >
          {(list) => (
            <Show
              when={list().items.length > 0}
              fallback={
                <p class="py-3 text-sm text-muted">
                  No album names came with these listens.
                </p>
              }
            >
              <TopList rows={list().items} by={by()} />
            </Show>
          )}
        </Show>
      </div>
      <Link
        to="/app/music"
        class="mt-2 inline-block text-sm font-semibold text-accent hover:underline"
      >
        All listens ›
      </Link>
    </section>
  )
}
