import {
  Outlet,
  createFileRoute,
  redirect,
  useNavigate,
  useParams,
} from '@tanstack/solid-router'
import { Show, createEffect, createSignal, on, onCleanup } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
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
import { getSession } from '../lib/session/session'

// GRP-004 on the web: the groups shell. Desktop shows four columns (rail, channels, the
// channel, members); a tablet folds the rail and channels into a drawer; a phone stacks
// groups → channels → chat.
export const Route = createFileRoute('/app_/groups')({
  head: () => ({ meta: [{ title: 'Groups · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
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
  const [notice, setNotice] = createSignal<string | null>(null)
  const params = useParams({ strict: false })
  const open = () => params() as { groupId?: string; channelId?: string }
  let noticeTimer: number | undefined
  onCleanup(() => window.clearTimeout(noticeTimer))

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
      setNotice(text)
      window.clearTimeout(noticeTimer)
      noticeTimer = window.setTimeout(() => setNotice(null), 6000)
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
      <div class="flex h-[100dvh] flex-col">
        <AppHeader class="max-w-none" />
        <div class="relative flex min-h-0 flex-1 border-t border-line">
          <Show when={drawer()}>
            <button
              type="button"
              aria-label="Close"
              tabIndex={-1}
              onClick={() => setDrawer(false)}
              class="fixed inset-0 z-30 hidden bg-black/30 md:max-lg:block"
            />
          </Show>
          <GroupRail
            class={
              drawer()
                ? 'hidden md:max-lg:fixed md:max-lg:inset-y-0 md:max-lg:left-0 md:max-lg:z-40 md:max-lg:flex group-drawer lg:flex'
                : 'hidden lg:flex'
            }
          />
          <Outlet />
        </div>
      </div>
      <Show when={notice()}>
        {(text) => (
          <p
            role="status"
            class="group-pop fixed bottom-6 left-1/2 z-50 max-w-[calc(100vw-2rem)] -translate-x-1/2 rounded-full bg-ink px-4 py-2 text-sm text-paper shadow-lg"
          >
            {text()}
          </p>
        )}
      </Show>
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
