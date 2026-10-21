import {
  Outlet,
  createFileRoute,
  isRedirect,
  redirect,
  useNavigate,
  useParams,
} from '@tanstack/solid-router'
import { Show, createEffect, createSignal, on } from 'solid-js'
import { ChannelList } from '../components/groups/ChannelList'
import { InviteDialog } from '../components/groups/dialogs'
import {
  GroupContext,
  debounced,
  useShell,
  useVisiblePoll,
} from '../components/groups/shell'
import type { GroupScope } from '../components/groups/shell'
import { getGroup } from '../lib/groups/server'
import { connectionState, useRealtime } from '../lib/realtime/socket'

// GRP-004 on the web: one group, its channel list beside whatever channel is open. A group you
// are not in (or that is gone) sends you back to groups home, like a 404.
export const Route = createFileRoute('/_shell/app_/groups/$groupId')({
  loader: async ({ params }) => {
    try {
      return await getGroup({ data: { groupId: params.groupId } })
    } catch (error) {
      if (isRedirect(error)) throw error
      throw redirect({ to: '/app/groups' })
    }
  },
  component: GroupLayout,
})

function GroupLayout() {
  const loaded = Route.useLoaderData()
  const shell = useShell()
  const params = useParams({ strict: false })
  const [detail, setDetail] = createSignal(loaded())
  const [inviting, setInviting] = createSignal(false)
  const [membersOpen, setMembersOpen] = createSignal(true)
  let leavingNow = false
  const channelOpen = () =>
    Boolean((params() as { channelId?: string }).channelId)

  createEffect(on(loaded, (next) => setDetail(next), { defer: true }))

  const scope: GroupScope = {
    detail,
    setDetail,
    refresh: async () => {
      setDetail(await getGroup({ data: { groupId: detail().group.id } }))
    },
    openInvite: () => setInviting(true),
    membersOpen,
    setMembersOpen,
    leaving: async (action) => {
      leavingNow = true
      try {
        await action()
      } catch (error) {
        leavingNow = false
        throw error
      }
    },
  }

  // GRP-006: this group's structure refetches on change; a message in another channel bumps
  // that channel's counts. Removed from the group: back to groups home, said calmly.
  const navigate = useNavigate()
  const refreshSoon = debounced(() => scope.refresh().catch(() => {}), 400)
  useRealtime((event) => {
    if (event.type === 'ready') return refreshSoon()
    if (event.groupId !== detail().group.id) return
    switch (event.type) {
      case 'group.removed':
        if (leavingNow) return
        shell.notify(`You're no longer in ${detail().group.name}.`)
        void navigate({ to: '/app/groups' })
        return
      case 'group.updated':
      case 'read':
      case 'message.deleted':
        refreshSoon()
        return
      case 'message.created': {
        const message = event.message
        const meId = shell.me().userId
        const openChannel = (params() as { channelId?: string }).channelId
        if (
          !message ||
          message.author?.userId === meId ||
          event.channelId === openChannel
        )
          return
        const mentioned = message.mentions.includes(meId)
        setDetail((current) => ({
          ...current,
          channels: current.channels.map((c) =>
            c.id === event.channelId
              ? {
                  ...c,
                  unread: c.unread + 1,
                  mentions: c.mentions + (mentioned ? 1 : 0),
                }
              : c,
          ),
        }))
        return
      }
      default:
        return
    }
  })
  // Only while the socket is down.
  useVisiblePoll(
    () => scope.refresh(),
    30000,
    () => connectionState() !== 'open',
  )

  // Phone: the channel list is the page until a channel opens. Tablet: it lives in the drawer.
  const listClass = () => {
    const phone = channelOpen() ? 'max-md:hidden' : 'max-md:flex'
    const tablet = shell.drawer()
      ? 'md:max-lg:fixed md:max-lg:inset-y-0 md:max-lg:left-[72px] md:max-lg:z-40 md:max-lg:flex md:max-lg:bg-surface group-drawer'
      : 'md:max-lg:hidden'
    return `${phone} ${tablet} lg:flex`
  }

  return (
    <GroupContext.Provider value={scope}>
      <ChannelList class={listClass()} />
      <Outlet />
      <Show when={inviting()}>
        <InviteDialog
          detail={detail()}
          onInvited={() => scope.refresh()}
          onClose={() => setInviting(false)}
        />
      </Show>
    </GroupContext.Provider>
  )
}
