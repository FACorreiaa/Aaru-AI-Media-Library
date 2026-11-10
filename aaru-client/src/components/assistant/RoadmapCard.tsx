import { Link } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import { Badge, buttonVariants } from '~/components/ui'
import {
  itemLine,
  roadmapSummary,
  startsPair,
} from '../../lib/assistant/roadmap'
import type { ChatRoadmap } from '../../lib/assistant/roadmap'

// ASK-011 (VIEWS.md `RoadmapCard`): the list Aaru planned in a chat, in its steps, as Aaru named
// the titles and before any is matched. Read-only, with one action: the import's review, where
// they are matched and nothing is added until the user approves.
export function RoadmapCard(props: {
  roadmap: ChatRoadmap
  /** The import that holds it; gone when the import was deleted. */
  importId: string | null
  onReview: () => void
}) {
  return (
    <article class="edge-lit rounded-card bg-surface p-5">
      <Show when={props.roadmap.listName}>
        {(name) => <h3 class="font-display text-xl font-medium">{name()}</h3>}
      </Show>
      <p class="mt-1 text-sm text-muted">
        {roadmapSummary(props.roadmap)} · nothing is added until you review
      </p>
      <ol class="mt-4 flex flex-col gap-5">
        <For each={props.roadmap.steps}>
          {(step, index) => (
            <li>
              <Show when={step.heading}>
                {(heading) => (
                  <h4 class="font-display font-semibold">
                    <span class="text-muted">{index() + 1}.</span> {heading()}
                  </h4>
                )}
              </Show>
              <Show when={step.note}>
                {(note) => <p class="mt-0.5 text-sm text-muted">{note()}</p>}
              </Show>
              <ul class="mt-2 divide-y divide-line">
                <For each={step.items}>
                  {(item, i) => (
                    <li
                      class="py-2"
                      classList={{
                        'border-l-2 border-l-accent pl-3':
                          item.pair !== undefined,
                      }}
                    >
                      <p class="font-medium">{item.title}</p>
                      <p class="flex flex-wrap items-center gap-1.5 text-sm text-muted">
                        <span>{itemLine(item)}</span>
                        <Show when={item.optional}>
                          <Badge variant="soft" size="xs">
                            Optional
                          </Badge>
                        </Show>
                        <Show when={startsPair(step.items, i())}>
                          <Badge variant="soft" size="xs">
                            Side by side
                          </Badge>
                        </Show>
                      </p>
                      <Show when={item.note}>
                        {(note) => <p class="text-sm text-muted">{note()}</p>}
                      </Show>
                    </li>
                  )}
                </For>
              </ul>
            </li>
          )}
        </For>
      </ol>
      <Show
        when={props.importId}
        fallback={
          <p class="mt-4 text-sm text-muted">
            The review for this list was deleted.
          </p>
        }
      >
        {(id) => (
          <Link
            to="/app/imports/$id"
            params={{ id: id() }}
            onClick={props.onReview}
            class={`mt-4 ${buttonVariants({ size: 'sm' })}`}
          >
            Review and save
          </Link>
        )}
      </Show>
    </article>
  )
}
