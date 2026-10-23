import { Show } from 'solid-js'
import { reviewEffect } from '../../lib/board/model'
import type { SpoilerChoice } from '../../lib/groups/kinds'
import type { MediaType } from '../../lib/media'
import { SpoilerControl } from '../groups/Spoilers'
import { StarRating } from './StarRating'

/**
 * Under a post's title in the composer: the stars, the spoiler mark, and what posting does to
 * your library. Its own module, loaded once a title is on the way: the Board itself never needs
 * the radio group or the popover.
 */
export default function TitleReview(props: {
  title: { title: string; type: MediaType; libraryItemId?: string }
  rating: number | undefined
  onRating: (rating: number | undefined) => void
  spoiler: SpoilerChoice
  onSpoiler: (choice: SpoilerChoice) => void
}) {
  const effect = () => reviewEffect(props.title, props.rating)
  return (
    <>
      <div class="mt-2 flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
        <StarRating value={props.rating} onChange={props.onRating} />
        <SpoilerControl
          value={props.spoiler}
          onChange={props.onSpoiler}
          hint="Friends who haven't watched this far see it veiled. Only you see the mark."
        />
      </div>
      <Show when={effect()}>
        {(line) => (
          <p class="mt-1 text-sm text-muted" aria-live="polite">
            {line()}
          </p>
        )}
      </Show>
    </>
  )
}
