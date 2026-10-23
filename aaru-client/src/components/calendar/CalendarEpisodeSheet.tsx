import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { badge, episodeCode, longWhen } from '../../lib/calendar/model'
import type { CalendarEntry } from '../../lib/calendar/model'
import { Poster } from '../Poster'
import {
  Badge,
  Button,
  buttonVariants,
  Dialog,
  DialogContent,
  DialogPortal,
} from '~/components/ui'

/** One airing up close (CAL-002): the still, the show, when and where, the synopsis, the tick
 * and the way to the show. A bottom sheet on phones, centred from 40rem. */
export default function CalendarEpisodeSheet(props: {
  entry: CalendarEntry
  pending: boolean
  onToggle: (entry: CalendarEntry) => void
  /** Defaults to true; the parent keeps it mounted with false so its exit plays (WEB-011). */
  open?: boolean
  onClose: () => void
}) {
  const e = () => props.entry
  const art = () => e().stillUrl ?? e().title.backdropUrl
  const label = () => badge(e())
  const aired = () => new Date(e().airsAt) <= new Date()

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
          aria-label={`${e().title.title}, ${episodeCode(e().season, e().number)}`}
          class="block gap-0 p-0 max-w-[34rem] overflow-hidden sm:max-w-[34rem]"
        >
          <div class="relative">
            <Show
              when={art()}
              fallback={
                <div
                  class="aspect-video w-full bg-accent/15"
                  aria-hidden="true"
                />
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
            <Show when={label()}>
              {(text) => (
                <Badge variant="scrim" class="absolute top-3 left-3">
                  {text()}
                </Badge>
              )}
            </Show>
          </div>
          <div class="px-5 pt-4 pb-5">
            <div class="flex items-start gap-4">
              <Poster
                url={e().title.posterUrl}
                kind={e().title.isAnime ? 'anime' : 'show'}
                class="-mt-14 w-20 shrink-0 shadow-lift ring-4 ring-paper"
              />
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold tracking-wide text-muted uppercase">
                  {e().title.title} · {episodeCode(e().season, e().number)}
                </p>
                <h2 class="mt-1 font-display text-2xl leading-tight font-medium">
                  {e().episodeName ?? `Episode ${e().number}`}
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
            <p class="mt-3 text-sm text-muted">
              {aired() ? '' : 'Airs '}
              {longWhen(e())}
              <Show when={e().runtimeMinutes}> · {e().runtimeMinutes} min</Show>
            </p>
            <Show when={e().episodeOverview}>
              <p class="mt-3 max-h-48 overflow-y-auto leading-relaxed">
                {e().episodeOverview}
              </p>
            </Show>
            <div class="mt-5 flex flex-wrap items-center gap-2">
              <Button
                variant={e().watched ? 'default' : 'outline'}
                size="sm"
                aria-pressed={e().watched}
                disabled={props.pending || (!aired() && !e().watched)}
                onClick={() => props.onToggle(e())}
              >
                {e().watched
                  ? 'Watched'
                  : aired()
                    ? 'Mark watched'
                    : 'Not aired yet'}
              </Button>
              <Link
                to="/app/title/$id"
                params={{ id: e().libraryItemId }}
                class={buttonVariants({ variant: 'quiet', size: 'sm' })}
              >
                Open show
              </Link>
            </div>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
