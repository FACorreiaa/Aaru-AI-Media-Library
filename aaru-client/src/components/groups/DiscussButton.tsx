import { useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
import { createChannel, getGroup, listGroups } from '../../lib/groups/server'
import type { GroupSummary } from '../../lib/groups/server'
import type { MediaType } from '../../lib/media'

/**
 * "Discuss in a group…" on a Title page (GRP-007): opens this title's channel in a group I
 * manage, making it if the group has none. Hidden when I manage no group.
 */
export function DiscussButton(props: {
  titleId: string
  type: MediaType
  name: string
}) {
  const navigate = useNavigate()
  const [groups, setGroups] = createSignal<GroupSummary[]>([])
  const [open, setOpen] = createSignal(false)
  const [busy, setBusy] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  let dialog: HTMLDialogElement | undefined

  onMount(async () => {
    try {
      setGroups((await listGroups()).filter((g) => g.role !== 'member'))
    } catch {
      // Without groups the button simply stays hidden.
    }
  })

  async function discuss(group: GroupSummary) {
    setBusy(group.id)
    setProblem(null)
    try {
      const detail = await getGroup({ data: { groupId: group.id } })
      const existing = detail.channels.find(
        (c) => c.kind === 'title' && c.title?.id === props.titleId,
      )
      const channel =
        existing ??
        (await createChannel({
          data: {
            groupId: group.id,
            kind: 'title',
            title: { titleId: props.titleId, type: props.type },
          },
        }))
      dialog?.close()
      await navigate({
        to: '/app/groups/$groupId/$channelId',
        params: { groupId: group.id, channelId: channel.id },
      })
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'The channel was not opened.',
      )
    } finally {
      setBusy(null)
    }
  }

  return (
    <Show when={groups().length > 0}>
      <button
        type="button"
        class="mt-4 ml-2 rounded-full border border-ink/25 px-4 py-1.5 text-sm font-semibold hover:bg-surface"
        onClick={() => {
          setOpen(true)
          queueMicrotask(() => dialog?.showModal())
        }}
      >
        Discuss in a group…
      </button>
      <Show when={open()}>
        <dialog
          ref={dialog}
          aria-label="Discuss in a group"
          onClose={() => setOpen(false)}
          class="m-auto w-[min(28rem,calc(100vw-2rem))] rounded-[20px] bg-paper p-0 text-ink shadow-2xl backdrop:bg-black/40"
        >
          <div class="p-5">
            <h2 class="font-display text-2xl font-medium">
              Discuss {props.name}
            </h2>
            <p class="mt-1 text-sm text-muted">
              Opens its channel in the group, or makes one. Spoilers stay veiled
              for whoever is behind.
            </p>
            <ul class="mt-4 grid gap-1.5">
              <For each={groups()}>
                {(group) => (
                  <li>
                    <button
                      type="button"
                      disabled={busy() !== null}
                      onClick={() => void discuss(group)}
                      class="flex w-full items-center justify-between rounded-xl bg-surface px-4 py-3 text-left font-medium hover:bg-surface/70 disabled:opacity-50"
                    >
                      <span class="truncate">{group.name}</span>
                      <span class="text-sm text-muted">
                        {busy() === group.id ? 'Opening…' : '→'}
                      </span>
                    </button>
                  </li>
                )}
              </For>
            </ul>
            <Show when={problem()}>
              {(text) => (
                <p role="alert" class="mt-3 text-sm text-danger">
                  {text()}
                </p>
              )}
            </Show>
            <div class="mt-5 flex justify-end">
              <button
                type="button"
                onClick={() => dialog?.close()}
                class="rounded-full px-4 py-2 text-sm font-medium text-muted hover:text-ink"
              >
                Cancel
              </button>
            </div>
          </div>
        </dialog>
      </Show>
    </Show>
  )
}
