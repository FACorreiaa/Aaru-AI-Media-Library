import { useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { createChannel, getGroup, listGroups } from '../../lib/groups/server'
import type { Channel, GroupSummary } from '../../lib/groups/server'
import type { MediaType } from '../../lib/media'

/** Each group's channel for this title, once looked up: a channel, none, or not known yet. */
type Found = Record<string, Channel | null | undefined>

/**
 * "Discuss in a group…" on a Title page (GRP-007, UX-083): every group I am in. "Open" where
 * the title already has a channel; where it has none, owners and admins can "Start" one and a
 * member is told who can. Hidden when I am in no group.
 */
export function DiscussButton(props: {
  titleId: string
  type: MediaType
  name: string
}) {
  const navigate = useNavigate()
  const [groups, setGroups] = createSignal<GroupSummary[]>([])
  const [found, setFound] = createSignal<Found>({})
  const [open, setOpen] = createSignal(false)
  const [busy, setBusy] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  onMount(async () => {
    try {
      setGroups(await listGroups())
    } catch {
      // Without groups the button simply stays hidden.
    }
  })

  // Looked up when the dialog opens: which groups already talk about this title.
  async function lookUp() {
    await Promise.all(
      groups().map(async (group) => {
        try {
          const detail = await getGroup({ data: { groupId: group.id } })
          const channel =
            detail.channels.find(
              (c) => c.kind === 'title' && c.title?.id === props.titleId,
            ) ?? null
          setFound((all) => ({ ...all, [group.id]: channel }))
        } catch {
          setFound((all) => ({ ...all, [group.id]: null }))
        }
      }),
    )
  }

  async function discuss(group: GroupSummary) {
    setBusy(group.id)
    setProblem(null)
    try {
      const channel =
        found()[group.id] ??
        (await createChannel({
          data: {
            groupId: group.id,
            kind: 'title',
            title: { titleId: props.titleId, type: props.type },
          },
        }))
      setOpen(false)
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
      <Button
        variant="outline"
        size="sm"
        class="mt-4 ml-2"
        onClick={() => {
          setProblem(null)
          setOpen(true)
          void lookUp()
        }}
      >
        Discuss in a group…
      </Button>
      <Dialog open={open()} onOpenChange={setOpen}>
        <DialogPortal>
          <DialogContent
            placement="sheet"
            showCloseButton={false}
            class="block w-[min(28rem,calc(100vw-2rem))] gap-0 p-5 sm:max-w-none"
          >
            <DialogTitle class="text-2xl">Discuss {props.name}</DialogTitle>
            <DialogDescription class="mt-1">
              Opens its channel in the group, or starts one. Spoilers stay
              veiled for whoever is behind.
            </DialogDescription>
            <ul class="mt-4 grid gap-1.5">
              <For each={groups()}>
                {(group) => {
                  const channel = () => found()[group.id]
                  const manages = () => group.role !== 'member'
                  const known = () => channel() !== undefined
                  return (
                    <li class="flex min-h-14 items-center justify-between gap-3 rounded-xl bg-surface px-4 py-2">
                      <span class="min-w-0">
                        <span class="block truncate font-medium">
                          {group.name}
                        </span>
                        <Show when={known() && !channel() && !manages()}>
                          <span class="block text-xs text-muted">
                            No channel yet. Owners and admins start one.
                          </span>
                        </Show>
                      </span>
                      <Show
                        when={known()}
                        fallback={
                          <span class="text-sm text-muted">Looking…</span>
                        }
                      >
                        <Show when={channel() || manages()}>
                          <Button
                            size="xs"
                            variant={channel() ? 'default' : 'outline'}
                            disabled={busy() !== null}
                            aria-label={`${channel() ? 'Open' : 'Start'} in ${group.name}`}
                            onClick={() => void discuss(group)}
                          >
                            {busy() === group.id
                              ? 'Opening…'
                              : channel()
                                ? 'Open'
                                : 'Start'}
                          </Button>
                        </Show>
                      </Show>
                    </li>
                  )
                }}
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
              <Button variant="ghost" size="sm" onClick={() => setOpen(false)}>
                Cancel
              </Button>
            </div>
          </DialogContent>
        </DialogPortal>
      </Dialog>
    </Show>
  )
}
