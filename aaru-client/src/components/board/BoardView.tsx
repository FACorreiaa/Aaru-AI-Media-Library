import { For, Match, Show, Switch, createMemo, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import { boardEmpty, hasOlder } from '../../lib/board/model'
import type { BoardPost, BoardSort } from '../../lib/board/model'
import { loadBoard } from '../../lib/board/server'
import { play } from '../../lib/motion'
import type { SocialUser } from '../../lib/social/server'
import { OwlEmpty } from '../Brand'
import { Segmented } from '../Segmented'
import { PostCard } from './PostCard'
import { PostComposer } from './PostComposer'

export type BoardData = Awaited<ReturnType<typeof loadBoard>>

const SORTS = [
  { value: 'recent', label: 'Recent' },
  { value: 'top', label: 'Top this week' },
] as const

/**
 * The Board (BOARD-002): what you and your friends post, newest first or the week's most
 * upvoted. The composer stays on top whatever the Board holds, empty included.
 */
export function BoardView(props: {
  /** The first Recent page, from the route's loader; null when it failed. */
  initial: BoardData | null
  problem?: string
  me: SocialUser
  /** Who `@` suggests in the composer, and whose handles read as mentions. */
  friends: SocialUser[]
  initialTitleId?: string
  onTitleDone?: () => void
  /** Switches Friends to Lately, where Invite lives. */
  onShowLately: () => void
}) {
  let list: HTMLOListElement | undefined
  const [sort, setSort] = createSignal<BoardSort>('recent')
  const [posts, setPosts] = createSignal<BoardPost[]>(
    props.initial?.posts ?? [],
  )
  const [friendCount, setFriendCount] = createSignal(
    props.initial?.friendCount ?? 0,
  )
  const [older, setOlder] = createSignal(
    hasOlder('recent', props.initial?.posts ?? []),
  )
  const [loaded, setLoaded] = createSignal(props.initial !== null)
  const [loading, setLoading] = createSignal<'sort' | 'older' | null>(null)
  const [problem, setProblem] = createSignal<string | null>(
    props.initial ? null : (props.problem ?? 'The Board could not be loaded.'),
  )
  let ticket = 0

  const handles = createMemo(
    () =>
      new Set(
        [
          props.me.handle,
          ...props.friends.map((f) => f.handle),
          ...posts().map((p) => p.author.handle),
        ].map((h) => h.toLowerCase()),
      ),
  )
  const empty = () => (loaded() ? boardEmpty(posts(), friendCount()) : null)

  /** Loads the first page of `next`, or the page before `before` on Recent. */
  async function load(next: BoardSort, before?: string) {
    const mine = ++ticket
    setLoading(before ? 'older' : 'sort')
    setProblem(null)
    try {
      const page = await loadBoard({ data: { sort: next, before } })
      if (mine !== ticket) return
      setPosts(before ? [...posts(), ...page.posts] : page.posts)
      setFriendCount(page.friendCount)
      setOlder(hasOlder(next, page.posts))
      setLoaded(true)
    } catch (error) {
      if (mine !== ticket) return
      setProblem(
        error instanceof Error
          ? error.message
          : 'The Board could not be loaded.',
      )
    } finally {
      if (mine === ticket) setLoading(null)
    }
  }

  function switchSort(next: BoardSort) {
    setSort(next)
    void load(next)
  }

  function showOlder() {
    const last = posts().at(-1)
    if (last && loading() === null) void load('recent', last.id)
  }

  /** A new post goes on top at once, settling in from just above. */
  function posted(post: BoardPost) {
    setPosts([post, ...posts().filter((p) => p.id !== post.id)])
    const first = list?.firstElementChild
    if (first) {
      void play(first, {
        opacity: [0, 1],
        transform: ['translateY(-8px)', 'translateY(0)'],
      })
    }
  }

  return (
    <div class="max-w-2xl">
      <PostComposer
        me={props.me}
        friends={props.friends}
        initialTitleId={props.initialTitleId}
        onTitleDone={props.onTitleDone}
        onPosted={posted}
      />

      <Segmented
        label="Order posts by"
        variant="chip"
        options={SORTS}
        value={sort()}
        onChange={switchSort}
        class="mt-6"
        itemClass="min-h-8 px-3 text-sm"
      />

      <Show when={problem()}>
        {(text) => (
          <p
            role="alert"
            class="mt-4 flex flex-wrap items-center gap-x-3 text-sm text-danger"
          >
            {text()}
            <Button
              variant="link"
              size="bare"
              class="font-medium"
              onClick={() => void load(sort())}
            >
              Try again
            </Button>
          </p>
        )}
      </Show>

      <Switch>
        <Match when={empty() === 'no-friends'}>
          <OwlEmpty
            title="Posts from your friends show here."
            body={
              <>
                Invite someone from{' '}
                <Button
                  variant="link"
                  size="bare"
                  class="align-baseline font-medium"
                  onClick={() => props.onShowLately()}
                >
                  Lately
                </Button>
                .
              </>
            }
          />
        </Match>
        <Match when={empty() === 'quiet'}>
          <p class="py-12 text-center font-display text-lg text-muted">
            Nothing yet. Say what you're watching.
          </p>
        </Match>
      </Switch>

      <ol
        ref={list}
        aria-label="Posts"
        aria-busy={loading() !== null}
        class={`mt-2 divide-y divide-line transition-opacity ${loading() === 'sort' ? 'opacity-60' : ''}`}
      >
        <For each={posts()}>
          {(post) => (
            <li>
              <PostCard
                post={post}
                handles={handles()}
                myHandle={props.me.handle.toLowerCase()}
              />
            </li>
          )}
        </For>
      </ol>

      <Show when={older() && sort() === 'recent'}>
        <Button
          variant="quiet"
          size="sm"
          class="mt-3"
          disabled={loading() !== null}
          onClick={showOlder}
        >
          {loading() === 'older' ? 'Loading…' : 'Show older'}
        </Button>
      </Show>
    </div>
  )
}
