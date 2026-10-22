import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { kindOf } from '../lib/library/model'
import {
  activityDay,
  activityVerb,
  withReaction,
  inviterName,
  monogram,
} from '../lib/social/model'
import { REACTIONS, loadActivity, reactTo } from '../lib/social/server'
import type { ActivityItem, ActivityPage, Reaction } from '../lib/social/server'
import { Poster } from './Poster'
import { Button } from './ui/button'

// SOC-003 (minimal): what you and your friends watched and finished in the last two weeks,
// newest first. Only dated ticks and finishes; imports never show. A room you visit, not a feed
// you are fed: no badge, no push. Friends' rows take one of six reactions (SOC-007); yours show
// what friends left.
export function FriendActivity(props: { page: ActivityPage; me?: string }) {
  const [items, setItems] = createSignal(props.page.items)
  const [next, setNext] = createSignal(props.page.nextBefore)
  const [loading, setLoading] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [picking, setPicking] = createSignal<string | null>(null)

  const mine = (item: ActivityItem) => item.user.handle === props.me

  /** Applies a reaction at once, and puts the row back if the server says no. */
  async function react(item: ActivityItem, emoji: Reaction) {
    setPicking(null)
    const chosen = item.myReaction === emoji ? null : emoji
    const before = items()
    setItems(
      items().map((row) =>
        row.id === item.id ? withReaction(row, chosen) : row,
      ),
    )
    try {
      await reactTo({ data: { id: item.id, emoji: chosen } })
    } catch (error) {
      setItems(before)
      setProblem(
        error instanceof Error ? error.message : 'That reaction was not saved.',
      )
    }
  }

  async function more() {
    const before = next()
    if (!before || loading()) return
    setLoading(true)
    setProblem(null)
    try {
      const page = await loadActivity({ data: { before } })
      setItems([...items(), ...page.items])
      setNext(page.nextBefore)
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'More could not be loaded.',
      )
    } finally {
      setLoading(false)
    }
  }

  return (
    <section aria-labelledby="activity" class="mt-8">
      <h2 id="activity" class="font-display text-xl font-medium">
        Lately
      </h2>
      <Show
        when={items().length > 0}
        fallback={
          <p class="mt-2 text-sm text-muted">
            Nothing from your friends in the last two weeks.
          </p>
        }
      >
        <ul class="mt-2 divide-y divide-line">
          <For each={items()}>
            {(item) => (
              <li class="flex items-center gap-3 py-3">
                <Link
                  to="/app/friends/$handle"
                  params={{ handle: item.user.handle }}
                  aria-label={inviterName(item.user)}
                  class="grid size-9 shrink-0 place-items-center rounded-full bg-medallion/20 font-display text-sm font-medium"
                >
                  {monogram(item.user)}
                </Link>
                <div class="min-w-0 flex-1 text-sm leading-snug">
                  <p>
                    <span class="font-medium">
                      {mine(item) ? 'You' : inviterName(item.user)}
                    </span>{' '}
                    {activityVerb(item)}{' '}
                    <span class="font-medium">{item.title.title}</span>
                    <Show when={item.finished && item.rating}>
                      {(rating) => (
                        <span class="text-muted"> · ★ {rating()}</span>
                      )}
                    </Show>
                    <span class="block text-muted">
                      {activityDay(item.day)}
                    </span>
                  </p>
                  <Reactions
                    item={item}
                    own={mine(item)}
                    picking={picking() === item.id}
                    onPick={() =>
                      setPicking(picking() === item.id ? null : item.id)
                    }
                    onReact={(emoji) => void react(item, emoji)}
                  />
                </div>
                <Poster
                  url={item.title.posterUrl}
                  kind={kindOf(item.title.type, item.title.isAnime)}
                  radius="thumb"
                  class="w-10 shrink-0"
                />
              </li>
            )}
          </For>
        </ul>
        <Show when={next()}>
          <Button
            variant="quiet"
            size="sm"
            class="mt-3"
            disabled={loading()}
            onClick={() => void more()}
          >
            {loading() ? 'Loading…' : 'Earlier'}
          </Button>
        </Show>
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </section>
  )
}

function Reactions(props: {
  item: ActivityItem
  own: boolean
  picking: boolean
  onPick: () => void
  onReact: (emoji: Reaction) => void
}) {
  return (
    <div class="mt-1 flex flex-wrap items-center gap-1.5">
      <For each={props.item.reactions ?? []}>
        {(reaction) => (
          <button
            type="button"
            disabled={props.own}
            aria-pressed={props.item.myReaction === reaction.emoji}
            aria-label={`${reaction.emoji} ${reaction.count}`}
            class={`inline-flex min-h-8 items-center gap-1 rounded-full px-2.5 text-xs disabled:cursor-default ${
              props.item.myReaction === reaction.emoji
                ? 'bg-accent/15 text-ink ring-1 ring-accent'
                : 'bg-surface'
            }`}
            onClick={() => props.onReact(reaction.emoji as Reaction)}
          >
            <span aria-hidden="true">{reaction.emoji}</span>
            {reaction.count}
          </button>
        )}
      </For>
      <Show when={!props.own}>
        <button
          type="button"
          aria-expanded={props.picking}
          aria-label="React"
          class="inline-flex min-h-8 min-w-8 items-center justify-center rounded-full bg-surface px-2 text-xs text-muted hover:text-ink"
          onClick={() => props.onPick()}
        >
          +
        </button>
        <Show when={props.picking}>
          <span role="group" aria-label="Reactions" class="flex gap-1">
            <For each={REACTIONS}>
              {(emoji) => (
                <button
                  type="button"
                  aria-label={emoji}
                  class="grid size-8 place-items-center rounded-full text-base hover:bg-surface motion-safe:transition-transform motion-safe:active:scale-90"
                  onClick={() => props.onReact(emoji)}
                >
                  {emoji}
                </button>
              )}
            </For>
          </span>
        </Show>
      </Show>
    </div>
  )
}
