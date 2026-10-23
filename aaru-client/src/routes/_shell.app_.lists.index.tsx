import { OwlEmpty } from '../components/Brand'
import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import {
  For,
  Show,
  createMemo,
  createSignal,
  onCleanup,
  onMount,
} from 'solid-js'
import {
  Button,
  TextField,
  TextFieldInput,
  TextFieldLabel,
  cardClass,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { createList, deleteList, renameList } from '../lib/lists/server'
import type { ListSummary } from '../lib/lists/server'
import { flip, leave } from '../lib/motion'
import { optionalEnum } from '../lib/search-params'
import { listsQuery } from '../lib/queries'

// APP-006 on the web: every list, with create, rename and delete.
export const Route = createFileRoute('/_shell/app_/lists/')({
  head: () => ({ meta: [{ title: 'Lists · Aaru' }] }),
  // UX-080: Home's "New list" lands here with `?new=1`, on the name field.
  validateSearch: (search): { new?: '1' } => ({
    new: optionalEnum(String(search.new ?? ''), ['1']),
  }),
  loader: ({ context: { queryClient } }) => queryClient.query(listsQuery),
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
  const search = Route.useSearch()
  const navigate = useNavigate({ from: Route.fullPath })
  let grid: HTMLUListElement | undefined
  let nameField: HTMLInputElement | undefined
  onMount(() => {
    if (search().new !== '1') return
    nameField?.focus()
    // Back or a reload does not focus it again.
    void navigate({ search: {}, replace: true })
  })
  /** Focuses a row's rename field once it is on the page. */
  const focusOnMount = (el: HTMLInputElement) =>
    queueMicrotask(() => {
      el.focus()
      el.select()
    })
  // Each row's element, so a delete can play its exit before it leaves the DOM.
  const rowEls = new Map<string, HTMLLIElement>()

  /** After a delete: the row fades out, then the lists below slide up into its place. */
  async function drop(id: string) {
    const el = rowEls.get(id)
    if (el) await leave(el)
    const mutate = () => setLists(lists().filter((l) => l.id !== id))
    if (grid) await flip(grid, mutate)
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
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Lists
        </h1>
        <form
          class="mt-6 flex max-w-xl gap-2"
          onSubmit={(e) => {
            e.preventDefault()
            void run(async () => {
              const created = await createList({ data: { name: name() } })
              setLists([summary(created), ...lists()])
              setName('')
            })
          }}
        >
          <TextField class="flex-1" value={name()} onChange={setName}>
            <TextFieldLabel class="sr-only">New list name</TextFieldLabel>
            <TextFieldInput
              ref={nameField}
              placeholder="Name a new list"
              class="min-h-11 rounded-full border-0 bg-surface px-5 text-base md:text-base"
            />
          </TextField>
          <Button type="submit" variant="default" disabled={!name().trim()}>
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
            <OwlEmpty
              class="mt-8"
              title="No lists yet"
              body="Make one for a theme, a marathon or a book club."
            />
          }
        >
          {/* WEB-006: as many columns as the width holds. */}
          <ul
            ref={grid}
            class="mt-8 grid grid-cols-[repeat(auto-fill,minmax(18rem,1fr))] gap-3"
          >
            <For each={lists()}>
              {(list) => (
                <li
                  ref={(el) => {
                    rowEls.set(list.id, el)
                    onCleanup(() => rowEls.delete(list.id))
                  }}
                  class={cn(cardClass, 'flex items-center gap-3 p-4')}
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
                      <TextField
                        class="flex-1"
                        name="name"
                        defaultValue={list.name}
                      >
                        <TextFieldLabel class="sr-only">
                          List name
                        </TextFieldLabel>
                        <TextFieldInput
                          ref={focusOnMount}
                          class="min-h-10 rounded-full border-0 bg-paper px-4"
                        />
                      </TextField>
                      <Button
                        type="submit"
                        variant="link"
                        size="bare"
                        class="text-sm font-semibold text-accent"
                      >
                        Save
                      </Button>
                    </form>
                  </Show>
                  <Button
                    variant="ghost"
                    size="bare"
                    class="min-h-9 px-1.5 text-sm"
                    onClick={() =>
                      setEditing(editing() === list.id ? null : list.id)
                    }
                  >
                    {editing() === list.id ? 'Cancel' : 'Rename'}
                  </Button>
                  <Button
                    variant="ghost"
                    size="bare"
                    class="min-h-9 px-1.5 text-sm hover:text-danger"
                    onClick={() => setPending(list)}
                  >
                    Delete
                  </Button>
                </li>
              )}
            </For>
          </ul>
        </Show>
        <ConfirmDialog
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
      </div>
    </div>
  )
}
