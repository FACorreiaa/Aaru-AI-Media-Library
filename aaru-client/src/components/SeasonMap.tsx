import { For } from 'solid-js'
import { cellState, episodeKey } from '../lib/title/model'
import type { CellState, Episode, Season } from '../lib/title/model'
import { cn } from '../lib/cn'
import { pop } from '../lib/motion'
import { cardClass } from './ui/card'

const CELL: Record<CellState, string> = {
  watched: 'bg-accent text-on-accent',
  next: 'bg-paper text-ink ring-2 ring-accent',
  aired: 'bg-paper text-muted hover:text-ink',
  unaired: 'bg-transparent text-muted/60 ring-1 ring-line cursor-not-allowed',
}

const STATE_LABEL: Record<CellState, string> = {
  watched: 'watched',
  next: 'up next',
  aired: 'not watched',
  unaired: 'not aired yet',
}

/** The Title room's season map (DESIGN.md §4): one cell per episode, a tap ticks it. The page
 * owns the watched state and the optimistic write; cells only report taps. */
export function SeasonMap(props: {
  seasons: Season[]
  watched: Set<string>
  pending: Set<string>
  next: Episode | undefined
  onToggle: (season: number, number: number) => void
}) {
  return (
    <div class={cn(cardClass, 'flex flex-col gap-3 p-5')}>
      <For each={props.seasons}>
        {(season) => (
          <div class="flex items-start gap-3">
            <span class="w-8 shrink-0 pt-1 text-xs font-semibold text-muted">
              {season.number === 0 ? 'SP' : `S${season.number}`}
            </span>
            <div
              class="flex flex-wrap gap-1.5"
              role="group"
              aria-label={
                season.number === 0 ? 'Specials' : `Season ${season.number}`
              }
            >
              <For each={season.episodes}>
                {(episode) => {
                  const state = () =>
                    cellState(episode, props.watched, props.next)
                  const key = episodeKey(episode.season, episode.number)
                  return (
                    <button
                      type="button"
                      class={`h-7 min-w-7 rounded-[8px] px-1 text-[11px] font-semibold tabular-nums transition-colors ${CELL[state()]}`}
                      aria-pressed={state() === 'watched'}
                      aria-label={`${season.number === 0 ? 'Special' : `Season ${season.number}`}, episode ${episode.number}${episode.name ? `, ${episode.name}` : ''}, ${STATE_LABEL[state()]}`}
                      title={episode.name ?? `Episode ${episode.number}`}
                      disabled={
                        (state() === 'unaired' && !props.watched.has(key)) ||
                        props.pending.has(key)
                      }
                      onClick={(event) => {
                        // A tick pops once; clearing one does not.
                        if (state() !== 'watched') void pop(event.currentTarget)
                        props.onToggle(episode.season, episode.number)
                      }}
                    >
                      {episode.number}
                    </button>
                  )
                }}
              </For>
            </div>
          </div>
        )}
      </For>
    </div>
  )
}
