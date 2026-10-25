import { For } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  SegmentedControl,
  SegmentedControlItem,
  SegmentedControlItemInput,
  SegmentedControlItemLabel,
  SegmentedControlItems,
} from '~/components/ui'
import { cn } from '~/lib/utils'

export type SegmentedOption<T extends string> = {
  value: T
  label: JSX.Element
  disabled?: boolean
}

// `pill`: one bordered track, the choice filled with ink. `chip`: separate chips that wrap,
// for longer sets (kinds, statuses, distances).
const tracks = {
  pill: 'flex w-fit rounded-full border border-line p-0.5',
  chip: 'flex flex-wrap gap-1.5',
}
const items = {
  pill: 'rounded-full text-muted hover:text-ink data-[checked]:bg-ink data-[checked]:text-paper',
  chip: 'rounded-full border border-line text-ink hover:bg-surface data-[checked]:border-transparent data-[checked]:bg-ink data-[checked]:text-paper',
}

/**
 * One choice of a few (WEB-009): shadcn-solid's SegmentedControl, a Kobalte radio group, so a
 * screen reader hears "radio, 2 of 3" and the arrow keys move the choice. Every one-of-N view
 * switch and filter on the web uses this; there is no toggle-button group for single choices.
 */
export function Segmented<T extends string>(props: {
  options: readonly SegmentedOption<T>[]
  value: T | undefined
  onChange: (value: T) => void
  label: string
  variant?: keyof typeof tracks
  class?: string
  /** Size and spacing of each choice, e.g. "min-h-9 px-4 text-sm". */
  itemClass?: string
  /** Extra classes on the track, e.g. a strip that scrolls instead of wrapping. */
  trackClass?: string
}) {
  const variant = () => props.variant ?? 'pill'
  return (
    <SegmentedControl
      aria-label={props.label}
      // Kobalte keeps a controlled radio group: '' means nothing chosen yet.
      value={props.value ?? ''}
      onChange={(next: string) => props.onChange(next as T)}
      class={cn('block', props.class)}
    >
      <SegmentedControlItems
        class={cn(
          'p-0 group-[[aria-orientation=vertical]]/segmented-control:flex-col',
          tracks[variant()],
          props.trackClass,
        )}
      >
        <For each={props.options}>
          {(option) => (
            <SegmentedControlItem
              value={option.value}
              disabled={option.disabled}
              class={cn(
                'relative cursor-pointer transition-colors before:hidden',
                'has-[[data-slot=segmented-control-item-input]:focus-visible]:outline-2 has-[[data-slot=segmented-control-item-input]:focus-visible]:outline-offset-2 has-[[data-slot=segmented-control-item-input]:focus-visible]:outline-ring',
                items[variant()],
              )}
            >
              <SegmentedControlItemInput />
              <SegmentedControlItemLabel
                class={cn(
                  'flex cursor-pointer items-center justify-center font-medium text-current dark:text-current dark:data-[checked]:text-current',
                  props.itemClass ?? 'px-3.5 py-1.5 text-sm',
                )}
              >
                {option.label}
              </SegmentedControlItemLabel>
            </SegmentedControlItem>
          )}
        </For>
      </SegmentedControlItems>
    </SegmentedControl>
  )
}
