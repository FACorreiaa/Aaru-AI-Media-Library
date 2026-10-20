import { Link, createFileRoute } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { MemberList, MemberSheet } from '../components/groups/MemberList'
import { MessageList, PAGE_SIZE } from '../components/groups/MessageList'
import { useGroup } from '../components/groups/shell'
import { listMessages } from '../lib/groups/server'

// GRP-005 on the web: one channel, with the member list folding away on the right.
export const Route = createFileRoute('/app_/groups/$groupId/$channelId')({
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
})

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
        {(id) => (
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
            <MessageList
              channel={channel(id)!}
              initial={loaded().messages ?? []}
              onOpenMembers={toggleMembers}
            />
          </Show>
        )}
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
