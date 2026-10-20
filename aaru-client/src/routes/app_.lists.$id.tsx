import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { Wordmark } from '../components/Brand'
import { Poster } from '../components/Poster'
import { SearchPanel } from '../components/SearchPanel'
import { Button } from '../components/ui/button'
import { KINDS, statusLabel } from '../lib/library/model'
import { toListRow } from '../lib/lists/model'
import { getList, removeFromList, reorderList } from '../lib/lists/server'
import type { ListDetail } from '../lib/lists/server'
import { getSession } from '../lib/session/session'

// APP-006 on the web: one list, in order, with remove and move up/down. LST-003: rows carry
// library status and progress, show status and the next airing; "Add titles" searches into it.
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
  let dialog: HTMLDialogElement | undefined
  onMount(() => setNow(new Date()))

  const rows = createMemo(() =>
    detail().items.map((item) => toListRow(item, now())),
  )

  function openSearch() {
    setSearchOpened(true)
    dialog?.showModal()
  }

  async function move(index: number, by: -1 | 1) {
    const before = detail()
    const items = [...before.items]
    const [moved] = items.splice(index, 1)
    items.splice(index + by, 0, moved)
    setDetail({ ...before, items }) // optimistic; the server's order wins
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

  async function remove(titleId: string) {
    setProblem(null)
    try {
      setDetail(await removeFromList({ data: { id: detail().id, titleId } }))
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'The title could not be removed.',
      )
    }
  }

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-3xl items-center justify-between px-5 md:px-8">
        <Wordmark />
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
          <ol class="mt-8 divide-y divide-line">
            <For each={rows()}>
              {(row, index) => (
                <li class="flex items-center gap-4 py-3">
                  <RowLink libraryItemId={row.libraryItemId}>
                    <Poster
                      url={row.posterUrl}
                      kind={row.kind}
                      class="w-11 shrink-0"
                    />
                    <div class="min-w-0 flex-1">
                      <p class="line-clamp-2 font-medium">{row.title}</p>
                      <p class="truncate text-sm text-muted">
                        {[
                          row.year,
                          KINDS.find((k) => k.kind === row.kind)?.label,
                          row.network,
                        ]
                          .filter(Boolean)
                          .join(' · ')}
                      </p>
                      <Show when={row.status || row.showStatus || row.airing}>
                        <p class="flex flex-wrap items-center gap-x-2 text-sm text-muted">
                          <Show when={row.showStatus}>
                            {(label) => (
                              <span class="rounded-full border border-line px-2 text-xs">
                                {label()}
                              </span>
                            )}
                          </Show>
                          <Show when={row.airing}>
                            {(label) => (
                              <span class="text-accent">{label()}</span>
                            )}
                          </Show>
                          <Show when={row.status}>
                            {(status) => (
                              <span>
                                {[statusLabel(status(), row.kind), row.detail]
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
                      aria-label={`Move ${row.title} up`}
                      disabled={index() === 0}
                      class="px-2 py-1"
                      onClick={() => move(index(), -1)}
                    >
                      ↑
                    </Button>
                    <Button
                      variant="soft"
                      size="bare"
                      aria-label={`Move ${row.title} down`}
                      disabled={index() === rows().length - 1}
                      class="px-2 py-1"
                      onClick={() => move(index(), 1)}
                    >
                      ↓
                    </Button>
                    <button
                      type="button"
                      class="ml-2 text-muted hover:text-danger"
                      onClick={() => remove(row.titleId)}
                    >
                      Remove
                    </button>
                  </div>
                </li>
              )}
            </For>
          </ol>
        </Show>
      </main>

      <dialog
        ref={dialog}
        aria-label={`Add to ${detail().name}`}
        class="m-auto w-[min(40rem,calc(100vw-2rem))] rounded-card bg-paper p-0 text-ink shadow-2xl backdrop:bg-black/40"
        onClick={(e) => {
          // A click on the backdrop closes it.
          if (e.target === dialog) dialog.close()
        }}
      >
        <Show when={searchOpened()}>
          <SearchPanel
            list={detail()}
            onListChanged={setDetail}
            onClose={() => dialog?.close()}
          />
        </Show>
      </dialog>
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
