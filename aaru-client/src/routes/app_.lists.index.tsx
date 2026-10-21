import { Link, createFileRoute } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onCleanup } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { AlertDialog } from '../components/ui/alert-dialog'
import { Button } from '../components/ui/button'
import {
  createList,
  deleteList,
  getLists,
  renameList,
} from '../lib/lists/server'
import type { ListSummary } from '../lib/lists/server'
import { flip, leave } from '../lib/motion'
import { requireSession } from '../lib/session/query'

// APP-006 on the web: every list, with create, rename and delete.
export const Route = createFileRoute('/app_/lists/')({
  head: () => ({ meta: [{ title: 'Lists · Aaru' }] }),
  beforeLoad: async ({ context }) => {
    await requireSession(context.queryClient)
  },
  loader: () => getLists(),
  component: Lists,
})

function Lists() {
  const loaded = Route.useLoaderData()
  const [lists, setLists] = createSignal<ListSummary[]>(loaded())
  const [name, setName] = createSignal('')
  const [editing, setEditing] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [pending, setPending] = createSignal<ListSummary | null>(null)
  const [deleting, setDeleting] = createSignal(false)
  // The last list asked about, so the dialog keeps its title while it fades out.
  const asked = createMemo<ListSummary | null>(
    (last) => pending() ?? last,
    null,
  )
  let shelf: HTMLUListElement | undefined
  // Each row's element, so a delete can play its exit before it leaves the DOM.
  const rowEls = new Map<string, HTMLLIElement>()

  /** After a delete: the row fades out, then the lists below slide up into its place. */
  async function drop(id: string) {
    const el = rowEls.get(id)
    if (el) await leave(el)
    const mutate = () => setLists(lists().filter((l) => l.id !== id))
    if (shelf) await flip(shelf, mutate)
    else mutate()
  }

  const summary = (detail: {
    id: string
    name: string
    titles: unknown[]
    createdAt: string
    updatedAt: string
  }): ListSummary => ({
    id: detail.id,
    name: detail.name,
    itemCount: detail.titles.length,
    createdAt: detail.createdAt,
    updatedAt: detail.updatedAt,
  })

  async function run(action: () => Promise<void>) {
    setProblem(null)
    try {
      await action()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That change was not saved.',
      )
    }
  }

  return (
    <div class="min-h-[100dvh]">
      <AppHeader class="max-w-3xl" />
      <main class="mx-auto max-w-3xl px-5 pb-20 md:px-8">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Lists
        </h1>
        <form
          class="mt-6 flex gap-2"
          onSubmit={(e) => {
            e.preventDefault()
            void run(async () => {
              const created = await createList({ data: { name: name() } })
              setLists([summary(created), ...lists()])
              setName('')
            })
          }}
        >
          <label for="list-name" class="sr-only">
            New list name
          </label>
          <input
            id="list-name"
            placeholder="Name a new list"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            class="min-h-11 flex-1 rounded-full border-0 bg-surface px-5 text-base focus:ring-2 focus:ring-accent"
          />
          <Button type="submit" variant="primary" disabled={!name().trim()}>
            Create
          </Button>
        </form>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
        <Show
          when={lists().length > 0}
          fallback={
            <p class="mt-16 text-center text-muted">
              No lists yet. Make one for a theme, a marathon or a book club.
            </p>
          }
        >
          <ul ref={shelf} class="mt-8 divide-y divide-line">
            <For each={lists()}>
              {(list) => (
                <li
                  ref={(el) => {
                    rowEls.set(list.id, el)
                    onCleanup(() => rowEls.delete(list.id))
                  }}
                  class="flex items-center gap-4 py-4"
                >
                  <Show
                    when={editing() === list.id}
                    fallback={
                      <Link
                        to="/app/lists/$id"
                        params={{ id: list.id }}
                        class="min-w-0 flex-1 hover:text-accent"
                      >
                        <span class="block truncate text-lg font-medium">
                          {list.name}
                        </span>
                        <span class="text-sm text-muted">
                          {list.itemCount === 1
                            ? '1 title'
                            : `${list.itemCount} titles`}
                        </span>
                      </Link>
                    }
                  >
                    <form
                      class="flex flex-1 gap-2"
                      onSubmit={(e) => {
                        e.preventDefault()
                        const value =
                          new FormData(e.currentTarget)
                            .get('name')
                            ?.toString() ?? ''
                        void run(async () => {
                          const renamed = await renameList({
                            data: { id: list.id, name: value },
                          })
                          setLists(
                            lists().map((l) =>
                              l.id === list.id ? summary(renamed) : l,
                            ),
                          )
                          setEditing(null)
                        })
                      }}
                    >
                      <input
                        name="name"
                        aria-label="List name"
                        value={list.name}
                        autofocus
                        class="min-h-10 flex-1 rounded-full border-0 bg-surface px-4 focus:ring-2 focus:ring-accent"
                      />
                      <button
                        type="submit"
                        class="text-sm font-semibold text-accent"
                      >
                        Save
                      </button>
                    </form>
                  </Show>
                  <button
                    type="button"
                    class="text-sm text-muted hover:text-ink"
                    onClick={() =>
                      setEditing(editing() === list.id ? null : list.id)
                    }
                  >
                    {editing() === list.id ? 'Cancel' : 'Rename'}
                  </button>
                  <button
                    type="button"
                    class="text-sm text-muted hover:text-danger"
                    onClick={() => setPending(list)}
                  >
                    Delete
                  </button>
                </li>
              )}
            </For>
          </ul>
        </Show>
        <AlertDialog
          open={pending() !== null}
          title={`Delete ${asked()?.name ?? ''}?`}
          description="The list goes; the titles stay in your library."
          confirmLabel="Delete list"
          busy={deleting()}
          onConfirm={() => {
            const list = pending()
            if (!list) return
            setDeleting(true)
            let deleted = false
            void run(async () => {
              await deleteList({ data: { id: list.id } })
              deleted = true
            }).finally(() => {
              setDeleting(false)
              setPending(null)
              if (deleted) void drop(list.id)
            })
          }}
          onCancel={() => setPending(null)}
        />
      </main>
    </div>
  )
}
