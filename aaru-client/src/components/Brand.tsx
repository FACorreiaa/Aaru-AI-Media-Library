import { createLink } from '@tanstack/solid-router'
import { splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import wordmark from '../assets/brand/wordmark.svg'
import mascot from '../assets/brand/mascot.webp'
import mascot2x from '../assets/brand/mascot@2x.webp'

/** A router link that never claims to be the current page: on /app the wordmark is a way home,
 * and only the Home row of the nav carries `aria-current`. */
const HomeLink = createLink(
  (props: JSX.AnchorHTMLAttributes<HTMLAnchorElement>) => {
    const [, rest] = splitProps(props, ['aria-current'])
    return <a {...rest} />
  },
)

/** Links home: the landing page by default, `/app` on signed-in pages. */
export function Wordmark(props: { class?: string; to?: '/' | '/app' }) {
  return (
    <HomeLink to={props.to ?? '/'} class="block" aria-label="Aaru">
      {/* The poster's wordmark as a mask over the text colour, so it is ink in light and dark
          (DESIGN.md "Brand"). The link carries the name. */}
      <span
        aria-hidden="true"
        class={`block aspect-[3094/777] bg-current text-ink ${props.class ?? 'h-8 w-auto md:h-9'}`}
        style={{
          'mask-image': `url(${wordmark})`,
          'mask-size': 'contain',
          'mask-repeat': 'no-repeat',
          '-webkit-mask-image': `url(${wordmark})`,
          '-webkit-mask-size': 'contain',
          '-webkit-mask-repeat': 'no-repeat',
        }}
      />
    </HomeLink>
  )
}

/** The mascot on a paper disc, so its painted edge reads the same in light and dark. */
export function MascotMedallion(props: { class?: string; priority?: boolean }) {
  return (
    <div
      class={`relative aspect-square overflow-hidden rounded-full bg-medallion ${props.class ?? ''}`}
    >
      <img
        src={mascot}
        srcset={`${mascot} 1x, ${mascot2x} 2x`}
        alt="Aaru's mascot, a small teal bird carrying a stack of books and a film reel"
        width="720"
        height="794"
        fetchpriority={props.priority ? 'high' : 'auto'}
        class="absolute inset-0 h-full w-full translate-y-[3%] object-contain"
      />
    </div>
  )
}
