import {
  Outlet,
  createFileRoute,
  redirect,
  useNavigate,
} from '@tanstack/solid-router'
import { Show, createEffect, createSignal, on } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { GroupRail } from '../components/groups/GroupRail'
import { NameDialog } from '../components/groups/dialogs'
import { ShellContext, useVisiblePoll } from '../components/groups/shell'
import type { Shell } from '../components/groups/shell'
import {
  createGroup,
  listGroupInvites,
  listGroups,
  loadGroups,
} from '../lib/groups/server'
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
  }

  useVisiblePoll(() => shell.refresh(), 15000)

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
