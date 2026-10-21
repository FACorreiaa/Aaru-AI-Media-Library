import { Link, createFileRoute } from '@tanstack/solid-router'
import { Match, Show, Switch, createMemo, createSignal } from 'solid-js'
import { MemberList, MemberSheet } from '../components/groups/MemberList'
import { MessageList } from '../components/groups/MessageList'
import { ShelfView } from '../components/groups/ShelfView'
import { TitleCard } from '../components/groups/TitleCard'
import { WatchPanel } from '../components/groups/WatchPanel'
import { useGroup } from '../components/groups/shell'
import { PAGE_SIZE } from '../lib/groups/model'
import { listMessages } from '../lib/groups/server'

// GRP-005 on the web: one channel, with the member list folding away on the right. A shelf is a
// list rather than a conversation; title and watch channels put their card above the chat.
export const Route = createFileRoute('/_shell/app_/groups/$groupId/$channelId')(
  {
    loader: async ({ params }) => ({
      channelId: params.channelId,
      messages: await listMessages({
        data: {
          groupId: params.groupId,
          channelId: params.channelId,
          limit: PAGE_SIZE,
        },
      }).catch(() => null),
    }),
    component: ChannelPage,
  },
)

function ChannelPage() {
  const loaded = Route.useLoaderData()
  const scope = useGroup()
  const [sheet, setSheet] = createSignal(false)
  const channel = (id: string) =>
    scope.detail().channels.find((c) => c.id === id)

  function toggleMembers() {
    if (window.matchMedia('(min-width: 1024px)').matches)
      scope.setMembersOpen(!scope.membersOpen())
    else setSheet(true)
  }

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
                <main class="grid flex-1 place-items-center p-8 text-center">
                  <div>
                    <p class="font-display text-2xl">This channel is gone.</p>
                    <Link
                      to="/app/groups/$groupId/$channelId"
                      params={{
                        groupId: scope.detail().group.id,
                        channelId: scope.detail().group.defaultChannelId,
                      }}
                      class="mt-4 inline-block text-accent underline"
                    >
                      Go to #general
                    </Link>
                  </div>
                </main>
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
          class="hidden w-60 shrink-0 overflow-y-auto border-l border-line bg-surface/40 lg:block"
        >
          <MemberList />
        </aside>
      </Show>
      <Show when={sheet()}>
        <MemberSheet onClose={() => setSheet(false)} />
      </Show>
    </>
  )
}
