import { Show } from 'solid-js'
import { airLabel, episodeCode, episodeKey, hasAired } from '../lib/title/model'
import type { Episode } from '../lib/title/model'
import { Button, Dialog, DialogContent, DialogPortal } from '~/components/ui'

/** One episode up close: still, synopsis, air date and the same tick as the list. `open`
 * (default true) lets the caller keep it mounted on its last episode, so closing plays the
 * exit (WEB-011). */
export function EpisodeSheet(props: {
  showTitle: string
  episode: Episode
  open?: boolean
  previous?: Episode
  next?: Episode
  watched: Set<string>
  pending: Set<string>
  onToggle: (season: number, number: number) => void
  onSelect: (episode: Episode) => void
  onClose: () => void
}) {
  const key = () => episodeKey(props.episode.season, props.episode.number)
  const isWatched = () => props.watched.has(key())
  const aired = () => hasAired(props.episode)
  const name = () => props.episode.name ?? `Episode ${props.episode.number}`
  const code = () => episodeCode(props.episode.season, props.episode.number)

  return (
    <Dialog
      open={props.open ?? true}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          aria-label={`${props.showTitle}, ${code()}`}
          class="block gap-0 p-0 max-w-[34rem] overflow-hidden sm:max-w-[34rem]"
        >
          <Show
            when={props.episode.stillUrl}
            fallback={
              <div class="aspect-video w-full bg-surface" aria-hidden="true" />
            }
          >
            {(url) => (
              <img
                src={url()}
                alt=""
                class="aspect-video w-full bg-surface object-cover"
                loading="lazy"
              />
            )}
          </Show>
          <div class="px-5 pt-4 pb-5">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <p class="text-xs font-semibold tracking-wide text-muted uppercase">
                  {code()}
                </p>
                <h2 class="mt-1 font-display text-2xl leading-tight font-medium">
                  {name()}
                </h2>
              </div>
              <Button
                variant="ghost"
                size="bare"
                class="text-sm"
                onClick={() => props.onClose()}
              >
                Close
              </Button>
            </div>
            <p class="mt-2 text-sm text-muted">
              {[
                airLabel(props.episode)
                  ? `${aired() ? '' : 'Airs '}${airLabel(props.episode)}`
                  : undefined,
                props.episode.runtimeMinutes
                  ? `${props.episode.runtimeMinutes} min`
                  : undefined,
              ]
                .filter(Boolean)
                .join(' · ')}
            </p>
            <Show when={props.episode.overview}>
              <p class="mt-4 max-h-48 overflow-y-auto leading-relaxed">
                {props.episode.overview}
              </p>
            </Show>
            <div class="mt-5 flex items-center gap-2">
              <Button
                variant={isWatched() ? 'default' : 'outline'}
                size="sm"
                class="font-semibold disabled:opacity-40"
                aria-pressed={isWatched()}
                disabled={
                  (!aired() && !isWatched()) || props.pending.has(key())
                }
                onClick={() =>
                  props.onToggle(props.episode.season, props.episode.number)
                }
              >
                {isWatched()
                  ? 'Watched'
                  : aired()
                    ? 'Mark watched'
                    : 'Not aired yet'}
              </Button>
              <span class="ml-auto flex gap-1">
                <Button
                  variant="outline"
                  size="sm"
                  aria-label="Previous episode"
                  disabled={!props.previous}
                  onClick={() =>
                    props.previous && props.onSelect(props.previous)
                  }
                >
                  ←
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  aria-label="Next episode"
                  disabled={!props.next}
                  onClick={() => props.next && props.onSelect(props.next)}
                >
                  →
                </Button>
              </span>
            </div>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
