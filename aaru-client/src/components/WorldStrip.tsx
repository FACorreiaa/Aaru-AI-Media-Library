import { Link } from '@tanstack/solid-router'
import { Show, createEffect, createSignal, on, onCleanup } from 'solid-js'
import { WorldProgress } from './WorldMap'
import { countLabel, isReady, kindsLabel } from '../lib/title/world'
import type { World } from '../lib/title/world'
import { loadWorld } from '../lib/title/worldServer'

// GRAPH-007: `WorldStrip`, the title room's World section: the World this title is part of and
// how far the viewer is, opening the map. Read in the browser after the room shows. Absent until
// the World is built and for a title that has none; a World still being built is asked for again
// a few times, then left.

const RETRY_MS = 4000
const TRIES = 6

export function WorldStrip(props: { titleId: string }) {
  const [world, setWorld] = createSignal<World | null>(null)
  let retry: ReturnType<typeof setTimeout> | undefined
  const load = (titleId: string, triesLeft: number) =>
    loadWorld({ data: { titleId } })
      .then((found) => {
        // A page that moved on to another title ignores a late answer for the last one.
        if (titleId !== props.titleId) return
        setWorld(found)
        if (found.state === 'building' && triesLeft > 1)
          retry = setTimeout(() => void load(titleId, triesLeft - 1), RETRY_MS)
      })
      .catch(() => undefined)
  createEffect(
    on(
      () => props.titleId,
      (titleId) => {
        clearTimeout(retry)
        setWorld(null)
        void load(titleId, TRIES)
      },
    ),
  )
  onCleanup(() => clearTimeout(retry))

  return (
    <Show when={isReady(world()) && world()}>
      {(w) => (
        <section aria-labelledby="title-world">
          <Link
            to="/app/world/$titleId"
            params={{ titleId: props.titleId }}
            class="group block rounded-panel border border-line bg-surface p-4 edge-lit hover:border-line-strong"
          >
            <div class="flex items-baseline justify-between gap-4">
              <h2 id="title-world" class="eyebrow">
                World
              </h2>
              <span class="text-xs text-muted group-hover:text-ink">
                Open the map
              </span>
            </div>
            <p class="mt-2 font-display text-xl font-medium">{w().name}</p>
            <p class="mt-1 flex flex-wrap items-baseline gap-x-2 text-sm">
              <span class="font-semibold tabular-nums">
                {countLabel(w().finished, w().total)}
              </span>
              <span class="text-muted">{kindsLabel(w().kinds)}</span>
            </p>
            <div class="mt-3">
              <WorldProgress finished={w().finished} total={w().total} />
            </div>
          </Link>
        </section>
      )}
    </Show>
  )
}
