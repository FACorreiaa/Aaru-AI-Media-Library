import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Wordmark } from '../components/Brand'
import { Poster } from '../components/Poster'
import { KINDS, kindOf } from '../lib/library/model'
import { getList, removeFromList, reorderList } from '../lib/lists/server'
import type { ListDetail } from '../lib/lists/server'
import { getSession } from '../lib/session/session'

// APP-006 on the web: one list, in order, with remove and move up/down.
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

  async function move(index: number, by: -1 | 1) {
    const before = detail()
    const titles = [...before.titles]
    const [moved] = titles.splice(index, 1)
    titles.splice(index + by, 0, moved)
    setDetail({ ...before, titles }) // optimistic; the server's order wins
    setProblem(null)
    try {
      setDetail(
        await reorderList({
          data: { id: before.id, titleIds: titles.map((t) => t.id) },
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
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          {detail().name}
        </h1>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
        <Show
          when={detail().titles.length > 0}
          fallback={
            <p class="mt-16 text-center text-muted">
              Nothing on this list. Add titles from search or from a title's
              page.
            </p>
          }
        >
          <ol class="mt-8 divide-y divide-line">
            <For each={detail().titles}>
              {(title, index) => (
                <li class="flex items-center gap-4 py-3">
                  <Poster
                    url={title.posterUrl}
                    kind={kindOf(title.type, title.isAnime)}
                    class="w-11 shrink-0"
                  />
                  <div class="min-w-0 flex-1">
                    <p class="line-clamp-2 font-medium">{title.title}</p>
                    <p class="text-sm text-muted">
                      {[
                        title.year,
                        KINDS.find(
                          (k) => k.kind === kindOf(title.type, title.isAnime),
                        )?.label,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </p>
                  </div>
                  <div class="flex items-center gap-1 text-sm">
                    <button
                      type="button"
                      aria-label={`Move ${title.title} up`}
                      disabled={index() === 0}
                      class="rounded-full px-2 py-1 hover:bg-surface disabled:opacity-30"
                      onClick={() => move(index(), -1)}
                    >
                      ↑
                    </button>
                    <button
                      type="button"
                      aria-label={`Move ${title.title} down`}
                      disabled={index() === detail().titles.length - 1}
                      class="rounded-full px-2 py-1 hover:bg-surface disabled:opacity-30"
                      onClick={() => move(index(), 1)}
                    >
                      ↓
                    </button>
                    <button
                      type="button"
                      class="ml-2 text-muted hover:text-danger"
                      onClick={() => remove(title.id)}
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
    </div>
  )
}
