import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Wordmark } from '../components/Brand'
import {
  createList,
  deleteList,
  getLists,
  renameList,
} from '../lib/lists/server'
import type { ListSummary } from '../lib/lists/server'
import { getSession } from '../lib/session/session'

// APP-006 on the web: every list, with create, rename and delete.
export const Route = createFileRoute('/app_/lists/')({
  head: () => ({ meta: [{ title: 'Lists · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
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
      <header class="mx-auto flex h-18 max-w-3xl items-center justify-between px-5 md:px-8">
        <Wordmark />
        <Link to="/app" class="text-sm font-medium text-muted hover:text-ink">
          Library
        </Link>
      </header>
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
          <button
            type="submit"
            disabled={!name().trim()}
            class="rounded-full bg-accent px-5 font-semibold text-on-accent disabled:opacity-40"
          >
            Create
          </button>
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
          <ul class="mt-8 divide-y divide-line">
            <For each={lists()}>
              {(list) => (
                <li class="flex items-center gap-4 py-4">
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
                    onClick={() =>
                      void run(async () => {
                        await deleteList({ data: { id: list.id } })
                        setLists(lists().filter((l) => l.id !== list.id))
                      })
                    }
                  >
                    Delete
                  </button>
                </li>
              )}
            </For>
          </ul>
        </Show>
      </main>
    </div>
  )
}
