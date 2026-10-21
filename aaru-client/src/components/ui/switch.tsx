import { Show, createUniqueId } from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'

// An on/off setting that applies at once (no Kobalte): a visually hidden native checkbox with
// role="switch" holds focus and the state; a pill track, turning accent when on, and the label
// both toggle it. The value is controlled: after a change the box is set back to `checked`, so
// the owner decides (flip at once and revert on failure).

export function Switch(props: {
  checked: boolean
  onChange: (checked: boolean) => void
  label: JSX.Element
  description?: JSX.Element
  /** The track after the text, at the row's end, instead of before it. */
  trackLast?: boolean
  disabled?: boolean
  class?: string
}) {
  const id = `switch-${createUniqueId()}`
  const track = (
    // A second label for the box, so a click on the track toggles it too.
    <label
      for={id}
      aria-hidden="true"
      class={cn(
        'inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full p-0.5 transition-colors peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-accent peer-disabled:opacity-50 motion-reduce:transition-none',
        props.checked ? 'bg-accent' : 'bg-ink/25',
      )}
    >
      <span
        class="size-5 rounded-full bg-medallion shadow transition-transform motion-reduce:transition-none"
        classList={{ 'translate-x-5': props.checked }}
      />
    </label>
  )
  return (
    // `relative`: the hidden box is absolutely positioned, so focus scrolls to here.
    <div class={cn('relative', props.class)}>
      <input
        id={id}
        type="checkbox"
        role="switch"
        class="peer sr-only"
        checked={props.checked}
        disabled={props.disabled}
        aria-describedby={props.description ? `${id}-description` : undefined}
        onChange={(event) => {
          props.onChange(event.currentTarget.checked)
          event.currentTarget.checked = props.checked
        }}
      />
      <Show when={!props.trackLast}>{track}</Show>
      <span>
        <label for={id} class="cursor-pointer">
          {props.label}
        </label>
        <Show when={props.description}>
          <span id={`${id}-description`} class="block text-xs text-muted">
            {props.description}
          </span>
        </Show>
      </span>
      <Show when={props.trackLast}>{track}</Show>
    </div>
  )
}
