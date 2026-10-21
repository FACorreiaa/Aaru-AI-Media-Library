import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { shortCode } from '../lib/calendar/model'
import type { ContinueEntry } from '../lib/home/model'
import { pickEpisode, pickReason } from '../lib/home/tonight'
import type { Tonight, TonightPick } from '../lib/home/tonight'
import { Art } from './HomeRows'
import { Button, buttonVariants } from './ui/button'

// VIEWS.md `TonightStrip`: the Field's focal piece. One thing to watch now, lit and large, and
// one more on a line under it. Composed in the browser (lib/home/tonight.ts); a mark-watched
// here is the same write as Continue watching's check.
export function TonightStrip(props: {
  tonight: Tonight
  busy: boolean
  onWatched: (entry: ContinueEntry) => void
  timeZone?: string
}) {
  const primary = () => props.tonight.primary
  const title = () => primary().entry.title
  const continuing = () => {
    const pick = primary()
    return pick.kind === 'continue' ? pick.entry : null
  }
  return (
    <section class="mt-8" aria-labelledby="tonight">
      <h2 id="tonight" class="eyebrow">
        Tonight
      </h2>
      <article class="edge-lit fringe mt-3 overflow-hidden rounded-card bg-surface md:grid md:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
        <Link
          to="/app/title/$id"
          params={{ id: primary().entry.libraryItemId }}
          tabindex="-1"
          aria-hidden="true"
          class="relative block aspect-video md:aspect-auto md:min-h-72"
        >
          {/* Out of the flow on a wide screen: the text sets the card's height, not the art. */}
          <span class="absolute inset-0">
            <Art
              sources={[title().backdropUrl, title().posterUrl]}
              title={title().title}
            />
          </span>
          <span class="veil absolute inset-x-0 bottom-0 h-1/3 md:hidden" />
        </Link>
        <div class="flex min-w-0 flex-col p-5 md:p-6">
          <h3 class="line-clamp-2 font-display text-3xl leading-tight font-medium text-balance">
            <Link
              to="/app/title/$id"
              params={{ id: primary().entry.libraryItemId }}
              class="hover:text-accent"
            >
              {title().title}
            </Link>
          </h3>
          <p class="mt-2 text-sm font-medium tabular-nums">
            {pickEpisode(primary())}
          </p>
          <p class="mt-0.5 text-sm text-muted tabular-nums">
            {pickReason(primary(), props.timeZone)}
          </p>
          <div class="mt-auto flex flex-wrap gap-2 pt-5">
            <Show when={continuing()}>
              {(entry) => (
                <Button
                  variant="primary"
                  disabled={props.busy}
                  onClick={() => props.onWatched(entry())}
                  aria-label={`Mark ${entry().title.title} ${shortCode(entry().next.season, entry().next.number)} watched`}
                >
                  Mark watched
                </Button>
              )}
            </Show>
            <Link
              to="/app/title/$id"
              params={{ id: primary().entry.libraryItemId }}
              class={buttonVariants({ variant: 'outline' })}
            >
              Open
            </Link>
          </div>
          <Show when={props.tonight.also}>
            {(also) => <AlsoLine pick={also()} timeZone={props.timeZone} />}
          </Show>
        </div>
      </article>
    </section>
  )
}

function AlsoLine(props: { pick: TonightPick; timeZone?: string }) {
  return (
    <div class="mt-5 border-t border-line pt-4">
      <p class="eyebrow">Also tonight</p>
      <Link
        to="/app/title/$id"
        params={{ id: props.pick.entry.libraryItemId }}
        class="mt-1 block truncate text-sm hover:text-accent"
      >
        <span class="font-medium">{props.pick.entry.title.title}</span>
        <span class="text-muted tabular-nums">
          {' · '}
          {[pickEpisode(props.pick), pickReason(props.pick, props.timeZone)]
            .filter(Boolean)
            .join(' · ')}
        </span>
      </Link>
    </div>
  )
}
