import { Link } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import type { JSX } from 'solid-js'
import { timeLabel } from '../lib/insights/model'
import { kindOf } from '../lib/library/model'
import {
  countTiles,
  genreBars,
  heroLine,
  isEmptyProfile,
  memberSince,
  timeShares,
  timeSpent,
} from '../lib/profile/model'
import type { ProfileStats, TimeShare } from '../lib/profile/model'
import { cn } from '~/lib/utils'
import { Poster } from './Poster'
import { RatingsHistogram } from './StatsPanel'
import { cardClass } from '~/components/ui'
import { Medallion } from './Medallion'
import type { Person } from './Medallion'

// The profile (GAM-006b, pulled forward 2026-10-22): all-time numbers, MyAnimeList-style, under
// the user's own medallion. Static like Insights (DESIGN.md §13b): bars are drawn at their
// final width and nothing counts up.

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

/** One tone per kind, so a segment and its legend swatch match; the legend names each too. */
const SHARE_TONE: Record<TimeShare['kind'], string> = {
  show: 'bg-accent',
  anime: 'bg-accent/55',
  movie: 'bg-accent/25',
}

const percent = (share: number) => `${Math.round(share * 100)}%`

export function ProfilePanel(props: {
  stats: ProfileStats
  person: Person
  /** The library item for a title, so a most-watched poster opens it. */
  itemFor: (titleId: string) => string | undefined
}) {
  const s = () => props.stats
  const name = () =>
    props.person.displayName?.trim() ||
    (props.person.handle ? `@${props.person.handle}` : 'You')
  const shares = () => timeShares(s())

  return (
    <div class="max-w-3xl">
      <header class="mt-4 flex items-center gap-4">
        <Medallion person={props.person} class="size-16 text-2xl" />
        <div class="min-w-0">
          <h1 class="truncate font-display text-4xl font-medium tracking-tight">
            {name()}
          </h1>
          <p class="text-sm text-muted">
            {[
              props.person.handle && props.person.displayName
                ? `@${props.person.handle}`
                : null,
              memberSince(s().memberSince),
            ]
              .filter(Boolean)
              .join(' · ')}
          </p>
        </div>
      </header>

      <Show
        when={!isEmptyProfile(s())}
        fallback={
          <p class="mt-10 text-muted">
            Your stats fill in as you watch. Mark a show you’ve finished to
            start.
          </p>
        }
      >
        <section class="mt-10" aria-labelledby="profile-time">
          <h2 id="profile-time" class="eyebrow">
            Time watched
          </h2>
          <p class="mt-2 font-display text-4xl font-medium tracking-tight tabular-nums md:text-5xl">
            {timeSpent(s().minutesWatched)}
          </p>
          <Show when={heroLine(s())}>
            {(line) => <p class="mt-1 text-muted tabular-nums">{line()}</p>}
          </Show>
        </section>

        <ul class="mt-8 grid grid-cols-2 gap-3">
          <For each={countTiles(s())}>
            {(tile) => (
              <li>
                <Link
                  to="/app/library"
                  search={{ kind: tile.kind, status: tile.status }}
                  class={cn(cardClass, 'block h-full p-5 hover:bg-surface')}
                >
                  <span class="block text-sm text-muted">{tile.label}</span>
                  <span class="mt-1 block font-display text-3xl font-medium tabular-nums">
                    {tile.value.toLocaleString('en')}
                  </span>
                  <Show when={tile.detail}>
                    {(detail) => (
                      <span class="block text-sm text-muted tabular-nums">
                        {detail()}
                      </span>
                    )}
                  </Show>
                </Link>
              </li>
            )}
          </For>
        </ul>

        <Show when={shares().length > 0}>
          <Section title="Where the time went">
            <div
              class="flex h-3 gap-0.5 overflow-hidden rounded-full"
              role="img"
              aria-label={shares()
                .map((share) => `${share.label} ${percent(share.share)}`)
                .join(', ')}
            >
              <For each={shares()}>
                {(share) => (
                  <div
                    class={SHARE_TONE[share.kind]}
                    style={{ width: percent(share.share) }}
                  />
                )}
              </For>
            </div>
            <ul class="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-sm">
              <For each={shares()}>
                {(share) => (
                  <li class="flex items-center gap-2">
                    <span
                      aria-hidden="true"
                      class={cn(
                        'size-2.5 rounded-full',
                        SHARE_TONE[share.kind],
                      )}
                    />
                    <span class="font-medium">{share.label}</span>
                    <span class="text-muted tabular-nums">
                      {timeLabel(share.minutes)}
                    </span>
                  </li>
                )}
              </For>
            </ul>
          </Section>
        </Show>

        <Show when={s().topGenres.length > 0}>
          <Section title="Genres">
            <ul class="space-y-4">
              <For each={genreBars(s().topGenres)}>
                {(genre) => (
                  <li>
                    <div class="flex items-baseline justify-between gap-4 text-sm">
                      <span class="truncate font-medium">{genre.name}</span>
                      <span class="shrink-0 text-muted tabular-nums">
                        {genre.time} · {genre.titles}
                      </span>
                    </div>
                    <div class="mt-2 h-2 overflow-hidden rounded-full bg-surface">
                      <div
                        class="h-full rounded-full bg-accent"
                        style={{ width: percent(genre.width) }}
                      />
                    </div>
                  </li>
                )}
              </For>
            </ul>
          </Section>
        </Show>

        <Show when={s().mostWatched.length > 0}>
          <Section title="Most watched">
            <ol class="grid grid-cols-3 gap-4">
              <For each={s().mostWatched}>
                {(top) => {
                  const art = () => (
                    <>
                      <Poster
                        url={top.title.posterUrl}
                        kind={kindOf(top.title.type, top.title.isAnime)}
                        frame
                      />
                      <span class="mt-2 line-clamp-2 block text-sm font-medium">
                        {top.title.title}
                      </span>
                      <span class="block text-xs text-muted tabular-nums">
                        {timeLabel(top.minutes)}
                      </span>
                    </>
                  )
                  return (
                    <li class="min-w-0">
                      <Show when={props.itemFor(top.title.id)} fallback={art()}>
                        {(id) => (
                          <Link
                            to="/app/title/$id"
                            params={{ id: id() }}
                            class="block"
                          >
                            {art()}
                          </Link>
                        )}
                      </Show>
                    </li>
                  )
                }}
              </For>
            </ol>
          </Section>
        </Show>

        <Show when={s().topNetworks.length > 0}>
          <Section title="Where you watch">
            <ul class="flex flex-wrap gap-2">
              <For each={s().topNetworks}>
                {(network) => (
                  <li class="rounded-full bg-surface px-4 py-2 text-sm font-medium">
                    {network.name}{' '}
                    <span class="text-muted tabular-nums">
                      {timeLabel(network.minutes)}
                    </span>
                  </li>
                )}
              </For>
            </ul>
          </Section>
        </Show>

        <Show when={s().ratings.count > 0}>
          <Section title="Ratings">
            <Show when={s().ratings.mean}>
              {(mean) => (
                <p class="mb-4 text-sm text-muted">
                  Average {mean().toFixed(1)} out of 10 across{' '}
                  {s().ratings.count} rating
                  {s().ratings.count === 1 ? '' : 's'}
                </p>
              )}
            </Show>
            <RatingsHistogram distribution={s().ratings.distribution} />
          </Section>
        </Show>
      </Show>

      <footer class="mt-12 flex flex-col gap-3 text-sm">
        <div class="flex flex-wrap gap-x-5 gap-y-2 font-medium">
          <Link
            to="/app/insights"
            search={{ span: 'all' }}
            class="text-accent hover:underline"
          >
            Insights
          </Link>
          <Link
            to="/app/recap"
            search={{ year: new Date().getFullYear() }}
            class="text-accent hover:underline"
          >
            Recap
          </Link>
        </div>
        <p class="text-muted">Includes episodes without a watch date.</p>
      </footer>
    </div>
  )
}
