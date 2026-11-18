import { For, Show, createMemo } from 'solid-js'
import { Badge } from '~/components/ui'
import { Poster } from './Poster'
import { TitleLink } from './TitleLink'
import {
  WORLD,
  countLabel,
  labelOrigin,
  laneCount,
  laneKind,
  laneLabel,
  rungPath,
  tileOrigin,
  titleLabel,
  titleYear,
  worldLayout,
} from '../lib/title/world'
import type { World, WorldLaneKind, WorldTitle } from '../lib/title/world'

// GRAPH-007: `WorldMap`, a World drawn. A row per lane (books, films, shows…), each lane's titles
// in the server's order along a rail; a link between lanes is a rung. Finished titles are ticked
// and their rail is lit, the one to go to is ringed, titles the viewer does not have are quieter,
// and a side story is smaller. The server places everything; this only draws it. The lines are
// decoration: a screen reader gets one ordered list per lane.

export function WorldMap(props: { world: World }) {
  const layout = createMemo(() => worldLayout(props.world))
  const middle = WORLD.posterHeight / 2
  return (
    <div class="overflow-x-auto rounded-card border border-line bg-surface/40">
      <div
        class="relative rise"
        style={{
          width: `${layout().width}px`,
          height: `${layout().height}px`,
        }}
      >
        <svg
          class="pointer-events-none absolute inset-0"
          width={layout().width}
          height={layout().height}
          aria-hidden="true"
        >
          <For each={props.world.lanes}>
            {(lane, laneIndex) => (
              <For each={lane.titles.slice(1)}>
                {(title, i) => {
                  const from = () =>
                    tileOrigin({ lane: laneIndex(), column: i() })
                  const to = () =>
                    tileOrigin({ lane: laneIndex(), column: i() + 1 })
                  // Lit between two finished titles: the path the viewer has walked.
                  const walked = () =>
                    lane.titles[i()].status === 'finished' &&
                    title.status === 'finished'
                  return (
                    <line
                      x1={from().x + WORLD.tileWidth}
                      y1={from().y + middle}
                      x2={to().x}
                      y2={to().y + middle}
                      stroke="currentColor"
                      stroke-width={walked() ? 2.5 : 1.5}
                      stroke-linecap="round"
                      class={walked() ? 'text-accent' : 'text-line-strong'}
                    />
                  )
                }}
              </For>
            )}
          </For>
          <For each={layout().rungs}>
            {(rung) => {
              const path = () => rungPath(rung)
              return (
                <g class="text-line-strong">
                  <path
                    d={path().d}
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.25"
                    stroke-dasharray="4 4"
                  />
                  <circle
                    cx={path().end.x}
                    cy={path().end.y}
                    r="2.5"
                    fill="currentColor"
                  />
                </g>
              )
            }}
          </For>
        </svg>
        <For each={props.world.lanes}>
          {(lane, laneIndex) => {
            const count = () => laneCount(lane)
            const id = `world-lane-${lane.kind}`
            return (
              <section aria-labelledby={id}>
                <h3
                  id={id}
                  class="absolute flex items-center gap-2"
                  style={{
                    left: `${labelOrigin(laneIndex()).x}px`,
                    top: `${labelOrigin(laneIndex()).y}px`,
                    height: `${WORLD.labelHeight}px`,
                  }}
                >
                  <span class="eyebrow">{laneLabel(lane.kind)}</span>
                  <span class="text-xs text-muted tabular-nums">
                    {countLabel(count().finished, count().total)}
                  </span>
                </h3>
                <ol>
                  <For each={lane.titles}>
                    {(title, column) => (
                      <li
                        class="absolute"
                        style={{
                          left: `${tileOrigin({ lane: laneIndex(), column: column() }).x}px`,
                          top: `${tileOrigin({ lane: laneIndex(), column: column() }).y}px`,
                          width: `${WORLD.tileWidth}px`,
                        }}
                      >
                        <WorldTile
                          title={title}
                          lane={lane.kind}
                          startHere={props.world.startHere === title.key}
                        />
                      </li>
                    )}
                  </For>
                </ol>
              </section>
            )
          }}
        </For>
      </div>
    </div>
  )
}

/** One title on the map, opening its page: the Title room when it is in the library, else its
 * catalog page. */
function WorldTile(props: {
  title: WorldTitle
  lane: WorldLaneKind
  startHere: boolean
}) {
  const marked = () => props.startHere || props.title.next
  // A title the viewer does not have is quieter; the next step never is.
  const quiet = () => !props.title.libraryItemId && !marked()
  return (
    <TitleLink
      hit={{ type: props.title.ref.type, ids: props.title.ref.ids ?? {} }}
      libraryItemId={props.title.libraryItemId}
      class="group block"
      aria-label={titleLabel(props.title, props.lane, props.startHere)}
    >
      <div
        class="flex items-end justify-center"
        style={{ height: `${WORLD.posterHeight}px` }}
      >
        <div
          class={`relative ${props.title.side ? 'w-4/5' : 'w-full'} ${quiet() ? 'opacity-50' : ''} ${props.startHere ? 'rounded-thumb ring-2 ring-accent ring-offset-2 ring-offset-paper' : ''}`}
        >
          <Poster
            url={props.title.posterUrl}
            kind={laneKind(props.lane)}
            radius="thumb"
          >
            <Show when={marked()}>
              <Badge
                variant="ink"
                size="xs"
                class="absolute left-0.5 top-0.5 px-1.5 text-[10px] whitespace-nowrap"
              >
                {props.startHere ? 'Start here' : 'Next'}
              </Badge>
            </Show>
            <Show when={props.title.status === 'finished'}>
              <span class="absolute right-1 bottom-1 grid size-4 place-items-center rounded-full bg-accent text-on-accent">
                <svg viewBox="0 0 12 12" class="size-2.5" aria-hidden="true">
                  <path
                    d="M2.5 6.5 5 9l4.5-5.5"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.75"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </span>
            </Show>
          </Poster>
        </div>
      </div>
      <p class="mt-1 line-clamp-2 text-xs leading-snug break-words group-hover:underline">
        {props.title.ref.title}
      </p>
      <Show when={titleYear(props.title)}>
        {(year) => <p class="text-[11px] text-muted">{year()}</p>}
      </Show>
    </TitleLink>
  )
}

/** How far the viewer is through a World, as a bar. */
export function WorldProgress(props: { finished: number; total: number }) {
  return (
    <div class="h-1.5 overflow-hidden rounded-full bg-line" aria-hidden="true">
      <div
        class="h-full rounded-full bg-accent"
        style={{
          width: `${props.total > 0 ? Math.min(100, (props.finished / props.total) * 100) : 0}%`,
        }}
      />
    </div>
  )
}

/** What the map's marks mean. */
export function WorldLegend() {
  return (
    <ul class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
      <li class="flex items-center gap-1.5">
        <span class="size-2.5 rounded-full bg-accent" aria-hidden="true" />
        Finished
      </li>
      <li class="flex items-center gap-1.5">
        <span
          class="size-2.5 rounded-full ring-2 ring-accent"
          aria-hidden="true"
        />
        Start here
      </li>
      <li class="flex items-center gap-1.5">
        <span
          class="size-2.5 rounded-full border border-line-strong"
          aria-hidden="true"
        />
        Ahead
      </li>
    </ul>
  )
}
