import { For, Index, Show, createSignal, onMount } from 'solid-js'
import { Button, Skeleton } from '~/components/ui'
import { cn } from '~/lib/utils'
import type { SportEntity } from '../../lib/sports/model'
import { getSportSuggestions } from '../../lib/sports/server'
import { SportBadge } from './SportBadge'

/** First run, before anything is followed: the owner's picks as tappable badges. The same
 * list for everyone, never a recommendation. */
export function SuggestedPicks(props: {
  isFollowing: (entity: SportEntity) => boolean
  isBusy: (entity: SportEntity) => boolean
  onToggle: (entity: SportEntity) => void
  onSearch: () => void
}) {
  const [picks, setPicks] = createSignal<SportEntity[] | null>(null)
  const [failed, setFailed] = createSignal(false)

  onMount(async () => {
    try {
      const found = await getSportSuggestions()
      setPicks(found.items)
    } catch {
      setFailed(true)
    }
  })

  return (
    <section aria-labelledby="sport-picks" class="max-w-3xl">
      <h2 id="sport-picks" class="font-display text-xl font-medium">
        Follow a league, a team or a player
      </h2>
      <p class="mt-1 text-sm text-muted">
        Their live scores, next games and results show here. Start with one of
        these, or search.
      </p>
      <Show
        when={picks()}
        fallback={
          <Show when={!failed()}>
            <div class="mt-5 flex flex-wrap gap-2" aria-hidden="true">
              <Index each={[0, 1, 2, 3, 4, 5]}>
                {() => <Skeleton class="h-11 w-36 rounded-full" />}
              </Index>
            </div>
          </Show>
        }
      >
        {(items) => (
          <ul class="mt-5 flex flex-wrap gap-2">
            <For each={items()}>
              {(entity) => (
                <li>
                  <Button
                    variant="quiet"
                    aria-pressed={props.isFollowing(entity)}
                    disabled={props.isBusy(entity)}
                    onClick={() => props.onToggle(entity)}
                    class={cn(
                      'min-h-11 gap-2 rounded-full py-1.5 pr-4 pl-2',
                      props.isFollowing(entity) &&
                        'border-transparent bg-ink text-paper hover:bg-ink/90',
                    )}
                  >
                    <SportBadge
                      url={entity.badgeUrl}
                      name={entity.name}
                      class="size-7"
                    />
                    {entity.name}
                  </Button>
                </li>
              )}
            </For>
          </ul>
        )}
      </Show>
      <Button variant="outline" class="mt-5" onClick={() => props.onSearch()}>
        Search leagues, teams and players
      </Button>
    </section>
  )
}
