import { Link } from '@tanstack/solid-router'
import { For, Show, createEffect, createSignal, on, onCleanup } from 'solid-js'
import { Badge, Button, buttonVariants } from '~/components/ui'
import { Poster } from './Poster'
import { TitleLink } from './TitleLink'
import { statusLabel } from '../lib/library/model'
import { loadRelations } from '../lib/title/server'
import {
  RELATED_GROUP_LABELS,
  centreOf,
  nodeCaption,
  nodeKind,
  relatedGroups,
} from '../lib/title/relations'
import type { RelationGraph, RelationNode } from '../lib/title/relations'

// GRAPH-002: `RelatedRow`, the title room's Related section. Read in the browser after the room
// shows. Nothing related leaves the section out; a failed read says so and offers to try again
// (a silent failure looked exactly like "nothing related"). A graph the server cut short is asked
// for once more, when the rest is cached.

const RETRY_PARTIAL_MS = 5000

export function RelatedTitles(props: { titleId: string }) {
  const [graph, setGraph] = createSignal<RelationGraph | null>(null)
  const [failed, setFailed] = createSignal(false)
  let retry: ReturnType<typeof setTimeout> | undefined
  const load = (titleId: string, again: boolean) =>
    loadRelations({ data: { titleId } })
      .then((g) => {
        // A page that moved on to another title ignores a late answer for the last one.
        if (titleId !== props.titleId) return
        setGraph(g)
        setFailed(false)
        if (g.partial && again)
          retry = setTimeout(() => void load(titleId, false), RETRY_PARTIAL_MS)
      })
      .catch(() => {
        // A late failure for a title the page left, or behind a graph already shown, says nothing.
        if (titleId === props.titleId && !graph()) setFailed(true)
      })
  // Read in the browser only, and again whenever the page moves to another title.
  createEffect(
    on(
      () => props.titleId,
      (titleId) => {
        clearTimeout(retry)
        setGraph(null)
        setFailed(false)
        void load(titleId, true)
      },
    ),
  )
  onCleanup(() => clearTimeout(retry))

  const groups = () => {
    const g = graph()
    const centre = g && centreOf(g)
    return g && centre ? relatedGroups(g, centre.key) : []
  }

  return (
    <Show
      when={groups().length > 0}
      fallback={
        <Show when={failed()}>
          <section aria-labelledby="related-titles">
            <h2 id="related-titles" class="eyebrow">
              Related
            </h2>
            <p role="status" class="mt-3 text-sm text-muted">
              Related titles could not be loaded.
            </p>
            <Button
              variant="outline"
              size="sm"
              class="mt-3"
              onClick={() => {
                setFailed(false)
                void load(props.titleId, true)
              }}
            >
              Try again
            </Button>
          </section>
        </Show>
      }
    >
      <section aria-labelledby="related-titles">
        <div class="flex items-baseline justify-between gap-4">
          <h2 id="related-titles" class="eyebrow">
            Related
          </h2>
          <Link
            to="/app/graph/$titleId"
            params={{ titleId: props.titleId }}
            class={buttonVariants({ variant: 'outline', size: 'sm' })}
          >
            Graph
          </Link>
        </div>
        <div class="mt-3 flex flex-col gap-5">
          <For each={groups()}>
            {(group) => (
              <div>
                <h3 class="text-sm font-medium text-muted">
                  {RELATED_GROUP_LABELS[group.group]}
                </h3>
                <ul class="mt-2 flex gap-3 overflow-x-auto pb-2">
                  <For each={group.nodes}>
                    {(node) => (
                      <li class="w-24 shrink-0">
                        <RelatedCard
                          node={node}
                          startHere={graph()?.startHere === node.key}
                        />
                      </li>
                    )}
                  </For>
                </ul>
              </div>
            )}
          </For>
        </div>
      </section>
    </Show>
  )
}

/** One related title: its poster, name and year, and the caller's status on it. */
export function RelatedCard(props: { node: RelationNode; startHere: boolean }) {
  const kind = () => nodeKind(props.node)
  return (
    <TitleLink
      hit={{ type: props.node.ref.type, ids: props.node.ref.ids ?? {} }}
      libraryItemId={props.node.libraryItemId}
      class="group block"
    >
      <Poster url={props.node.posterUrl} kind={kind()} radius="thumb" frame>
        <Show when={props.startHere}>
          <Badge variant="ink" size="xs" class="absolute left-1 top-1">
            Start here
          </Badge>
        </Show>
      </Poster>
      <p class="mt-1.5 line-clamp-2 text-sm leading-snug group-hover:underline">
        {props.node.ref.title}
      </p>
      <p class="text-xs text-muted">{nodeCaption(props.node)}</p>
      <Show when={props.node.status}>
        {(status) => (
          <Badge variant="soft" size="xs" class="mt-1">
            {statusLabel(status(), kind())}
          </Badge>
        )}
      </Show>
    </TitleLink>
  )
}
