import { For, Show, createSignal } from 'solid-js'
import type { Cover, KindCard as Kind, TypeTile } from '../lib/landing/art'

// Teal → gold, the brand gradient, in three steps so a stack of type tiles reads as three.
const tileTints = [
  'bg-[linear-gradient(160deg,#13505a_0%,#2f7c7f_100%)]',
  'bg-[linear-gradient(160deg,#2f7c7f_0%,#8fb5a4_100%)]',
  'bg-[linear-gradient(160deg,#8fb5a4_0%,#e8cf9f_100%)]',
]

// Back, middle, front: fanned slightly, front on top, the stack centred in the card.
const placement = {
  poster: ['left-[5%]', 'left-[31%]', 'left-[57%]'],
  square: ['left-[3%]', 'left-[30%]', 'left-[57%]'],
}
const turn = ['-rotate-6 z-0', 'rotate-0 z-10', 'rotate-6 z-20']

function CoverImage(props: { cover: Cover }) {
  const [failed, setFailed] = createSignal(false)
  return (
    <Show
      when={!failed()}
      fallback={
        <span class="absolute inset-0 grid place-items-center p-2 text-center text-xs font-medium text-muted">
          {props.cover.title}
        </span>
      }
    >
      <img
        src={props.cover.url}
        alt=""
        loading="lazy"
        decoding="async"
        class="h-full w-full object-cover"
        onError={() => setFailed(true)}
      />
    </Show>
  )
}

function TypeCover(props: { tile: TypeTile; index: number }) {
  return (
    <span
      class={`absolute inset-0 flex flex-col justify-between p-3 text-[#fbf6ec] ${tileTints[props.index % tileTints.length]}`}
    >
      <span class="text-[10px] font-semibold tracking-[0.14em] uppercase opacity-80">
        {props.tile.caption}
      </span>
      <span class="font-display text-base leading-tight font-medium">
        {props.tile.title}
      </span>
    </span>
  )
}

/** One thing Aaru tracks: three covers in a small fan, the name, one line. */
export function KindCard(props: { kind: Kind }) {
  const width = () => (props.kind.shape === 'square' ? 'w-[40%]' : 'w-[38%]')
  const aspect = () =>
    props.kind.shape === 'square' ? 'aspect-square' : 'aspect-[2/3]'
  return (
    <article class="flex flex-col rounded-[28px] bg-surface p-7">
      <div
        class="relative mx-auto h-44 w-full max-w-[17rem]"
        aria-hidden="true"
      >
        <For each={props.kind.covers}>
          {(cover, index) => (
            <div
              class={`absolute bottom-0 overflow-hidden rounded-[10px] bg-paper shadow-[0_14px_28px_-16px_rgb(15_34_36/0.55)] ring-1 ring-line ${width()} ${aspect()} ${placement[props.kind.shape][index()]} ${turn[index()]}`}
            >
              {'url' in cover ? (
                <CoverImage cover={cover} />
              ) : (
                <TypeCover tile={cover} index={index()} />
              )}
            </div>
          )}
        </For>
      </div>
      <h3 class="mt-8 font-display text-2xl font-medium">{props.kind.name}</h3>
      <p class="mt-2 leading-relaxed text-muted">{props.kind.pitch}</p>
    </article>
  )
}
