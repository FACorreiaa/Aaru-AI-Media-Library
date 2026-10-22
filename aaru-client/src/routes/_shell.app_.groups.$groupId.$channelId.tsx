import { Link, createFileRoute } from '@tanstack/solid-router'
import { Match, Show, Switch, createMemo } from 'solid-js'
import { LoadError } from '../components/groups/LoadError'
import { MemberList } from '../components/groups/MemberList'
import { MessageList } from '../components/groups/MessageList'
import { ShelfView } from '../components/groups/ShelfView'
import { TitleCard } from '../components/groups/TitleCard'
import { WatchPanel } from '../components/groups/WatchPanel'
import { useGroup } from '../components/groups/shell'
import { PAGE_SIZE } from '../lib/groups/model'
import { openChannel } from '../lib/groups/server'
import type { GroupDetail } from '../lib/groups/server'

// GRP-005 on the web: one channel, with the member list folding away on the right. A `shelf`
// channel (a List in the UI) is a list rather than a conversation; title and watch channels put
// their card above the chat. "Gone" is a 404 only; any other failure offers Try again (UX-064).
export const Route = createFileRoute('/_shell/app_/groups/$groupId/$channelId')(
  {
    loader: async ({ params }) => ({
      channelId: params.channelId,
      messages: await openChannel({
        data: {
          groupId: params.groupId,
          channelId: params.channelId,
          limit: PAGE_SIZE,
        },
      }),
    }),
    // UX-013: "#general · Book club · Aaru".
    head: ({ matches, params }) => {
      const group = (
        matches as ReadonlyArray<{ routeId: string; loaderData?: unknown }>
      ).find((m) => m.routeId === '/_shell/app_/groups/$groupId')
        ?.loaderData as GroupDetail | undefined
      const channel = group?.channels.find((c) => c.id === params.channelId)
      return {
        meta: [
          {
            title:
              group && channel
                ? `#${channel.name} · ${group.group.name} · Aaru`
                : 'Groups · Aaru',
          },
        ],
      }
    },
    errorComponent: (props) => (
      <LoadError what="This channel" error={props.error} reset={props.reset} />
    ),
    component: ChannelPage,
  },
)

function ChannelPage() {
  const loaded = Route.useLoaderData()
  const scope = useGroup()
  const channel = (id: string) =>
    scope.detail().channels.find((c) => c.id === id)

  const toggleMembers = () => scope.toggleMembers()

  return (
    <>
      <Show when={loaded().channelId} keyed>
        {(id) => {
          // Keyed on the kind alone, so a group refresh never remounts the card or the party.
          const kind = createMemo(() => channel(id)?.kind)
          const top = createMemo(() =>
            kind() === 'title' ? (
              <TitleCard channel={channel(id)!} />
            ) : kind() === 'watch' ? (
              <WatchPanel channel={channel(id)!} />
            ) : undefined,
          )
          return (
            <Show
              when={loaded().messages && channel(id)}
              fallback={
                <div class="grid flex-1 place-items-center p-8 text-center">
                  <div>
                    <p class="font-display text-2xl">This channel is gone.</p>
                    <Link
                      to="/app/groups/$groupId/$channelId"
                      params={{
                        groupId: scope.detail().group.id,
                        channelId: scope.detail().group.defaultChannelId,
                      }}
                      class="mt-4 inline-flex min-h-11 items-center text-accent underline"
                    >
                      Go to #general
                    </Link>
                  </div>
                </div>
              }
            >
              <Switch
                fallback={
                  <MessageList
                    channel={channel(id)!}
                    initial={loaded().messages ?? []}
                    onOpenMembers={toggleMembers}
                    top={top()}
                  />
                }
              >
                <Match when={kind() === 'shelf'}>
                  <ShelfView
                    channel={channel(id)!}
                    onOpenMembers={toggleMembers}
                  />
                </Match>
              </Switch>
            </Show>
          )
        }}
      </Show>
      <Show when={scope.membersOpen()}>
        <aside
          aria-label="Members"
          class="hidden w-60 shrink-0 overflow-y-auto border-l border-line bg-surface/40 2xl:block"
        >
          <MemberList />
        </aside>
      </Show>
    </>
  )
}
