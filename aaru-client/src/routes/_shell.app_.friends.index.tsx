import { createFileRoute, useNavigate } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { BoardView } from '../components/board/BoardView'
import { FriendActivity } from '../components/FriendActivity'
import { RecommendationInbox } from '../components/Recommendations'
import { Segmented } from '../components/Segmented'
import { Leaderboard } from '../components/achievements/Leaderboard'
import { YouCard } from '../components/achievements/YouCard'
import { FriendsSection } from '../components/settings/FriendsSection'
import { getLeaderboard } from '../lib/achievements/server'
import { optionalEnum, optionalString } from '../lib/search-params'
import { loadFriendsPage, saveSocialSettings } from '../lib/social/server'

type FriendsView = 'board' | 'lately'

const VIEWS = [
  { value: 'board', label: 'Board' },
  { value: 'lately', label: 'Lately' },
] as const

// BOARD-002: Friends opens on the Board, posts by you and your friends; Lately is its second
// view (owner, 2026-10-23). Lately is SOC-002 / SOC-003 as before: your friends' last two weeks,
// then invites, requests and friends. A friend's name opens their profile. Your handle and name
// are in Settings → Account; who sees your library is in Settings → Friends & privacy.
// GAM-002/005: the "You" card on top and "This week", the friends board, once you join it.
// `?title=<id>` (a title page's "Write about this") opens the composer with that title.
export const Route = createFileRoute('/_shell/app_/friends/')({
  head: () => ({ meta: [{ title: 'Friends · Aaru' }] }),
  validateSearch: (search): { view?: FriendsView; title?: string } => ({
    view: optionalEnum(search.view, ['board', 'lately']),
    title: optionalString(search.title),
  }),
  loader: () => loadFriendsPage(),
  component: Friends,
})

function Friends() {
  const page = Route.useLoaderData()
  const search = Route.useSearch()
  const navigate = useNavigate({ from: Route.fullPath })
  const [board, setBoard] = createSignal(page().board)
  const view = () => search().view ?? 'board'

  function switchView(next: FriendsView) {
    void navigate({
      search: (prev) => ({
        ...prev,
        view: next === 'board' ? undefined : next,
      }),
      replace: true,
    })
  }

  function forgetTitle() {
    void navigate({
      search: (prev) => ({ ...prev, title: undefined }),
      replace: true,
    })
  }

  async function join() {
    await saveSocialSettings({ data: { leaderboardOptIn: true } })
    setBoard(await getLeaderboard({ data: {} }))
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <div class="mt-4 flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
          <h1 class="font-display text-4xl font-medium tracking-tight">
            Friends
          </h1>
          <Segmented
            label="Friends view"
            options={VIEWS}
            value={view()}
            onChange={switchView}
            itemClass="min-h-9 px-4 text-sm"
          />
        </div>
        {/* Both views stay mounted, so going back to one finds it as it was left: a post
            just shared, older pages, an open request. */}
        <div hidden={view() !== 'board'} class="mt-6">
          <BoardView
            initial={page().posts.data}
            problem={page().posts.problem}
            me={{
              userId: page().posts.data?.me.id ?? '',
              handle: page().handle ?? 'you',
              displayName: page().displayName,
            }}
            friends={page().social.friends}
            initialTitleId={search().title}
            onTitleDone={forgetTitle}
            onShowLately={() => switchView('lately')}
          />
        </div>
        <div hidden={view() !== 'lately'}>
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
    </div>
  )
}
