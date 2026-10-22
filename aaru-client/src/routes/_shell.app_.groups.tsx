import {
  Outlet,
  createFileRoute,
  useNavigate,
  useParams,
} from '@tanstack/solid-router'
import { Show, createEffect, createSignal, on } from 'solid-js'
import { toast } from '~/components/ui'
import { useAppShell } from '../components/shell/context'
import { GroupRail } from '../components/groups/GroupRail'
import { NameDialog } from '../components/groups/dialogs'
import {
  ShellContext,
  debounced,
  useVisiblePoll,
} from '../components/groups/shell'
import type { Shell } from '../components/groups/shell'
import {
  createGroup,
  listGroupInvites,
  listGroups,
  loadGroups,
} from '../lib/groups/server'
import { connectionState, useRealtime } from '../lib/realtime/socket'

// GRP-004 on the web: the groups shell, inside the app shell. From 1024px (the app sidebar
// beside it) the rail, the channels and the channel; the member column joins at 1536px. A
// tablet folds the rail and channels into a Drawer; a phone stacks groups → channels → chat.
export const Route = createFileRoute('/_shell/app_/groups')({
  head: () => ({ meta: [{ title: 'Groups · Aaru' }] }),
  loader: () => loadGroups(),
  component: GroupsShell,
})

function GroupsShell() {
  const loaded = Route.useLoaderData()
  const navigate = useNavigate()
  const [groups, setGroups] = createSignal(loaded().groups)
  const [invites, setInvites] = createSignal(loaded().invites)
  const [drawer, setDrawer] = createSignal(false)
  const [creating, setCreating] = createSignal(false)
  const params = useParams({ strict: false })
  const open = () => params() as { groupId?: string; channelId?: string }
  // The app sidebar's Groups badge follows the live mention total.
  const appShell = useAppShell()
  createEffect(() =>
    appShell.setMentions(groups().reduce((sum, g) => sum + g.mentions, 0)),
  )

  createEffect(
    on(
      loaded,
      (state) => {
        setGroups(state.groups)
        setInvites(state.invites)
      },
      { defer: true },
    ),
  )

  const shell: Shell = {
    me: () => loaded().me,
    groups,
    setGroups,
    invites,
    setInvites,
    refresh: async () => {
      const [nextGroups, nextInvites] = await Promise.all([
        listGroups(),
        listGroupInvites(),
      ])
      setGroups(nextGroups)
      setInvites(nextInvites)
    },
    drawer,
    setDrawer,
    openCreate: () => setCreating(true),
    notify: (text) => {
      toast(text, { duration: 6000 })
    },
  }

  // GRP-006: the socket says what changed; REST says what is true. Structural changes and
  // reconnects refetch; a new message elsewhere only bumps the rail's counts.
  const refreshSoon = debounced(() => shell.refresh().catch(() => {}), 400)
  useRealtime((event) => {
    switch (event.type) {
      case 'message.created': {
        const message = event.message
        const meId = loaded().me.userId
        if (!message || message.author?.userId === meId) return
        // The open channel marks itself read and refreshes the rail.
        if (
          event.groupId === open().groupId &&
          event.channelId === open().channelId
        )
          return
        const mentioned = message.mentions.includes(meId)
        setGroups((list) =>
          list.map((g) =>
            g.id === event.groupId
              ? {
                  ...g,
                  unread: g.unread + 1,
                  mentions: g.mentions + (mentioned ? 1 : 0),
                }
              : g,
          ),
        )
        return
      }
      case 'ready':
      case 'read':
      case 'message.deleted':
      case 'group.updated':
      case 'group.removed':
      case 'invites.changed':
        refreshSoon()
        return
      default:
        return
    }
  })
  // Only while the socket is down.
  useVisiblePoll(
    () => shell.refresh(),
    30000,
    () => connectionState() !== 'open',
  )

  return (
    <ShellContext.Provider value={shell}>
      <div class="flex h-[calc(100dvh-3.5rem)] flex-col lg:h-[100dvh]">
        <div class="relative flex min-h-0 flex-1">
          <GroupRail class="hidden lg:flex" />
          <Outlet />
        </div>
      </div>
      <Show when={creating()}>
        <NameDialog
          title="New group"
          label="Name"
          hint="A small place to talk with friends. It starts with #general, and only friends you invite can join."
          submit="Create"
          onSubmit={async (name) => {
            const created = await createGroup({ data: { name } })
            await shell.refresh()
            await navigate({
              to: '/app/groups/$groupId/$channelId',
              params: {
                groupId: created.group.id,
                channelId: created.group.defaultChannelId,
              },
            })
          }}
          onClose={() => setCreating(false)}
        />
      </Show>
    </ShellContext.Provider>
  )
}
