import { createFileRoute } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { FriendActivity } from '../components/FriendActivity'
import { RecommendationInbox } from '../components/Recommendations'
import { Leaderboard } from '../components/achievements/Leaderboard'
import { YouCard } from '../components/achievements/YouCard'
import { FriendsSection } from '../components/settings/FriendsSection'
import { getLeaderboard } from '../lib/achievements/server'
import { loadFriendsPage, saveSocialSettings } from '../lib/social/server'

// SOC-002 / SOC-003 on the web: your friends' last two weeks, then invites, requests and
// friends. A friend's name opens their profile. Your handle and name are in Settings → Account;
// who sees your library is in Settings → Friends & privacy. GAM-002/005: the "You" card on top
// and "This week", the friends board, once you join it.
export const Route = createFileRoute('/_shell/app_/friends/')({
  head: () => ({ meta: [{ title: 'Friends · Aaru' }] }),
  loader: () => loadFriendsPage(),
  component: Friends,
})

function Friends() {
  const page = Route.useLoaderData()
  const [board, setBoard] = createSignal(page().board)

  async function join() {
    await saveSocialSettings({ data: { leaderboardOptIn: true } })
    setBoard(await getLeaderboard({ data: {} }))
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Friends
        </h1>
        <Show when={page().progress}>
          {(progress) => (
            <div class="mt-6 max-w-3xl">
              <YouCard
                progress={progress()}
                name={page().displayName ?? `@${page().handle ?? 'you'}`}
              />
            </div>
          )}
        </Show>
        <RecommendationInbox items={page().recommendations} />
        <FriendActivity page={page().activity} me={page().handle} />
        <Show when={board()}>
          {(current) => (
            <div class="mt-10 max-w-3xl">
              <Leaderboard board={current()} onJoin={join} />
            </div>
          )}
        </Show>
        <div class="mt-10 max-w-3xl">
          <FriendsSection handle={page().handle} state={page().social} />
        </div>
      </div>
    </div>
  )
}
