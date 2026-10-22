import { Link, createFileRoute } from '@tanstack/solid-router'
import { BackLink } from '../components/shell/BackLink'
import {
  For,
  Show,
  Suspense,
  createMemo,
  createSignal,
  lazy,
  onCleanup,
  onMount,
} from 'solid-js'
import type { JSX } from 'solid-js'
import { AddControl } from '../components/AddControl'
import { Poster } from '../components/Poster'
import { Button, Dialog, DialogContent, DialogPortal } from '~/components/ui'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { KINDS, statusLabel } from '../lib/library/model'
import type { CatalogHit, LibraryStatus } from '../lib/library/model'
import { addToLibrary } from '../lib/library/server'
import { toListRow } from '../lib/lists/model'
import type { ListRow } from '../lib/lists/model'
import { removeFromList, reorderList } from '../lib/lists/server'
import type { ListDetail } from '../lib/lists/server'
import { createFocusReturn, focusFieldOnOpen } from '../lib/dialog-focus'
import { flip, leave } from '../lib/motion'
import { listQuery } from '../lib/queries'

// APP-006 on the web: one list, in order, with remove and move up/down. LST-003: rows carry
// library status and progress, show status and the next airing; "Add titles" searches into it.
// Search loads only when it is first opened: it is not part of the page's first paint.
const SearchPanel = lazy(() =>
  import('../components/SearchPanel').then((m) => ({ default: m.SearchPanel })),
)

export const Route = createFileRoute('/_shell/app_/lists/$id')({
  loader: ({ params, context: { queryClient } }) =>
    queryClient.query(listQuery(params.id)),
  // UX-013: the tab names the list.
  head: ({ loaderData }) => ({
    meta: [{ title: `${loaderData?.name ?? 'List'} · Lists · Aaru` }],
  }),
  component: ListPage,
})

function ListPage() {
  const loaded = Route.useLoaderData()
  const [detail, setDetail] = createSignal<ListDetail>(loaded())
  const [problem, setProblem] = createSignal<string | null>(null)
  // Set on mount, not during SSR: "Tomorrow" depends on the viewer's clock and timezone.
  const [now, setNow] = createSignal<Date | null>(null)
  const [searchOpened, setSearchOpened] = createSignal(false)
  const [pending, setPending] = createSignal<ListRow | null>(null)
  const [removing, setRemoving] = createSignal(false)
  // The last row asked about, so the dialog keeps its title while it fades out.
  const asked = createMemo<ListRow | null>((last) => pending() ?? last, null)
  const [searchOpen, setSearchOpen] = createSignal(false)
  // Members being added to the library right now, by title id.
  const [adding, setAdding] = createSignal<ReadonlySet<string>>(new Set())
  let list: HTMLOListElement | undefined
  // Each row's element, so a removal can play its exit before it leaves the DOM.
  const rowEls = new Map<string, HTMLLIElement>()
  onMount(() => setNow(new Date()))

  const rows = createMemo(() =>
    detail().items.map((item) => toListRow(item, now())),
  )
  const rowById = createMemo(
    () => new Map(rows().map((row) => [row.titleId, row])),
  )
  // Rows are keyed by title id, so a server answer keeps their elements and a move or a
  // removal can slide the others (FLIP) instead of redrawing the list.
  const ids = createMemo(() => rows().map((row) => row.titleId))

  /** Applies a state change, sliding the rows that move. */
  function reflow(mutate: () => void) {
    if (list) void flip(list, mutate)
    else mutate()
  }

  const focusReturn = createFocusReturn()
  function openSearch(event: MouseEvent) {
    focusReturn.remember(event.currentTarget as Element)
    setSearchOpened(true)
    setSearchOpen(true)
  }

  async function move(index: number, by: -1 | 1) {
    const before = detail()
    const items = [...before.items]
    const [moved] = items.splice(index, 1)
    items.splice(index + by, 0, moved)
    reflow(() => setDetail({ ...before, items })) // optimistic; the server's order wins
    setProblem(null)
    try {
      setDetail(
        await reorderList({
          data: { id: before.id, titleIds: items.map((i) => i.title.id) },
        }),
      )
    } catch (error) {
      setDetail(before)
      setProblem(
        error instanceof Error ? error.message : 'The new order was not saved.',
      )
    }
  }

  /** UX-072: a member only on the list joins the library from its row, as on Discover. */
  async function addMember(
    titleId: string,
    hit: CatalogHit,
    status: LibraryStatus,
  ) {
    if (adding().has(titleId)) return
    setAdding(new Set([...adding(), titleId]))
    setProblem(null)
    try {
      const entry = await addToLibrary({
        data: {
          type: hit.type,
          ids: hit.ids,
          title: hit.title,
          year: hit.year,
          status,
        },
      })
      const current = detail()
      setDetail({
        ...current,
        items: current.items.map((item) =>
          item.title.id === titleId ? { ...item, entry } : item,
        ),
      })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : `${hit.title} could not be added.`,
      )
    } finally {
      const rest = new Set(adding())
      rest.delete(titleId)
      setAdding(rest)
    }
  }

  /** Removes after the confirm: the dialog closes, the row fades out, the rest slide up. */
  async function remove(titleId: string) {
    setProblem(null)
    setRemoving(true)
    let next: ListDetail
    try {
      next = await removeFromList({ data: { id: detail().id, titleId } })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'The title could not be removed.',
      )
      return
    } finally {
      setRemoving(false)
      setPending(null)
    }
    const el = rowEls.get(titleId)
    if (el) await leave(el)
    reflow(() => setDetail(next))
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/lists" label="Lists" class="-ml-1" />
        <div class="mt-4 flex items-end justify-between gap-4">
          <h1 class="font-display text-4xl font-medium tracking-tight">
            {detail().name}
          </h1>
          <Button
            variant="outline"
            size="sm"
            class="shrink-0"
            onClick={openSearch}
          >
            Add titles
          </Button>
        </div>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
        <Show
          when={rows().length > 0}
          fallback={
            <div class="mt-16 text-center">
              <p class="text-muted">Nothing on this list yet.</p>
              <Button
                variant="default"
                size="lg"
                class="mt-6"
                onClick={openSearch}
              >
                Add titles
              </Button>
            </div>
          }
        >
          {/* An ordered list reads top to bottom: one column, at a width rows can be read. */}
          <ol ref={list} class="mt-8 max-w-[56rem] divide-y divide-line">
            <For each={ids()}>
              {(id, index) => {
                // The last known row: it stays drawn while a removed one is torn down.
                const row = createMemo<ListRow>(
                  (last) => rowById().get(id) ?? last,
                  rowById().get(id)!,
                )
                onCleanup(() => rowEls.delete(id))
                return (
                  <li
                    ref={(el) => rowEls.set(id, el)}
                    class="flex items-center gap-4 py-3"
                  >
                    <RowLink libraryItemId={row().libraryItemId}>
                      <Poster
                        url={row().posterUrl}
                        kind={row().kind}
                        class="w-11 shrink-0"
                      />
                      <div class="min-w-0 flex-1">
                        <p class="line-clamp-2 font-medium">{row().title}</p>
                        <p class="truncate text-sm text-muted">
                          {(row().kind === 'album'
                            ? [row().byline, row().year]
                            : [
                                row().year,
                                KINDS.find((k) => k.kind === row().kind)?.label,
                                row().network,
                              ]
                          )
                            .filter(Boolean)
                            .join(' · ')}
                        </p>
                        <Show
                          when={
                            row().status || row().showStatus || row().airing
                          }
                        >
                          <p class="flex flex-wrap items-center gap-x-2 text-sm text-muted">
                            <Show when={row().showStatus}>
                              {(label) => (
                                <span class="rounded-full border border-line px-2 text-xs">
                                  {label()}
                                </span>
                              )}
                            </Show>
                            <Show when={row().airing}>
                              {(label) => (
                                <span class="text-accent">{label()}</span>
                              )}
                            </Show>
                            <Show when={row().status}>
                              {(status) => (
                                <span>
                                  {[
                                    statusLabel(status(), row().kind),
                                    row().detail,
                                  ]
                                    .filter(Boolean)
                                    .join(' · ')}
                                </span>
                              )}
                            </Show>
                          </p>
                        </Show>
                      </div>
                    </RowLink>
                    <div class="flex items-center gap-1 text-sm">
                      <Show when={row().hit}>
                        {(hit) => (
                          <div class="mr-2">
                            <AddControl
                              hit={hit()}
                              adding={adding().has(id)}
                              idPrefix="list"
                              onAdd={(status) =>
                                void addMember(id, hit(), status)
                              }
                            />
                          </div>
                        )}
                      </Show>
                      <Button
                        variant="soft"
                        size="bare"
                        aria-label={`Move ${row().title} up`}
                        disabled={index() === 0}
                        class="px-2 py-1"
                        onClick={() => move(index(), -1)}
                      >
                        ↑
                      </Button>
                      <Button
                        variant="soft"
                        size="bare"
                        aria-label={`Move ${row().title} down`}
                        disabled={index() === rows().length - 1}
                        class="px-2 py-1"
                        onClick={() => move(index(), 1)}
                      >
                        ↓
                      </Button>
                      <Button
                        variant="ghost"
                        size="bare"
                        class="ml-2 min-h-9 px-1.5 text-sm hover:text-danger"
                        onClick={() => setPending(row())}
                      >
                        Remove
                      </Button>
                    </div>
                  </li>
                )
              }}
            </For>
          </ol>
        </Show>
        <ConfirmDialog
          open={pending() !== null}
          title={`Remove ${asked()?.title ?? ''} from this list?`}
          confirmLabel="Remove"
          busy={removing()}
          onConfirm={() => {
            const row = pending()
            if (row) void remove(row.titleId)
          }}
          onCancel={() => setPending(null)}
        />
      </div>

      <Dialog open={searchOpen()} onOpenChange={setSearchOpen}>
        <DialogPortal>
          <DialogContent
            showCloseButton={false}
            aria-label={`Add to ${detail().name}`}
            onOpenAutoFocus={focusFieldOnOpen}
            onCloseAutoFocus={focusReturn.restore}
            class="block gap-0 p-0 w-[min(40rem,calc(100vw-2rem))]"
          >
            <Show when={searchOpened()}>
              <Suspense
                fallback={
                  <p class="px-5 py-8 text-center text-sm text-muted">
                    Loading…
                  </p>
                }
              >
                <SearchPanel
                  list={detail()}
                  onListChanged={setDetail}
                  onClose={() => setSearchOpen(false)}
                />
              </Suspense>
            </Show>
          </DialogContent>
        </DialogPortal>
      </Dialog>
    </div>
  )
}

/** A member in the library opens its title page; one only on the list has none to open. */
function RowLink(props: { libraryItemId?: string; children: JSX.Element }) {
  return (
    <Show
      when={props.libraryItemId}
      fallback={
        <div class="flex min-w-0 flex-1 items-center gap-4">
          {props.children}
        </div>
      }
    >
      {(id) => (
        <Link
          to="/app/title/$id"
          params={{ id: id() }}
          class="flex min-w-0 flex-1 items-center gap-4"
        >
          {props.children}
        </Link>
      )}
    </Show>
  )
}
