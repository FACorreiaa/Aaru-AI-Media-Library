import { For, Show } from 'solid-js'
import { Link } from '@tanstack/solid-router'
import { Badge, buttonVariants } from '~/components/ui'
import { Poster } from './Poster'
import { Segmented } from './Segmented'
import { TitleLink } from './TitleLink'
import { statusLabel } from '../lib/library/model'
import type { RoadmapSection } from '../lib/lists/roadmap'

// GRAPH-003: a roadmap list read as its steps. Numbered headings with their note; each title with
// its note ("FF #570-588"), Optional, and a bracket joining titles read side by side; what Aaru could
// not find stays as text in its step. Editing is the Order view's.

export function RoadmapSteps(props: {
  sections: RoadmapSection[]
  /** The first title in the roadmap the person has not finished or dropped. */
  startHere?: string
}) {
  return (
    <ol class="mt-6 flex max-w-[56rem] flex-col gap-8">
      <For each={props.sections}>
        {(section, index) => (
          <li>
            <h2 class="font-display text-xl font-semibold">
              <span class="text-muted">{index() + 1}.</span> {section.heading}
            </h2>
            <Show when={section.note}>
              {(note) => <p class="mt-1 text-sm text-muted">{note()}</p>}
            </Show>
            <ul class="mt-3 divide-y divide-line">
              <For each={section.entries}>
                {(entry, i) => {
                  const pairedAbove = () =>
                    entry.pair !== undefined &&
                    section.entries[i() - 1]?.pair === entry.pair
                  const pairedBelow = () =>
                    entry.pair !== undefined &&
                    section.entries[i() + 1]?.pair === entry.pair
                  return (
                    <li
                      class={`flex items-center gap-4 py-3 ${entry.pair !== undefined ? 'border-l-2 border-l-accent pl-3' : ''}`}
                    >
                      <TitleLink
                        hit={entry.row.hit}
                        libraryItemId={entry.row.libraryItemId}
                        class="flex min-w-0 flex-1 items-center gap-4"
                      >
                        <Poster
                          url={entry.row.posterUrl}
                          kind={entry.row.kind}
                          class="w-11 shrink-0"
                        />
                        <div class="min-w-0 flex-1">
                          <p class="line-clamp-2 font-medium">
                            {entry.row.title}
                          </p>
                          <Show when={entry.note}>
                            {(note) => (
                              <p class="text-sm text-muted">{note()}</p>
                            )}
                          </Show>
                          <p class="mt-0.5 flex flex-wrap items-center gap-1.5">
                            <Show when={props.startHere === entry.row.titleId}>
                              <Badge variant="ink" size="xs">
                                Start here
                              </Badge>
                            </Show>
                            <Show when={entry.optional}>
                              <Badge variant="soft" size="xs">
                                Optional
                              </Badge>
                            </Show>
                            <Show when={pairedBelow() && !pairedAbove()}>
                              <Badge variant="soft" size="xs">
                                Read side by side
                              </Badge>
                            </Show>
                            <Show when={entry.row.status}>
                              {(status) => (
                                <span class="text-xs text-muted">
                                  {statusLabel(status(), entry.row.kind)}
                                </span>
                              )}
                            </Show>
                          </p>
                        </div>
                      </TitleLink>
                    </li>
                  )
                }}
              </For>
            </ul>
            <Show when={section.missing.length > 0}>
              <div class="mt-2 text-sm text-muted">
                <p>Not found in Aaru's catalog:</p>
                <ul class="mt-1 list-disc pl-5">
                  <For each={section.missing}>{(m) => <li>{m}</li>}</For>
                </ul>
              </div>
            </Show>
          </li>
        )}
      </For>
    </ol>
  )
}

/** The first title in step order the person has not finished or dropped, skipping optional ones. */
export function roadmapStartHere(
  sections: RoadmapSection[],
): string | undefined {
  for (const section of sections)
    for (const entry of section.entries) {
      if (entry.optional) continue
      const status = entry.row.status
      if (status === 'finished' || status === 'dropped') continue
      return entry.row.titleId
    }
  return undefined
}

/** The Steps / Order switch and, on Steps, the steps: loaded only by a list that has a roadmap. */
export function RoadmapView(props: {
  listId: string
  sections: RoadmapSection[]
  view: 'steps' | 'order'
  onView: (view: 'steps' | 'order') => void
}) {
  return (
    <>
      <div class="mt-8 flex flex-wrap items-center gap-3">
        <Segmented
          label="View"
          value={props.view}
          onChange={props.onView}
          options={[
            { value: 'steps', label: 'Steps' },
            { value: 'order', label: 'Order' },
          ]}
        />
        <Link
          to="/app/lists/$id/graph"
          params={{ id: props.listId }}
          class={buttonVariants({ variant: 'outline', size: 'sm' })}
        >
          Graph
        </Link>
      </div>
      <Show when={props.view === 'steps'}>
        <RoadmapSteps
          sections={props.sections}
          startHere={roadmapStartHere(props.sections)}
        />
      </Show>
    </>
  )
}
