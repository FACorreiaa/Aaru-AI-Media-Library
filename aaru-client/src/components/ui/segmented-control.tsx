import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'
import { RadioGroup, RadioOption } from './radio-group'

// One choice out of a few, drawn as segments: a native radio group (see radio-group.tsx), so
// arrow keys move the choice and the group is one tab stop. No sliding indicator.

export const SegmentedControl = RadioGroup

/** Each look as [base, chosen, not chosen]. */
const SEGMENT_LOOKS = {
  /** Ink when chosen, muted text otherwise. */
  ink: [
    'rounded-full font-medium',
    'bg-ink text-paper',
    'text-muted hover:text-ink',
  ],
  /** Ink when chosen, an outlined pill otherwise. */
  chip: [
    'rounded-full font-medium',
    'bg-ink text-paper',
    'border border-line text-ink hover:bg-surface',
  ],
  /** A surface tint and semibold when chosen. */
  surface: ['', 'bg-surface font-semibold', ''],
} as const

export function SegmentedControlItem(props: {
  value: string
  variant?: keyof typeof SEGMENT_LOOKS
  disabled?: boolean
  /** On the visible segment. */
  class?: string
  children: JSX.Element
}) {
  const look = () => SEGMENT_LOOKS[props.variant ?? 'ink']
  return (
    <RadioOption
      value={props.value}
      disabled={props.disabled}
      // The ring is inset: segments sit in pill containers that may clip.
      class={cn(
        'flex items-center peer-focus-visible:-outline-offset-2',
        look()[0],
        props.class,
      )}
      on={look()[1]}
      off={look()[2]}
    >
      {props.children}
    </RadioOption>
  )
}
