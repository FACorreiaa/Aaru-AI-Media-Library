import {
  Outlet,
  createFileRoute,
  redirect,
  useNavigate,
  useParams,
} from '@tanstack/solid-router'
import { Show, createEffect, createSignal, on } from 'solid-js'
import { Drawer, DrawerContent, DrawerLabel } from '~/components/ui'
import { ChannelList } from '../components/groups/ChannelList'
import { GroupRail } from '../components/groups/GroupRail'
import { LoadError } from '../components/groups/LoadError'
import { MemberSheet } from '../components/groups/MemberList'
import { InviteDialog } from '../components/groups/dialogs'
import {
  GroupContext,
  debounced,
  useShell,
  useVisiblePoll,
} from '../components/groups/shell'
import type { GroupScope } from '../components/groups/shell'
import { getGroup, openGroup } from '../lib/groups/server'
import { connectionState, useRealtime } from '../lib/realtime/socket'

// GRP-004 on the web: one group, its channel list beside whatever channel is open. A group you
// are not in (or that is gone) sends you back to all groups, like a 404; one that did not load
// says so, with Try again (UX-064).
export const Route = createFileRoute('/_shell/app_/groups/$groupId')({
  loader: async ({ params }) => {
    const detail = await openGroup({ data: { groupId: params.groupId } })
    if (!detail) throw redirect({ to: '/app/groups' })
    return detail
  },
  head: ({ loaderData }) => ({
    meta: [
      {
        title: loaderData
          ? `${loaderData.group.name} · Groups · Aaru`
          : 'Groups · Aaru',
      },
    ],
  }),
  errorComponent: (props) => (
    <LoadError what="This group" error={props.error} reset={props.reset} />
  ),
  component: GroupLayout,
})

/** The member column fits beside the app sidebar, the rail, the channels and the chat. */
const membersFit = () => window.matchMedia('(min-width: 1536px)').matches

function GroupLayout() {
  const loaded = Route.useLoaderData()
  const shell = useShell()
  const params = useParams({ strict: false })
  const [detail, setDetail] = createSignal(loaded())
  const [inviting, setInviting] = createSignal(false)
  const [membersOpen, setMembersOpen] = createSignal(true)
  const [membersSheet, setMembersSheet] = createSignal(false)
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
    openMembers: () => {
      if (membersFit()) setMembersOpen(true)
      else setMembersSheet(true)
    },
    toggleMembers: () => {
      if (membersFit()) setMembersOpen(!membersOpen())
      else setMembersSheet(true)
    },
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

  // Phone: the channel list is the page until a channel opens. Tablet: rail and channels live in
  // the Drawer (WEB-004). From 1024px they sit beside the channel.
  const listClass = () =>
    `${channelOpen() ? 'max-md:hidden' : 'max-md:flex'} md:max-lg:hidden lg:flex`

  return (
    <GroupContext.Provider value={scope}>
      <ChannelList class={listClass()} />
      <Outlet />
      <Drawer
        side="left"
        open={shell.drawer()}
        onOpenChange={(open) => shell.setDrawer(open)}
      >
        <DrawerContent class="w-auto max-w-[calc(100vw-3rem)] flex-row border-line bg-surface p-0 sm:max-w-none">
          <DrawerLabel class="sr-only">Groups and channels</DrawerLabel>
          <GroupRail class="flex" />
          <ChannelList class="flex w-64" />
        </DrawerContent>
      </Drawer>
      <Show when={membersSheet()}>
        <MemberSheet onClose={() => setMembersSheet(false)} />
      </Show>
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
