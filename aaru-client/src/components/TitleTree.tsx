import {
  For,
  Show,
  createEffect,
  createSignal,
  on,
  onCleanup,
  onMount,
} from 'solid-js'
import {
  Badge,
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import { Poster } from './Poster'
import { TitleLink } from './TitleLink'
import { arrive } from '../lib/motion'
import { statusLabel } from '../lib/library/model'
import { loadTree } from '../lib/title/server'
import {
  TREE,
  branchLabel,
  hasBranches,
  tileState,
  treeLayout,
  treeNodeKind,
  treeNodeLabel,
  treeNodeYear,
} from '../lib/title/tree'
import type { TileState, TitleTree, TreeNode } from '../lib/title/tree'

// GRAPH-005: `TitleTree`, "From here". Where a title leads, in the manner of a game's skill
// tree: the title on the left, a trunk down from it, and a row for the person who made it, for
// its series and for its adaptations. Catalog data, the same for everyone: it never adds
// anything, and a tile opens that title's page.

const RETRY_PARTIAL_MS = 5000

/**
 * The tree for the title on screen, read in the browser after the page shows. A tree the server
 * cut short is asked for once more. A failed read leaves it null: the section is a signpost, and
 * its absence takes nothing away.
 */
export function createTitleTree(titleId: () => string) {
  const [tree, setTree] = createSignal<TitleTree | null>(null)
  let retry: ReturnType<typeof setTimeout> | undefined
  const load = (id: string, again: boolean): Promise<TitleTree | null> =>
    loadTree({ data: { titleId: id } })
      .then((t) => {
        // A page that moved on to another title ignores a late answer for the last one.
        if (id !== titleId()) return null
        setTree(t)
        if (t.partial && again)
          retry = setTimeout(() => void load(id, false), RETRY_PARTIAL_MS)
        return t
      })
      .catch(() => null)
  createEffect(
    on(titleId, (id) => {
      clearTimeout(retry)
      setTree(null)
      void load(id, true)
    }),
  )
  onCleanup(() => clearTimeout(retry))
  return {
    tree,
    /** Reads it again, so the marks follow a change the person just made. */
    refresh: () => {
      clearTimeout(retry)
      return load(titleId(), true)
    },
  }
}

/** The title page's "From here" section. Absent when the tree has no branch. */
export function TitleTreeSection(props: { tree: TitleTree | null }) {
  return (
    <Show when={hasBranches(props.tree) && props.tree}>
      {(tree) => (
        <section aria-labelledby="title-tree">
          <h2 id="title-tree" class="eyebrow">
            From here
          </h2>
          <TitleTreeCanvas tree={tree()} class="mt-3" />
        </section>
      )}
    </Show>
  )
}

/** The same tree, opened once when a tap on the page finishes the title. */
export function TitleTreeDialog(props: {
  open: boolean
  tree: TitleTree | null
  name: string
  onClose: () => void
}) {
  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          class="block w-[min(42rem,calc(100vw-2rem))] gap-0 p-0 sm:max-w-none"
        >
          <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
            <div class="min-w-0">
              <DialogTitle class="text-xl">From here</DialogTitle>
              <DialogDescription class="mt-1 truncate text-sm text-muted">
                Where {props.name} leads: who made it, and what comes after.
              </DialogDescription>
            </div>
            <Button
              variant="ghost"
              size="bare"
              class="text-sm"
              onClick={() => props.onClose()}
            >
              Done
            </Button>
          </div>
          <Show when={props.tree}>
            {(tree) => (
              <TitleTreeCanvas
                tree={tree()}
                class="px-5 py-5"
                entrance
                onOpen={() => props.onClose()}
              />
            )}
          </Show>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}

const RING: Record<TileState, string> = {
  root: 'ring-2 ring-accent',
  lit: 'ring-2 ring-accent',
  library: 'ring-1 ring-line',
  locked:
    'opacity-60 ring-1 ring-line transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100',
}

/**
 * The tree drawn: tiles over one layer of straight and right-angle lines, scrolled sideways on
 * a narrow screen. `entrance` plays the trunk and then the tiles in, once, for the dialog a tap
 * opened; on the page nothing moves.
 */
export function TitleTreeCanvas(props: {
  tree: TitleTree
  class?: string
  entrance?: boolean
  /** A tile was opened: the dialog closes behind it. */
  onOpen?: () => void
}) {
  const layout = () => treeLayout(props.tree)
  let canvas: HTMLDivElement | undefined
  onMount(() => {
    if (!props.entrance || !canvas) return
    void arrive([...canvas.querySelectorAll('[data-tree-part]')])
  })
  return (
    <div class={cn('overflow-x-auto', props.class)}>
      <div
        ref={canvas}
        class="relative"
        style={{
          width: `${layout().width}px`,
          height: `${layout().height}px`,
        }}
      >
        <svg
          data-tree-part
          class="pointer-events-none absolute inset-0 text-muted/40"
          width={layout().width}
          height={layout().height}
          aria-hidden="true"
        >
          <For each={layout().connectors}>
            {(line) => (
              <path
                d={line.d}
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linejoin="miter"
                class={line.lit ? 'text-accent' : undefined}
              />
            )}
          </For>
        </svg>
        <div
          data-tree-part
          class="absolute"
          style={{
            left: `${layout().root.x}px`,
            top: `${layout().root.y}px`,
            width: `${TREE.TILE_W}px`,
          }}
        >
          <Tile node={layout().root.node} />
        </div>
        <For each={layout().rows}>
          {(row) => (
            <>
              <h3
                class="eyebrow absolute truncate"
                style={{
                  left: `${row.x}px`,
                  top: `${row.y}px`,
                  'max-width': `${layout().width - row.x}px`,
                }}
              >
                {branchLabel(row.branch)}
              </h3>
              <ul aria-label={branchLabel(row.branch)}>
                <For each={row.tiles}>
                  {(tile) => (
                    <li
                      data-tree-part
                      class="absolute"
                      style={{
                        left: `${tile.x}px`,
                        top: `${tile.y}px`,
                        width: `${TREE.TILE_W}px`,
                      }}
                    >
                      <Tile node={tile.node} onOpen={props.onOpen} />
                    </li>
                  )}
                </For>
              </ul>
            </>
          )}
        </For>
      </div>
    </div>
  )
}

/** One title: its art in a 2:3 slot (a square cover sits at the foot), its name and year. The
 * root is the title on screen, so it is not a link. */
function Tile(props: { node: TreeNode; onOpen?: () => void }) {
  const state = () => tileState(props.node)
  const kind = () => treeNodeKind(props.node)
  const face = () => (
    <>
      <div class="flex items-end" style={{ height: `${TREE.TILE_H}px` }}>
        <div class={cn('w-full rounded-thumb', RING[state()])}>
          <Poster url={props.node.posterUrl} kind={kind()} radius="thumb">
            <Show when={props.node.pick === 'best_known'}>
              <Badge
                variant="ink"
                size="xs"
                class="absolute left-1 top-1"
                title="Best known"
                aria-hidden="true"
              >
                ★
              </Badge>
            </Show>
          </Poster>
        </div>
      </div>
      <p class="mt-1.5 line-clamp-2 text-xs leading-snug group-hover:underline">
        {props.node.ref.title}
      </p>
      <p class="text-xs text-muted">
        {state() === 'root' && props.node.status
          ? statusLabel(props.node.status, kind())
          : treeNodeYear(props.node)}
      </p>
    </>
  )
  return (
    <Show
      when={state() !== 'root'}
      fallback={
        <div aria-label={`${treeNodeLabel(props.node)}, this title`}>
          {face()}
        </div>
      }
    >
      <TitleLink
        hit={{ type: props.node.ref.type, ids: props.node.ref.ids ?? {} }}
        libraryItemId={props.node.libraryItemId}
        class="group block"
        aria-label={treeNodeLabel(props.node)}
        onClick={props.onOpen}
      >
        {face()}
      </TitleLink>
    </Show>
  )
}
