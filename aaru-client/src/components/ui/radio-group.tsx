import { createContext, createUniqueId, useContext } from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'

// A radio group on native radios (no Kobalte): the browser gives arrow keys and one tab stop.
// Each option is a visually hidden `<input type="radio">` sharing the group's `name`, followed by
// the visible label, ringed by `peer-focus-visible`. The value is
// controlled: after a change the radios are set back to what `value` says.

type RadioGroupContextValue = {
  name: string
  value: () => string | undefined
  select: (value: string) => void
}

const RadioGroupContext = createContext<RadioGroupContextValue>()

export function RadioGroup(props: {
  value?: string
  onChange?: (value: string) => void
  'aria-label'?: string
  class?: string
  children: JSX.Element
}) {
  const name = `radio-${createUniqueId()}`
  return (
    <RadioGroupContext.Provider
      value={{
        name,
        value: () => props.value,
        select: (value) => props.onChange?.(value),
      }}
    >
      <div
        role="radiogroup"
        aria-label={props['aria-label']}
        class={props.class}
      >
        {props.children}
      </div>
    </RadioGroupContext.Provider>
  )
}

/** One option. `on` / `off` are the label's classes when chosen and when not: plain utilities
 *  the stylesheet already has, rather than `data-*` variants it would grow by. */
export function RadioOption(props: {
  value: string
  disabled?: boolean
  class?: string
  on: string
  off: string
  children: JSX.Element
}) {
  const group = useContext(RadioGroupContext)!
  const checked = () => group.value() === props.value
  return (
    // `relative`: the hidden radio is absolutely positioned, so focus scrolls to here.
    <label class="relative flex">
      <input
        type="radio"
        class="peer sr-only"
        name={group.name}
        value={props.value}
        checked={checked()}
        disabled={props.disabled}
        onChange={() => {
          group.select(props.value)
          // Controlled: a change the owner did not take is undone.
          for (const radio of document.getElementsByName(group.name))
            (radio as HTMLInputElement).checked =
              (radio as HTMLInputElement).value === group.value()
        }}
      />
      <span
        class={cn(
          'cursor-pointer peer-focus-visible:outline-2 peer-focus-visible:outline-accent peer-disabled:opacity-50',
          props.class,
          checked() ? props.on : props.off,
        )}
      >
        {props.children}
      </span>
    </label>
  )
}

/** A chip: accent when chosen, outlined otherwise. */
export function RadioGroupItem(props: {
  value: string
  disabled?: boolean
  class?: string
  children: JSX.Element
}) {
  return (
    <RadioOption
      value={props.value}
      disabled={props.disabled}
      class={cn(
        'inline-flex min-h-11 items-center rounded-full border px-4 text-sm font-semibold peer-focus-visible:outline-offset-2',
        props.class,
      )}
      on="border-accent bg-accent text-on-accent"
      off="border-ink/25"
    >
      {props.children}
    </RadioOption>
  )
}
