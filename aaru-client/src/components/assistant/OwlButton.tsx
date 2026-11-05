import { onCleanup } from 'solid-js'
import type { JSX } from 'solid-js'
import { Button } from '~/components/ui'
import { OwlMark } from '../Brand'

// The owl (DESIGN.md "Assistant"): a click opens the card ready to type; a long press (0.4 s)
// opens it listening. Shown only while the server has the assistant on.

const LONG_PRESS_MS = 400

export function OwlButton(props: {
  onAsk: (listen: boolean) => void
  class?: string
  /** "Ask Aaru" beside the owl, as the sidebar's rows have. */
  label?: boolean
  children?: JSX.Element
}) {
  let timer: ReturnType<typeof setTimeout> | undefined
  let pressed = false
  const clear = () => clearTimeout(timer)
  onCleanup(clear)
  return (
    <Button
      variant="ghost"
      size={props.label ? 'default' : 'icon'}
      aria-label="Ask Aaru"
      title="Ask Aaru (⌘J)"
      aria-keyshortcuts="Meta+J Control+J"
      class={props.class}
      onPointerDown={() => {
        pressed = false
        timer = setTimeout(() => {
          pressed = true
          props.onAsk(true)
        }, LONG_PRESS_MS)
      }}
      onPointerUp={clear}
      onPointerLeave={clear}
      onClick={() => {
        clear()
        if (!pressed) props.onAsk(false)
        pressed = false
      }}
    >
      <OwlMark class="size-7" idle />
      {props.label ? <span class="flex-1 text-left">Ask Aaru</span> : null}
      {props.children}
    </Button>
  )
}
