import { createFileRoute } from '@tanstack/solid-router'
import { FriendActivity } from '../components/FriendActivity'
import { RecommendationInbox } from '../components/Recommendations'
import { FriendsSection } from '../components/settings/FriendsSection'
import { loadFriendsPage } from '../lib/social/server'

// SOC-002 / SOC-003 on the web: your friends' last two weeks, then invites, requests and
// friends. A friend's name opens their profile. Your handle and name are in Settings → Account;
// who sees your library is in Settings → Friends & privacy.
export const Route = createFileRoute('/_shell/app_/friends/')({
  head: () => ({ meta: [{ title: 'Friends · Aaru' }] }),
  loader: () => loadFriendsPage(),
  component: Friends,
})

function Friends() {
  const page = Route.useLoaderData()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Friends
        </h1>
        <RecommendationInbox items={page().recommendations} />
        <FriendActivity page={page().activity} me={page().handle} />
        <div class="mt-10 max-w-3xl">
          <FriendsSection handle={page().handle} state={page().social} />
        </div>
      </div>
    </div>
  )
}
