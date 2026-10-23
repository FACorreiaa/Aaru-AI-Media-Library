import { createSignal } from 'solid-js'
import { Button, toast } from '~/components/ui'
import { toggleUpvote } from '../../lib/board/model'
import type { UpvoteState } from '../../lib/board/model'
import { setUpvote } from '../../lib/board/server'
import { pop } from '../../lib/motion'

/**
 * Upvote (BOARD-002): ▲ and the count. Applies at once, like a reaction on Lately (SOC-007),
 * and puts the count back with a toast if the server says no. Yours is ringed in accent.
 */
export function UpvoteButton(props: {
  postId: string
  upvotes: number
  upvotedByMe: boolean
}) {
  // Seeded once: after a tap this button, not the list, holds the truth.
  const [state, setState] = createSignal<UpvoteState>({
    upvotes: props.upvotes,
    upvotedByMe: props.upvotedByMe,
  })
  let busy = false
  let mark: HTMLSpanElement | undefined

  async function press() {
    if (busy) return
    busy = true
    const before = state()
    const next = toggleUpvote(before)
    setState(next)
    if (next.upvotedByMe && mark) void pop(mark)
    try {
      await setUpvote({ data: { postId: props.postId, on: next.upvotedByMe } })
    } catch (error) {
      setState(before)
      toast(
        error instanceof Error ? error.message : 'Your upvote was not saved.',
      )
    } finally {
      busy = false
    }
  }

  return (
    <Button
      variant="ghost"
      size="bare"
      aria-pressed={state().upvotedByMe}
      aria-label={`Upvote, ${state().upvotes}`}
      onClick={() => void press()}
      class={`inline-flex min-h-8 items-center gap-1.5 rounded-full px-3 text-xs font-semibold tabular-nums ${
        state().upvotedByMe
          ? 'bg-accent/15 text-ink ring-1 ring-accent hover:text-ink'
          : 'bg-surface text-muted hover:text-ink'
      }`}
    >
      <span
        ref={mark}
        aria-hidden="true"
        class={`inline-block text-[10px] leading-none ${state().upvotedByMe ? 'text-accent' : ''}`}
      >
        ▲
      </span>
      {state().upvotes}
    </Button>
  )
}
