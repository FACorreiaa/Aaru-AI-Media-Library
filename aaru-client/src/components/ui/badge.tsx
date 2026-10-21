import { splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import { cva } from 'class-variance-authority'
import type { VariantProps } from 'class-variance-authority'
import { cn } from '../../lib/cn'

export const badgeVariants = cva(
  'rounded-full px-2 py-0.5 text-xs font-semibold',
  {
    variants: {
      tone: {
        accent: 'bg-accent text-on-accent',
        ink: 'bg-ink text-paper',
        /** On top of artwork, where the page's colours would not read. */
        scrim: 'bg-black/65 text-white',
      },
    },
    defaultVariants: { tone: 'accent' },
  },
)

export function Badge(
  props: JSX.HTMLAttributes<HTMLSpanElement> &
    VariantProps<typeof badgeVariants>,
) {
  const [local, rest] = splitProps(props, ['tone', 'class'])
  return (
    <span
      class={cn(badgeVariants({ tone: local.tone }), local.class)}
      {...rest}
    />
  )
}
