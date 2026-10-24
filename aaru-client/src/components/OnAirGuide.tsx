import { For, Index, Show, createSignal, onMount } from 'solid-js'
import {
  episodeLine,
  markOnAir,
  showCount,
  streamsLine,
  viewerRegion,
} from '../lib/discover/onAir'
import type { OnAirGuide as Guide } from '../lib/discover/onAir'
import { getDiscoverOnAir } from '../lib/home/server'
import { createDiscoverAdder } from './DiscoverRows'
import { DiscoverCard, Row } from './HomeRows'
import { Alert, Button, Skeleton } from '~/components/ui'

/**
 * DISC-003: the shows airing this week, one row per channel or streamer, busiest first. Each
 * card says the next episode, at its exact time in the viewer's zone when TVmaze knows it,
 * and where else it streams in the viewer's region. Loaded in the browser: the time zone and
 * the region are the viewer's, and the region (from the language) is never stored.
 */
export function OnAirGuide(props: {
  onProblem: (message: string | null) => void
}) {
  const [guide, setGuide] = createSignal<Guide | null>(null)
  const [failed, setFailed] = createSignal<string | null>(null)

  async function load() {
    setFailed(null)
    try {
      setGuide(
        await getDiscoverOnAir({
          data: { region: viewerRegion(navigator.language) },
        }),
      )
    } catch (error) {
      setFailed(
        error instanceof Error ? error.message : 'On air could not be loaded.',
      )
    }
  }
  onMount(() => void load())

  const adder = createDiscoverAdder({
    onAdded: (key, entry) =>
      setGuide((current) => current && markOnAir(current, key, entry.id)),
    onProblem: (message) => props.onProblem(message),
  })

  return (
    <section aria-label="On air">
      <Show when={failed()}>
        {(message) => (
          <Alert
            variant="destructive"
            class="mt-6 flex items-center justify-between gap-3"
          >
            <span>{message()}</span>
            <Button variant="quiet" size="sm" onClick={() => void load()}>
              Try again
            </Button>
          </Alert>
        )}
      </Show>

      <Show
        when={guide()}
        fallback={
          <Show when={!failed()}>
            <div aria-hidden="true">
              <For each={[0, 1, 2]}>
                {() => (
                  <div class="mt-10">
                    <Skeleton class="h-7 w-40 rounded-full" />
                    <div class="mt-4 flex gap-4 overflow-hidden">
                      <For each={[0, 1, 2, 3, 4, 5]}>
                        {() => (
                          <Skeleton class="aspect-[2/3] w-32 shrink-0 rounded-field md:w-36" />
                        )}
                      </For>
                    </div>
                  </div>
                )}
              </For>
            </div>
          </Show>
        }
      >
        {(loaded) => (
          <Show
            when={loaded().channels.length > 0}
            fallback={
              <div class="mt-8 flex flex-col items-center gap-3 rounded-panel bg-surface px-4 py-6 text-center text-sm text-muted">
                <p>
                  The week’s airings aren’t answering right now. Try again in a
                  few minutes.
                </p>
                <Button variant="quiet" size="sm" onClick={() => void load()}>
                  Try again
                </Button>
              </div>
            }
          >
            <p class="mt-6 text-sm text-muted">
              Shows with a new episode this week, by where they air.
            </p>
            {/* Index, not For: an add replaces the show objects, and the rows must update in
 place rather than be redrawn, or each would lose its scroll position. */}
            <Index each={loaded().channels}>
              {(channel) => (
                <Row
                  title={channel().name}
                  note={showCount(channel().shows.length)}
                >
                  <Index each={channel().shows}>
                    {(show) => (
                      <DiscoverCard
                        hit={show().item}
                        rowId="tv_on_air"
                        adding={adder.isAdding(show().item)}
                        onAdd={(status) => void adder.add(show().item, status)}
                        onList={() => adder.openList(show().item)}
                        details={
                          <>
                            <p class="truncate text-xs text-muted tabular-nums">
                              {episodeLine(show().nextEpisode)}
                            </p>
                            <Show when={streamsLine(show())}>
                              {(line) => (
                                <Show
                                  when={show().watchLink}
                                  fallback={
                                    <p class="truncate text-xs text-muted">
                                      {line()}
                                    </p>
                                  }
                                >
                                  {(href) => (
                                    <a
                                      href={href()}
                                      rel="noopener"
                                      target="_blank"
                                      class="block truncate text-xs text-muted hover:text-accent hover:underline"
                                    >
                                      {line()}
                                    </a>
                                  )}
                                </Show>
                              )}
                            </Show>
                          </>
                        }
                      />
                    )}
                  </Index>
                </Row>
              )}
            </Index>
          </Show>
        )}
      </Show>
      <adder.ListDialog />
    </section>
  )
}
