import { For, Show, createSignal, onCleanup, onMount } from 'solid-js'
import type { RecapCard } from '../../lib/recap/deck'
import type { Stats } from '../../lib/recap/model'
import { RecapCardView } from './RecapCards'
import { prefersReducedMotion } from '../../lib/reduced-motion'
import { shareRecap } from './share'
import { Dialog, DialogContent, DialogPortal } from '~/components/ui'

// GAM-006a: the Recap story. Tap the right of a card to go on, the left to go back, hold to
// pause; arrows and Esc on a keyboard. Cards advance on their own unless the viewer asked for
// reduced motion, in which case they cross-fade and wait for a tap.

const CARD_MS = 6000
const TICK_MS = 100
/** Shorter than this, a press is a tap; longer, it was a hold. */
const TAP_MS = 250

const BACKDROPS = [
  'bg-ink text-paper',
  'bg-accent text-on-accent',
  'bg-surface text-ink',
]

export function RecapStory(props: {
  stats: Stats
  deck: RecapCard[]
  onClose: () => void
}) {
  const [index, setIndex] = createSignal(0)
  const [elapsed, setElapsed] = createSignal(0)
  const [held, setHeld] = createSignal(false)
  const [shareNote, setShareNote] = createSignal<string | null>(null)
  const [sharing, setSharing] = createSignal(false)
  const still = prefersReducedMotion()
  const last = () => props.deck.length - 1
  let pressedAt = 0

  function go(to: number) {
    setIndex(Math.max(0, Math.min(last(), to)))
    setElapsed(0)
  }

  onMount(() => {
    const timer = setInterval(() => {
      if (still || held()) return
      const next = elapsed() + TICK_MS
      // The last card fills its bar, then stays.
      if (next < CARD_MS) setElapsed(next)
      else if (index() < last()) go(index() + 1)
      else setElapsed(CARD_MS)
    }, TICK_MS)
    onCleanup(() => clearInterval(timer))
  })

  // Esc is the dialog's own: it closes, and onClose leaves. Space on a button or link presses
  // it, as anywhere else; elsewhere it goes on, like the right arrow.
  function onKeyDown(event: KeyboardEvent) {
    const onControl =
      event.target instanceof Element &&
      event.target.closest('button, a') !== null
    if (event.key === 'ArrowRight' || (event.key === ' ' && !onControl)) {
      event.preventDefault()
      go(index() + 1)
    } else if (event.key === 'ArrowLeft') go(index() - 1)
  }

  function onPointerDown() {
    pressedAt = Date.now()
    setHeld(true)
  }

  function onPointerUp(event: PointerEvent) {
    setHeld(false)
    if (Date.now() - pressedAt > TAP_MS) return
    const box = (event.currentTarget as HTMLElement).getBoundingClientRect()
    go(event.clientX - box.left < box.width / 3 ? index() - 1 : index() + 1)
  }

  async function share() {
    setSharing(true)
    setShareNote(null)
    try {
      const how = await shareRecap(props.stats)
      if (how === 'downloaded') setShareNote('Saved as an image.')
    } catch (err) {
      setShareNote(
        err instanceof Error ? err.message : 'The image could not be made.',
      )
    } finally {
      setSharing(false)
    }
  }

  const progress = (i: number) =>
    i < index() ? 1 : i > index() ? 0 : still ? 1 : elapsed() / CARD_MS

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="full"
          showCloseButton={false}
          aria-label="Your recap"
          onKeyDown={onKeyDown}
          class="block gap-0 p-0"
        >
          {/* Focus starts here, not on Close, so Space and the arrows work at once; a tap on the
          story keeps it here. */}
          <div
            autofocus
            tabindex={-1}
            class={`flex h-full flex-col outline-none transition-colors duration-500 ${BACKDROPS[index() % BACKDROPS.length]}`}
          >
            <div class="mx-auto flex w-full max-w-xl items-center gap-3 px-4 pt-4">
              <div class="flex flex-1 gap-1" aria-hidden="true">
                <For each={props.deck}>
                  {(_, i) => (
                    <div class="h-[3px] flex-1 overflow-hidden rounded-full bg-current/25">
                      <div
                        class="h-full origin-left bg-current"
                        style={{ transform: `scaleX(${progress(i())})` }}
                      />
                    </div>
                  )}
                </For>
              </div>
              <button
                type="button"
                class="-mr-2 rounded-full px-3 py-1 text-sm font-medium hover:bg-current/10"
                onClick={() => props.onClose()}
              >
                Close
              </button>
            </div>
            <p class="sr-only" aria-live="polite">
              Card {index() + 1} of {props.deck.length}
            </p>
            <div
              class="mx-auto flex w-full max-w-xl flex-1 cursor-pointer flex-col justify-center px-6 pb-16 select-none md:px-8"
              onPointerDown={onPointerDown}
              onPointerUp={onPointerUp}
              onPointerCancel={() => setHeld(false)}
            >
              <Show when={props.deck[index()]} keyed>
                {(card) => (
                  <section class="recap-card">
                    <RecapCardView
                      card={card}
                      stats={props.stats}
                      share={
                        <div
                          onPointerDown={(e) => e.stopPropagation()}
                          onPointerUp={(e) => e.stopPropagation()}
                        >
                          <button
                            type="button"
                            class="rounded-full border-2 border-current px-6 py-3 font-medium hover:bg-current/10 disabled:opacity-60"
                            disabled={sharing()}
                            onClick={share}
                          >
                            {sharing()
                              ? 'Making the image…'
                              : 'Share as an image'}
                          </button>
                          {/* Always present, so the note is announced when it appears: a toast
                          region outside this modal would be inert while it is open. */}
                          <p
                            role="status"
                            class="text-sm opacity-80"
                            classList={{ 'mt-3': !!shareNote() }}
                          >
                            {shareNote()}
                          </p>
                        </div>
                      }
                    />
                  </section>
                )}
              </Show>
            </div>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
