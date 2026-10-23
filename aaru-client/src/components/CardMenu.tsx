import {
  Show,
  Suspense,
  createSignal,
  lazy,
  onCleanup,
  onMount,
} from 'solid-js'
import type { JSX } from 'solid-js'
import { Button } from '~/components/ui'
import { cn } from '~/lib/utils'
import type { LibraryEntry } from '../lib/library/model'
import type { MarkTarget } from '../lib/title/model'

// A card's menu: Mark show watched (or Mark watched, for a film), then Open. A "⋯" on the card
// shows on hover or focus, and always where there is no hover; a right-click or a long press on
// touch opens the same menu. A mark applies at once and the toast offers Undo (owner,
// 2026-10-22). The menu loads on the first hover, focus or press, not with the page.

const loadPopup = () => import('./CardMenuPopup')
const CardMenuPopup = lazy(loadPopup)

/** A touch held this long opens the menu instead of the card. */
const LONG_PRESS_MS = 500
/** A finger that moves this far is scrolling, not pressing. */
const PRESS_SLOP_PX = 10

const dots = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 24 24"
    fill="currentColor"
    aria-hidden="true"
    class="size-5"
  >
    <circle cx="5.5" cy="12" r="1.6" />
    <circle cx="12" cy="12" r="1.6" />
    <circle cx="18.5" cy="12" r="1.6" />
  </svg>
)

export function CardMenu(props: {
  /** The library item. */
  id: string
  name: string
  target: MarkTarget
  onChanged: (entry?: LibraryEntry) => void
  class?: string
  /** Where the trigger sits; over the art's top right by default. */
  triggerClass?: string
  /** `art`: a scrim chip over a poster; `row`: a quiet icon in a list row. */
  tone?: 'art' | 'row'
  children: JSX.Element
}) {
  const [open, setOpen] = createSignal(false)
  // Mounted on the first ask, then kept, so closing plays the exit.
  const [mounted, setMounted] = createSignal(false)
  let card!: HTMLDivElement
  let timer: ReturnType<typeof setTimeout> | undefined
  let start: { x: number; y: number } | null = null
  /** A long press opened the menu: the click the touch ends with is not a tap on the card. */
  let pressed = false

  const triggerClass = () =>
    cn(
      'opacity-0 transition-opacity group-focus-within/card:opacity-100 group-hover/card:opacity-100 focus-visible:opacity-100 data-[expanded]:opacity-100 [@media(hover:none)]:opacity-100',
      props.tone === 'row'
        ? ['size-11 shrink-0 text-muted hover:text-ink', props.triggerClass]
        : [
            'absolute size-9 bg-scrim text-on-scrim',
            props.triggerClass ?? 'top-1.5 right-1.5',
          ],
    )

  function openMenu() {
    setMounted(true)
    setOpen(true)
  }

  function cancelPress() {
    clearTimeout(timer)
    timer = undefined
    start = null
  }

  function pointerDown(event: PointerEvent) {
    pressed = false
    void loadPopup()
    if (event.pointerType !== 'touch') return
    start = { x: event.clientX, y: event.clientY }
    timer = setTimeout(() => {
      pressed = true
      cancelPress()
      openMenu()
    }, LONG_PRESS_MS)
  }

  function pointerMove(event: PointerEvent) {
    if (
      start &&
      Math.hypot(event.clientX - start.x, event.clientY - start.y) >
        PRESS_SLOP_PX
    )
      cancelPress()
  }

  onMount(() => {
    // Capture, so the card's own link never sees the click a long press ends with.
    const click = (event: MouseEvent) => {
      if (!pressed) return
      pressed = false
      event.preventDefault()
      event.stopPropagation()
    }
    card.addEventListener('click', click, { capture: true })
    onCleanup(() => card.removeEventListener('click', click, { capture: true }))
  })
  onCleanup(cancelPress)

  // Until the menu has loaded, the same "⋯" stands in and asks for it.
  const standIn = () => (
    <Button
      variant="ghost"
      size="bare"
      aria-label={`More for ${props.name}`}
      aria-haspopup="menu"
      class={triggerClass()}
      onClick={openMenu}
    >
      {dots()}
    </Button>
  )

  return (
    <div
      ref={card}
      class={cn(
        'group/card relative [-webkit-touch-callout:none] [@media(hover:none)]:select-none',
        props.class,
      )}
      onContextMenu={(event) => {
        event.preventDefault()
        cancelPress()
        openMenu()
      }}
      onPointerEnter={() => void loadPopup()}
      onFocusIn={() => void loadPopup()}
      onPointerDown={pointerDown}
      onPointerMove={pointerMove}
      onPointerUp={cancelPress}
      onPointerCancel={cancelPress}
    >
      {props.children}
      <Show when={mounted()} fallback={standIn()}>
        <Suspense fallback={standIn()}>
          <CardMenuPopup
            id={props.id}
            name={props.name}
            target={props.target}
            onChanged={props.onChanged}
            open={open()}
            onOpenChange={setOpen}
            triggerClass={triggerClass()}
            icon={dots()}
          />
        </Suspense>
      </Show>
    </div>
  )
}
