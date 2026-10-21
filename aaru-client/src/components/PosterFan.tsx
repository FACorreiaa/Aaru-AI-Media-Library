import { For } from 'solid-js'
import type { Cover } from '../lib/landing/art'

/**
 * The hero's hand of posters: an arc that opens from the middle, fading into the page.
 * Phones show the middle five, tablets nine, wide screens all of them. Decorative only.
 */
export function PosterFan(props: { covers: Cover[] }) {
  const middle = () => (props.covers.length - 1) / 2
  return (
    <div class="poster-fan" aria-hidden="true">
      <For each={props.covers}>
        {(cover, index) => {
          const t = index() - middle()
          const reach = Math.abs(t)
          const shown =
            reach <= 2
              ? 'block'
              : reach <= 4
                ? 'hidden md:block'
                : 'hidden lg:block'
          return (
            <div
              class={`poster-fan-slot ${shown}`}
              style={{ '--t': t, '--reach': reach, 'z-index': 20 - reach }}
            >
              <img
                src={cover.url}
                alt=""
                width="342"
                height="513"
                loading={reach <= 2 ? 'eager' : 'lazy'}
                decoding="async"
                class="rise poster-fan-cover"
                style={{ '--delay': `${200 + reach * 70}ms` }}
              />
            </div>
          )
        }}
      </For>
    </div>
  )
}
