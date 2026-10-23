import { For, Show, createEffect, createSignal, on } from 'solid-js'
import { addToList, createList, getLists } from '../lib/lists/server'
import type { ListSummary } from '../lib/lists/server'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import type { MediaType } from '../lib/media'

export interface MediaRefInput {
  titleId?: string
  type: MediaType
  ids?: Record<string, string>
  title?: string
  year?: number
}

/** Picks lists for one title: click to add; a new list can be made on the spot (APP-006).
 * `open` (default true) lets a caller keep it mounted, so closing plays the exit (WEB-011); the
 * lists reload each time it opens. */
export function AddToListDialog(props: {
  mediaRef: MediaRefInput
  titleName: string
  open?: boolean
  onClose: () => void
}) {
  const open = () => props.open ?? true
  const [lists, setLists] = createSignal<ListSummary[] | null>(null)
  const [added, setAdded] = createSignal<Set<string>>(new Set())
  const [working, setWorking] = createSignal<string | null>(null)
  const [newName, setNewName] = createSignal('')
  const [problem, setProblem] = createSignal<string | null>(null)

  createEffect(
    on(open, async (isOpen) => {
      if (!isOpen) return
      setProblem(null)
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
    }),
  )

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
    <Dialog
      open={open()}
      onOpenChange={(next) => {
        if (!next) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          showCloseButton={false}
          aria-label={`Add ${props.titleName} to a list`}
          class="block gap-0 p-0 w-[min(26rem,calc(100vw-2rem))]"
        >
          <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
            <h2 class="line-clamp-1 font-display text-xl font-medium">
              Add “{props.titleName}”
            </h2>
            <Button
              variant="ghost"
              size="bare"
              class="text-sm"
              onClick={() => props.onClose()}
            >
              Done
            </Button>
          </div>
          <form class="flex gap-2 px-5 pt-4" onSubmit={create}>
            <TextField class="flex-1" value={newName()} onChange={setNewName}>
              <TextFieldLabel class="sr-only">New list name</TextFieldLabel>
              <TextFieldInput
                placeholder="New list"
                class="min-h-10 rounded-full border-0 bg-surface px-4 text-sm"
              />
            </TextField>
            <Button
              variant="outline"
              type="submit"
              size="sm"
              disabled={!newName().trim()}
            >
              Create
            </Button>
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
                  <Button
                    variant="soft"
                    size="bare"
                    class="w-full justify-between rounded-panel px-3 py-2.5 text-left text-base disabled:opacity-100 disabled:hover:bg-transparent"
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
                  </Button>
                </li>
              )}
            </For>
          </ul>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
