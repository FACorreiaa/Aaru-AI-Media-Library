import { Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import { coverShape } from '../lib/library/model'
import type { MediaKind } from '../lib/library/model'

const glyph: Record<MediaKind, string> = {
  film: 'Film',
  show: 'TV',
  anime: 'Anime',
  book: 'Book',
  album: 'Album',
}

/**
 * A title's art from the catalog URL, with a calm placeholder while it loads or when there is
 * none: a 2:3 poster, or a square cover for an album, at the same width. Among posters (a mixed
 * grid or row) pass `frame`: the square then sits at the foot of a 2:3 slot, so its bottom edge
 * and the title under it line up with the posters beside it. `children` overlay the art itself
 * (a chip, a badge), so they stay on the cover whatever its shape.
 */
export function Poster(props: {
  url?: string
  kind: MediaKind
  class?: string
  frame?: boolean
  children?: JSX.Element
}) {
  const [failed, setFailed] = createSignal(false)
  const square = () => coverShape(props.kind) === 'square'
  const framed = () => square() && !!props.frame
  const art = (extra: string) => (
    <div
      class={`relative overflow-hidden rounded-field bg-surface ${square() ? 'aspect-square' : 'aspect-[2/3]'} ${extra}`}
    >
      <Show
        when={props.url && !failed()}
        fallback={
          <span
            class="absolute inset-0 grid place-items-center text-xs font-medium tracking-wide text-muted/70 uppercase"
            aria-hidden="true"
          >
            {glyph[props.kind]}
          </span>
        }
      >
        <img
          src={props.url}
          alt=""
          loading="lazy"
          decoding="async"
          class="h-full w-full object-cover"
          onError={() => setFailed(true)}
        />
      </Show>
      {props.children}
    </div>
  )
  return (
    <Show when={framed()} fallback={art(props.class ?? '')}>
      <div class={`flex aspect-[2/3] items-end ${props.class ?? ''}`}>
        {art('w-full')}
      </div>
    </Show>
  )
}
