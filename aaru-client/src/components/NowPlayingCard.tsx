import { Link } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import {
  episodeLine,
  eyebrow,
  progress,
  timeLabel,
} from '../lib/nowplaying/model'
import type { NowPlaying } from '../lib/nowplaying/model'
import { Art } from './HomeRows'
import { Button, buttonVariants } from '~/components/ui'

// VIEWS.md `NowPlayingCard` (DESIGN.md §15, SCR-008): what Stremio or the browser extension
// is playing now, across the top of the Field. Art, the episode, a bar and "17m left", which a
// tap flips to "Ends at 10:12 PM". Values refresh with the poll and a half-minute clock;
// nothing animates (Mindspace).
export function NowPlayingCard(props: {
  playing: NowPlaying
  now: Date
  busy: boolean
  onWatched?: () => void
  timeZone?: string
}) {
  const [showEnd, setShowEnd] = createSignal(false)
  const title = () => props.playing.title
  const itemId = () => props.playing.libraryItemId
  const fraction = () => progress(props.playing, props.now)
  const time = () =>
    timeLabel(props.playing, props.now, showEnd(), undefined, props.timeZone)
  const episode = () => episodeLine(props.playing)

  return (
    <section class="mt-8" aria-labelledby="now-playing">
      <article class="edge-lit overflow-hidden rounded-card bg-surface md:grid md:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
        <div class="relative aspect-[21/9] md:aspect-auto md:min-h-48">
          <span class="absolute inset-0">
            <Art
              sources={[title().backdropUrl, title().posterUrl]}
              title={title().title}
            />
          </span>
          <span class="veil absolute inset-x-0 bottom-0 h-1/3 md:hidden" />
        </div>
        <div class="flex min-w-0 flex-col p-5 md:p-6">
          <h2 id="now-playing" class="eyebrow">
            {eyebrow(props.playing)}
          </h2>
          <h3 class="mt-2 line-clamp-2 font-display text-3xl leading-tight font-medium text-balance">
            <Show when={itemId()} fallback={title().title}>
              {(id) => (
                <Link
                  to="/app/title/$id"
                  params={{ id: id() }}
                  class="hover:text-accent"
                >
                  {title().title}
                </Link>
              )}
            </Show>
          </h3>
          <Show when={episode()}>
            {(line) => (
              <p class="mt-1 text-sm font-medium tabular-nums">{line()}</p>
            )}
          </Show>

          <Show when={fraction() !== null}>
            <div class="mt-4 flex items-center gap-3">
              <div
                class="h-1.5 flex-1 overflow-hidden rounded-full bg-line"
                role="progressbar"
                aria-label="Watched so far"
                aria-valuemin="0"
                aria-valuemax="100"
                aria-valuenow={Math.round((fraction() ?? 0) * 100)}
              >
                <div
                  class="h-full rounded-full bg-gold"
                  style={{ width: `${(fraction() ?? 0) * 100}%` }}
                />
              </div>
              <Button
                variant="ghost"
                size="bare"
                class="shrink-0 font-normal tabular-nums"
                disabled={props.playing.state === 'paused'}
                onClick={() => setShowEnd((on) => !on)}
                aria-label={showEnd() ? 'Show time left' : 'Show when it ends'}
              >
                {time()}
              </Button>
            </div>
          </Show>

          <Show when={itemId()}>
            {(id) => (
              <div class="mt-auto flex flex-wrap gap-2 pt-5">
                <Show when={props.onWatched && props.playing.episode}>
                  <Button
                    variant="default"
                    disabled={props.busy}
                    onClick={() => props.onWatched?.()}
                    aria-label={`Mark ${title().title} ${episode() ?? ''} watched`}
                  >
                    Mark watched
                  </Button>
                </Show>
                <Link
                  to="/app/title/$id"
                  params={{ id: id() }}
                  class={buttonVariants({ variant: 'outline' })}
                >
                  Open
                </Link>
              </div>
            )}
          </Show>
        </div>
      </article>
    </section>
  )
}
