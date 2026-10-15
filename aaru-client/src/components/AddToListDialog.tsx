import { For, Show, createSignal, onMount } from 'solid-js'
import { addToList, createList, getLists } from '../lib/lists/server'
import type { ListSummary } from '../lib/lists/server'

export interface MediaRefInput {
  titleId?: string
  type: 'movie' | 'show' | 'book'
  ids?: Record<string, string>
  title?: string
  year?: number
}

/** Picks lists for one title: click to add; a new list can be made on the spot (APP-006). */
export function AddToListDialog(props: {
  mediaRef: MediaRefInput
  titleName: string
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [lists, setLists] = createSignal<ListSummary[] | null>(null)
  const [added, setAdded] = createSignal<Set<string>>(new Set())
  const [working, setWorking] = createSignal<string | null>(null)
  const [newName, setNewName] = createSignal('')
  const [problem, setProblem] = createSignal<string | null>(null)

  onMount(async () => {
    dialog?.showModal()
    try {
      setLists(await getLists())
    } catch (error) {
      setLists([])
      setProblem(
        error instanceof Error
          ? error.message
          : 'Your lists could not be loaded.',
      )
    }
  })

  async function add(id: string) {
    if (working() || added().has(id)) return
    setWorking(id)
    setProblem(null)
    try {
      await addToList({ data: { id, mediaRef: props.mediaRef } })
      setAdded(new Set([...added(), id]))
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'The title could not be added.',
      )
    } finally {
      setWorking(null)
    }
  }

  async function create(event: SubmitEvent) {
    event.preventDefault()
    const name = newName().trim()
    if (!name) return
    setProblem(null)
    try {
      const list = await createList({ data: { name } })
      setLists([
        {
          id: list.id,
          name: list.name,
          itemCount: list.titles.length,
          createdAt: list.createdAt,
          updatedAt: list.updatedAt,
        },
        ...(lists() ?? []),
      ])
      setNewName('')
      await add(list.id)
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'The list could not be created.',
      )
    }
  }

  return (
    <dialog
      ref={dialog}
      aria-label={`Add ${props.titleName} to a list`}
      class="m-auto w-[min(26rem,calc(100vw-2rem))] rounded-[20px] bg-paper p-0 text-ink shadow-2xl backdrop:bg-black/40"
      onClose={() => props.onClose()}
    >
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 class="line-clamp-1 font-display text-xl font-medium">
          Add “{props.titleName}”
        </h2>
        <button
          type="button"
          class="text-sm font-medium text-muted hover:text-ink"
          onClick={() => dialog?.close()}
        >
          Done
        </button>
      </div>
      <form class="flex gap-2 px-5 pt-4" onSubmit={create}>
        <label for="new-list" class="sr-only">
          New list name
        </label>
        <input
          id="new-list"
          placeholder="New list"
          value={newName()}
          onInput={(e) => setNewName(e.currentTarget.value)}
          class="min-h-10 flex-1 rounded-full border-0 bg-surface px-4 text-sm focus:ring-2 focus:ring-accent"
        />
        <button
          type="submit"
          disabled={!newName().trim()}
          class="rounded-full border border-ink/25 px-4 text-sm font-semibold disabled:opacity-40"
        >
          Create
        </button>
      </form>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="px-5 pt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
      <ul class="max-h-80 overflow-y-auto px-3 py-3">
        <Show when={lists() === null}>
          <li class="px-2 py-4 text-sm text-muted">Loading…</li>
        </Show>
        <Show when={lists()?.length === 0}>
          <li class="px-2 py-4 text-sm text-muted">
            No lists yet. Name one above.
          </li>
        </Show>
        <For each={lists() ?? []}>
          {(list) => (
            <li>
              <button
                type="button"
                class="flex w-full items-center justify-between rounded-[12px] px-3 py-2.5 text-left hover:bg-surface disabled:hover:bg-transparent"
                disabled={added().has(list.id)}
                onClick={() => add(list.id)}
              >
                <span class="font-medium">{list.name}</span>
                <span class="text-sm text-muted">
                  {working() === list.id
                    ? 'Adding…'
                    : added().has(list.id)
                      ? 'Added'
                      : ''}
                </span>
              </button>
            </li>
          )}
        </For>
      </ul>
    </dialog>
  )
}
