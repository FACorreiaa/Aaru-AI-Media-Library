import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Button, cardClass } from '~/components/ui'
import { cn } from '~/lib/utils'
import { weekRange } from '../../lib/achievements/model'
import type { Leaderboard as Board } from '../../lib/achievements/model'
import { inviterName, monogram } from '../../lib/social/model'
import { Monogram } from '../groups/Monogram'

// GAM-005 on Friends, "This week" (DESIGN.md §17 "The board"): you and the friends who joined,
// ranked by this week's points, your row marked. Before you join, one card explains it. No
// global board and no all-time board.
export function Leaderboard(props: {
  board: Board
  /** Joins the board; the caller reloads it. */
  onJoin: () => Promise<void>
}) {
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function join() {
    setBusy(true)
    setProblem(null)
    try {
      await props.onJoin()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'You did not join the board.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <section aria-labelledby="friends-board">
      <div class="flex items-baseline justify-between gap-4">
        <h2 id="friends-board" class="eyebrow">
          This week
        </h2>
        <span class="text-xs text-muted">
          {weekRange(props.board.from, props.board.until)}
        </span>
      </div>
      <Show
        when={props.board.optedIn}
        fallback={
          <div class={cn(cardClass, 'mt-3 p-5')}>
            <p class="font-display text-xl font-medium">
              A quiet board for friends
            </p>
            <p class="mt-1 text-sm text-muted">
              See who watched and read the most this week, among friends who
              joined too. Only friends ever see it, and it starts again every
              Monday.
            </p>
            <Button
              size="sm"
              class="mt-4"
              disabled={busy()}
              onClick={() => void join()}
            >
              Join the board
            </Button>
            <Show when={problem()}>
              {(message) => (
                <p role="alert" class="mt-3 text-sm text-danger">
                  {message()}
                </p>
              )}
            </Show>
          </div>
        }
      >
        <ol class={cn(cardClass, 'mt-3 divide-y divide-line px-2 py-1')}>
          <For each={props.board.entries}>
            {(entry) => (
              <li
                class="flex items-center gap-3 rounded-panel px-3 py-2.5"
                classList={{ 'bg-surface': entry.you }}
                aria-current={entry.you ? 'true' : undefined}
              >
                <span class="w-5 text-right text-sm text-muted tabular-nums">
                  {entry.rank}
                </span>
                <Monogram
                  text={monogram(entry.user)}
                  avatarUrl={entry.user.avatarUrl}
                  class="size-8 bg-medallion/60 font-normal"
                />
                <span class="min-w-0 flex-1 truncate text-sm font-medium">
                  <Show when={!entry.you} fallback={<span>You</span>}>
                    <Link
                      to="/app/friends/$handle"
                      params={{ handle: entry.user.handle }}
                      class="hover:text-accent"
                    >
                      {inviterName(entry.user)}
                    </Link>
                  </Show>
                </span>
                <span class="text-sm font-semibold tabular-nums">
                  {entry.points.toLocaleString('en-US')}
                  <span class="sr-only"> points</span>
                </span>
              </li>
            )}
          </For>
        </ol>
        <Show when={props.board.entries.length <= 1}>
          <p class="mt-2 text-xs text-muted">
            Only you so far. Friends appear once they join from their Friends
            page.
          </p>
        </Show>
      </Show>
    </section>
  )
}
