import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { kindOf } from '../lib/library/model'
import {
  activityDay,
  activityVerb,
  inviterName,
  monogram,
} from '../lib/social/model'
import { loadActivity } from '../lib/social/server'
import type { ActivityPage } from '../lib/social/server'
import { Poster } from './Poster'
import { Button } from '~/components/ui'

// SOC-003 (minimal): what friends watched and finished in the last two weeks, newest first.
// Only dated ticks and finishes; imports never show. A room you visit, not a feed you are fed:
// no badge, no push.
export function FriendActivity(props: { page: ActivityPage }) {
  const [items, setItems] = createSignal(props.page.items)
  const [next, setNext] = createSignal(props.page.nextBefore)
  const [loading, setLoading] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

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
                <p class="min-w-0 flex-1 text-sm leading-snug">
                  <span class="font-medium">{inviterName(item.user)}</span>{' '}
                  {activityVerb(item)}{' '}
                  <span class="font-medium">{item.title.title}</span>
                  <Show when={item.finished && item.rating}>
                    {(rating) => (
                      <span class="text-muted"> · ★ {rating()}</span>
                    )}
                  </Show>
                  <span class="block text-muted">{activityDay(item.day)}</span>
                </p>
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
