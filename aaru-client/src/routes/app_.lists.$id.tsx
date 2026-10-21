import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
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
import { Wordmark } from '../components/Brand'
import { Poster } from '../components/Poster'
import { AlertDialog } from '../components/ui/alert-dialog'
import { Button } from '../components/ui/button'
import { Dialog } from '../components/ui/dialog'
import { KINDS, statusLabel } from '../lib/library/model'
import { toListRow } from '../lib/lists/model'
import type { ListRow } from '../lib/lists/model'
import { getList, removeFromList, reorderList } from '../lib/lists/server'
import type { ListDetail } from '../lib/lists/server'
import { flip, leave } from '../lib/motion'
import { getSession } from '../lib/session/session'

// APP-006 on the web: one list, in order, with remove and move up/down. LST-003: rows carry
// library status and progress, show status and the next airing; "Add titles" searches into it.
// Search loads only when it is first opened: it is not part of the page's first paint.
const SearchPanel = lazy(() =>
  import('../components/SearchPanel').then((m) => ({ default: m.SearchPanel })),
)

export const Route = createFileRoute('/app_/lists/$id')({
  head: () => ({ meta: [{ title: 'List · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: ({ params }) => getList({ data: { id: params.id } }),
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
  let dialog: HTMLDialogElement | undefined
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

  function openSearch() {
    setSearchOpened(true)
    dialog?.showModal()
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
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-3xl items-center justify-between px-5 md:px-8">
        <Wordmark to="/app" />
        <Link
          to="/app/lists"
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Lists
        </Link>
      </header>
      <main class="mx-auto max-w-3xl px-5 pb-20 md:px-8">
        <div class="mt-4 flex items-end justify-between gap-4">
          <h1 class="font-display text-4xl font-medium tracking-tight">
            {detail().name}
          </h1>
          <Button size="sm" class="shrink-0" onClick={openSearch}>
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
                variant="primary"
                size="lg"
                class="mt-6"
                onClick={openSearch}
              >
                Add titles
              </Button>
            </div>
          }
        >
          <ol ref={list} class="mt-8 divide-y divide-line">
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
                      <button
                        type="button"
                        class="ml-2 text-muted hover:text-danger"
                        onClick={() => setPending(row())}
                      >
                        Remove
                      </button>
                    </div>
                  </li>
                )
              }}
            </For>
          </ol>
        </Show>
        <AlertDialog
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
      </main>

      <Dialog
        ref={dialog}
        aria-label={`Add to ${detail().name}`}
        class="w-[min(40rem,calc(100vw-2rem))]"
      >
        <Show when={searchOpened()}>
          <Suspense
            fallback={
              <p class="px-5 py-8 text-center text-sm text-muted">Loading…</p>
            }
          >
            <SearchPanel
              list={detail()}
              onListChanged={setDetail}
              onClose={() => dialog?.close()}
            />
          </Suspense>
        </Show>
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
