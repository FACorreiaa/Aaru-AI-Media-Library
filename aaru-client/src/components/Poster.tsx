import { Show, createSignal } from 'solid-js'
import type { MediaKind } from '../lib/library/model'

const glyph: Record<MediaKind, string> = {
  film: 'Film',
  show: 'TV',
  anime: 'Anime',
  book: 'Book',
}

/** A 2:3 poster from the catalog URL, with a calm placeholder while it loads or when there is none. */
export function Poster(props: {
  url?: string
  kind: MediaKind
  class?: string
}) {
  const [failed, setFailed] = createSignal(false)
  return (
    <div
      class={`relative aspect-[2/3] overflow-hidden rounded-[10px] bg-surface ${props.class ?? ''}`}
      aria-hidden="true"
    >
      <Show
        when={props.url && !failed()}
        fallback={
          <span class="absolute inset-0 grid place-items-center text-xs font-medium tracking-wide text-muted/70 uppercase">
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
    </div>
  )
}
