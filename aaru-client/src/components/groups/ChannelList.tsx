import { Link, useNavigate, useParams } from '@tanstack/solid-router'
import { For, Match, Show, Switch, createSignal } from 'solid-js'
import {
  createChannel,
  deleteChannel,
  deleteGroup,
  removeGroupMember,
  setGroupMuted,
  updateChannel,
  updateGroup,
} from '../../lib/groups/server'
import type { Channel } from '../../lib/groups/server'
import { ChannelDialog, ConfirmDialog, NameDialog } from './dialogs'
import { ChannelGlyph } from './ChannelGlyph'
import { Menu, MenuItem, MentionPill, useGroup, useShell } from './shell'

type Dialog =
  | { kind: 'rename' }
  | { kind: 'leave' }
  | { kind: 'delete' }
  | { kind: 'channel'; channel?: Channel }

/**
 * ChannelList (GRP-004): the group's name with its menu, then its channels. `#general` is
 * first; unread channels are bold with a mention count. Owner and admins add and edit channels.
 */
export function ChannelList(props: { class?: string }) {
  const shell = useShell()
  const scope = useGroup()
  const navigate = useNavigate()
  const params = useParams({ strict: false })
  const selected = () => (params() as { channelId?: string }).channelId
  const [menu, setMenu] = createSignal(false)
  const [dialog, setDialog] = createSignal<Dialog | null>(null)

  const group = () => scope.detail().group
  const manages = () => group().role !== 'member'

  async function toggleMuted() {
    setMenu(false)
    try {
      const summary = await setGroupMuted({
        data: { groupId: group().id, muted: !group().muted },
      })
      scope.setDetail((detail) => ({ ...detail, group: summary }))
      shell.notify(
        summary.muted
          ? `Mentions in ${summary.name} send no alerts.`
          : `Mentions in ${summary.name} send alerts again.`,
      )
    } catch (error) {
      shell.notify(
        error instanceof Error ? error.message : 'That setting was not saved.',
      )
    }
  }

  async function afterLeaving() {
    await shell.refresh()
    await navigate({ to: '/app/groups' })
  }

  return (
    <aside
      aria-label={`${group().name} channels`}
      class={`w-full shrink-0 flex-col bg-surface/60 md:w-60 md:border-r md:border-line ${props.class ?? ''}`}
    >
      <div class="relative border-b border-line">
        <button
          type="button"
          aria-haspopup="menu"
          aria-expanded={menu()}
          onClick={() => setMenu(!menu())}
          class="flex h-14 w-full items-center justify-between gap-2 px-4 text-left hover:bg-surface"
        >
          <span class="truncate font-display text-lg font-medium">
            {group().name}
          </span>
          <svg
            viewBox="0 0 20 20"
            class={`size-4 shrink-0 text-muted transition-transform ${menu() ? 'rotate-180' : ''}`}
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M5.2 7.5a.75.75 0 0 1 1.06 0L10 11.2l3.74-3.7a.75.75 0 1 1 1.06 1.06l-4.27 4.24a.75.75 0 0 1-1.06 0L5.2 8.56a.75.75 0 0 1 0-1.06Z" />
          </svg>
        </button>
        <Menu
          open={menu()}
          onClose={() => setMenu(false)}
          class="top-full right-2 left-2 mt-1"
        >
          <MenuItem
            onSelect={() => {
              setMenu(false)
              scope.openInvite()
            }}
          >
            Invite friends
          </MenuItem>
          <Show when={manages()}>
            <MenuItem
              onSelect={() => {
                setMenu(false)
                setDialog({ kind: 'channel' })
              }}
            >
              New channel
            </MenuItem>
            <MenuItem
              onSelect={() => {
                setMenu(false)
                setDialog({ kind: 'rename' })
              }}
            >
              Rename group
            </MenuItem>
          </Show>
          <MenuItem onSelect={() => void toggleMuted()}>
            {group().muted ? 'Unmute mentions' : 'Mute mentions'}
          </MenuItem>
          <div class="my-1 h-px bg-line" />
          <Show
            when={group().role === 'owner'}
            fallback={
              <MenuItem
                danger
                onSelect={() => {
                  setMenu(false)
                  setDialog({ kind: 'leave' })
                }}
              >
                Leave group
              </MenuItem>
            }
          >
            <MenuItem
              danger
              onSelect={() => {
                setMenu(false)
                setDialog({ kind: 'delete' })
              }}
            >
              Delete group
            </MenuItem>
          </Show>
        </Menu>
      </div>

      <div class="flex-1 overflow-y-auto px-2 py-3">
        <div class="flex items-center justify-between px-2 pb-1">
          <h3 class="text-xs font-semibold tracking-wide text-muted uppercase">
            Channels
          </h3>
          <Show when={manages()}>
            <button
              type="button"
              aria-label="New channel"
              title="New channel"
              onClick={() => setDialog({ kind: 'channel' })}
              class="grid size-6 place-items-center rounded-md text-lg leading-none text-muted hover:bg-surface hover:text-ink"
            >
              +
            </button>
          </Show>
        </div>
        <ul class="space-y-0.5">
          <For each={scope.detail().channels}>
            {(channel) => {
              const active = () => selected() === channel.id
              return (
                <li class="group/row relative">
                  <Link
                    to="/app/groups/$groupId/$channelId"
                    params={{ groupId: group().id, channelId: channel.id }}
                    onClick={() => shell.setDrawer(false)}
                    aria-current={active() ? 'page' : undefined}
                    class={`flex min-h-10 items-center gap-2 rounded-lg px-2 md:min-h-8 ${active() ? 'bg-paper text-ink shadow-sm' : channel.unread > 0 ? 'font-semibold text-ink hover:bg-paper/60' : 'text-muted hover:bg-paper/60 hover:text-ink'}`}
                  >
                    <ChannelGlyph channel={channel} />
                    <span class="min-w-0 flex-1 truncate">{channel.name}</span>
                    <Show when={channel.unread > 0 && channel.mentions === 0}>
                      <span class="sr-only">unread</span>
                    </Show>
                    <MentionPill count={channel.mentions} />
                    <Show when={manages()}>
                      <span class="w-5" aria-hidden="true" />
                    </Show>
                  </Link>
                  <Show when={manages()}>
                    <button
                      type="button"
                      aria-label={`Edit #${channel.name}`}
                      title="Edit channel"
                      onClick={() => setDialog({ kind: 'channel', channel })}
                      class="absolute top-1/2 right-1.5 grid size-6 -translate-y-1/2 place-items-center rounded-md text-muted opacity-0 group-hover/row:opacity-100 hover:text-ink focus-visible:opacity-100"
                    >
                      <svg
                        viewBox="0 0 20 20"
                        class="size-3.5"
                        fill="currentColor"
                        aria-hidden="true"
                      >
                        <path d="M11.3 2.6a1.5 1.5 0 0 1 2.1 0l1 1a1.5 1.5 0 0 1 0 2.1l-1.4 1.4-3.1-3.1zM8.9 5l3.1 3.1-6.6 6.6a1 1 0 0 1-.5.27l-2.6.6a.5.5 0 0 1-.6-.6l.6-2.6a1 1 0 0 1 .27-.5z" />
                      </svg>
                    </button>
                  </Show>
                </li>
              )
            }}
          </For>
        </ul>
      </div>

      <Switch>
        <Match when={dialog()?.kind === 'rename'}>
          <NameDialog
            title="Rename group"
            label="Name"
            initial={group().name}
            submit="Save"
            onSubmit={async (name) => {
              scope.setDetail(
                await updateGroup({ data: { groupId: group().id, name } }),
              )
              await shell.refresh()
            }}
            onClose={() => setDialog(null)}
          />
        </Match>
        <Match when={dialog()?.kind === 'leave'}>
          <ConfirmDialog
            title={`Leave ${group().name}?`}
            body="You stop seeing its channels. A member can invite you back."
            confirm="Leave"
            danger
            onConfirm={() =>
              scope.leaving(async () => {
                await removeGroupMember({
                  data: { groupId: group().id, userId: shell.me().userId },
                })
                await afterLeaving()
              })
            }
            onClose={() => setDialog(null)}
          />
        </Match>
        <Match when={dialog()?.kind === 'delete'}>
          <ConfirmDialog
            title={`Delete ${group().name}?`}
            body="Every channel and message goes, for everyone. This cannot be undone. To keep the group without you, make someone else the owner from the member list."
            confirm="Delete group"
            danger
            onConfirm={() =>
              scope.leaving(async () => {
                await deleteGroup({ data: { groupId: group().id } })
                await afterLeaving()
              })
            }
            onClose={() => setDialog(null)}
          />
        </Match>
        <Match
          when={(() => {
            const open = dialog()
            return open?.kind === 'channel' ? open : null
          })()}
        >
          {(open) => (
            <ChannelDialog
              channel={open().channel}
              onSubmit={async ({ kind, name, topic, title }) => {
                const existing = open().channel
                const saved = existing
                  ? await updateChannel({
                      data: {
                        groupId: group().id,
                        channelId: existing.id,
                        name,
                        topic,
                      },
                    })
                  : await createChannel({
                      data: {
                        groupId: group().id,
                        kind,
                        name: name.trim() || undefined,
                        topic: topic.trim() || undefined,
                        title: title?.ref,
                      },
                    })
                await scope.refresh()
                if (!existing)
                  await navigate({
                    to: '/app/groups/$groupId/$channelId',
                    params: { groupId: group().id, channelId: saved.id },
                  })
              }}
              onDelete={
                open().channel && !open().channel?.isDefault
                  ? async () => {
                      const channel = open().channel
                      if (!channel) return
                      await deleteChannel({
                        data: { groupId: group().id, channelId: channel.id },
                      })
                      await scope.refresh()
                      if (selected() === channel.id)
                        await navigate({
                          to: '/app/groups/$groupId/$channelId',
                          params: {
                            groupId: group().id,
                            channelId: group().defaultChannelId,
                          },
                        })
                    }
                  : undefined
              }
              onClose={() => setDialog(null)}
            />
          )}
        </Match>
      </Switch>
    </aside>
  )
}
