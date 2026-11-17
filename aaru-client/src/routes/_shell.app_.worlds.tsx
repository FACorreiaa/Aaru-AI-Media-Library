import { Link, createFileRoute } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import { BackLink } from '../components/shell/BackLink'
import { Poster } from '../components/Poster'
import { WorldProgress } from '../components/WorldMap'
import { countLabel, kindsLabel, laneKind } from '../lib/title/world'
import type { WorldSummary } from '../lib/title/world'
import { loadMyWorlds } from '../lib/title/worldServer'

// GRAPH-007: the Worlds page. Every World the viewer has a title in, those with something left
// first and the furthest along leading, as the server orders them. A row opens its map.

export const Route = createFileRoute('/_shell/app_/worlds')({
  loader: () => loadMyWorlds(),
  head: () => ({ meta: [{ title: 'Worlds · Aaru' }] }),
  component: WorldsPage,
})

function WorldsPage() {
  const worlds = Route.useLoaderData()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/library" label="Library" class="-ml-1" />
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Worlds
        </h1>
        <p class="mt-2 max-w-prose text-muted">
          The larger stories your library is part of, across books, films, shows
          and more, and how far you are through each.
        </p>
        <Show
          when={worlds().length > 0}
          fallback={
            <div class="mt-16 text-center">
              <p class="font-display text-2xl font-medium">No worlds yet</p>
              <p class="mx-auto mt-2 max-w-prose text-muted">
                A world appears when a title in your library is part of a larger
                story: a sequel, an adaptation, a spin-off.
              </p>
            </div>
          }
        >
          <ul class="mt-8 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            <For each={worlds()}>
              {(world) => (
                <li>
                  <WorldRow world={world} />
                </li>
              )}
            </For>
          </ul>
        </Show>
      </div>
    </div>
  )
}

/** One World in the list: a poster, its name, how far the viewer is, and what comes next. */
function WorldRow(props: { world: WorldSummary }) {
  const done = () => props.world.finished >= props.world.total
  return (
    <Link
      to="/app/world/$titleId"
      params={{ titleId: props.world.titleId }}
      class="flex h-full gap-3 rounded-panel border border-line bg-surface p-4 hover:border-line-strong"
    >
      <div class="w-14 shrink-0" aria-hidden="true">
        <Poster
          url={props.world.posterUrl}
          kind={laneKind(props.world.kinds[0] ?? 'film')}
          radius="thumb"
        />
      </div>
      <div class="min-w-0 flex-1">
        <p class="line-clamp-2 font-display text-lg leading-snug font-medium">
          {props.world.name}
        </p>
        <p class="mt-1 flex flex-wrap items-baseline gap-x-2 text-sm">
          <span class="font-semibold tabular-nums">
            {countLabel(props.world.finished, props.world.total)}
          </span>
          <span class="truncate text-muted">
            {kindsLabel(props.world.kinds)}
          </span>
        </p>
        <div class="mt-2">
          <WorldProgress
            finished={props.world.finished}
            total={props.world.total}
          />
        </div>
        <Show
          when={!done()}
          fallback={<p class="mt-2 text-xs text-accent">Finished</p>}
        >
          <Show when={props.world.startHere?.title}>
            {(next) => (
              <p class="mt-2 truncate text-xs text-muted">Next: {next()}</p>
            )}
          </Show>
        </Show>
      </div>
    </Link>
  )
}
