import { createFileRoute, redirect } from '@tanstack/solid-router'
import { AppHeader } from '../components/AppHeader'
import { FriendActivity } from '../components/FriendActivity'
import { RecommendationInbox } from '../components/Recommendations'
import { SocialSection } from '../components/SocialSection'
import { loadFriendsPage } from '../lib/social/server'
import { getSession } from '../lib/session/session'

// SOC-002 / SOC-003 on the web: your friends' last two weeks, then invites, requests and
// friends. A friend's name opens their profile.
export const Route = createFileRoute('/app_/friends/')({
  head: () => ({ meta: [{ title: 'Friends · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: () => loadFriendsPage(),
  component: Friends,
})

function Friends() {
  const page = Route.useLoaderData()
  return (
    <div class="min-h-[100dvh]">
      <AppHeader class="max-w-3xl" />
      <main class="mx-auto max-w-3xl px-5 pb-20 md:px-8">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Friends
        </h1>
        <RecommendationInbox items={page().recommendations} />
        <FriendActivity page={page().activity} me={page().handle} />
        <SocialSection
          handle={page().handle}
          displayName={page().displayName}
          state={page().social}
          onProfileSaved={() => {}}
        />
      </main>
    </div>
  )
}
