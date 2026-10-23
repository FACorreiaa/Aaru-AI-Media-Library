import { createLink } from '@tanstack/solid-router'
import { Show, splitProps } from 'solid-js'
import { Dynamic } from 'solid-js/web'
import type { JSX } from 'solid-js'
import wordmark from '../assets/brand/wordmark.svg'
import mascot from '../assets/brand/mascot.webp'
import mascot2x from '../assets/brand/mascot@2x.webp'
import owlMark from '../assets/brand/owl-mark.webp'

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

/** The owl on the night disc (the poster's sky), so the white owl reads in light and dark.
 * `idle` gives it a slow float and an amber glow behind the disc (`owl-idle`): alive, never
 * working; still under reduced motion. `decorative` hides it where words beside it speak. */
export function MascotMedallion(props: {
  class?: string
  priority?: boolean
  idle?: boolean
  decorative?: boolean
}) {
  return (
    <div
      aria-hidden={props.decorative || undefined}
      class={`relative aspect-square rounded-full ${props.idle ? 'owl-idle' : ''} ${props.class ?? ''}`}
    >
      <div class="absolute inset-0 overflow-hidden rounded-full bg-night">
        <img
          src={mascot}
          srcset={`${mascot} 1x, ${mascot2x} 2x`}
          alt={
            props.decorative
              ? ''
              : "Aaru's mascot, a small white robot owl with glowing amber eyes"
          }
          width="720"
          height="877"
          fetchpriority={props.priority ? 'high' : 'auto'}
          class="absolute inset-0 h-full w-full translate-y-[3%] object-contain"
        />
      </div>
    </div>
  )
}

/** The owl's head on the night disc: Aaru's own mark, for the agent (DESIGN.md "Brand"). It
 * breathes only while Aaru is working and, with `idle`, floats calmly otherwise: never both,
 * and still under reduced motion. */
export function OwlMark(props: {
  class?: string
  breathing?: boolean
  idle?: boolean
}) {
  return (
    <span
      aria-hidden="true"
      class={`relative inline-block shrink-0 rounded-full ${props.breathing ? 'aaru-breathe' : props.idle ? 'owl-idle' : ''} ${props.class ?? 'size-5'}`}
    >
      <img
        src={owlMark}
        alt=""
        width="128"
        height="128"
        decoding="async"
        class="block h-full w-full rounded-full bg-night object-cover"
      />
    </span>
  )
}

/** A screen or section with nothing in it yet: the owl, idle, above the screen's own words and
 * its way forward. The title carries the meaning, so the owl is decorative here. */
export function OwlEmpty(props: {
  title: string
  body?: JSX.Element | string
  action?: JSX.Element
  size?: 'sm' | 'md'
  /** The title's element: `h2` for a screen, `p` inside a section that has its own heading. */
  as?: 'h2' | 'h3' | 'p'
  class?: string
}) {
  const sm = () => props.size === 'sm'
  return (
    <div
      class={`flex flex-col items-center text-center ${sm() ? 'py-8' : 'py-14'} ${props.class ?? ''}`}
    >
      <MascotMedallion idle decorative class={sm() ? 'w-16' : 'w-24'} />
      <Dynamic
        component={props.as ?? 'h2'}
        class="mt-5 font-display text-xl font-medium text-balance"
      >
        {props.title}
      </Dynamic>
      <Show when={props.body}>
        <p class="mt-2 max-w-sm text-sm text-balance text-muted">
          {props.body}
        </p>
      </Show>
      <Show when={props.action}>
        <div class="mt-6">{props.action}</div>
      </Show>
    </div>
  )
}
