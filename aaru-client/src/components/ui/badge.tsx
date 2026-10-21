import { splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import { cva } from 'class-variance-authority'
import type { VariantProps } from 'class-variance-authority'
import { cn } from '../../lib/cn'

export const badgeVariants = cva('rounded-full font-semibold', {
  variants: {
    tone: {
      accent: 'bg-accent text-on-accent',
      ink: 'bg-ink text-paper',
      /** On top of artwork, where the page's colours would not read. */
      scrim: 'bg-black/65 text-white',
      /** Quiet: a count or a filter on the page's own colours. */
      soft: 'bg-ink/10 text-ink',
    },
    size: {
      md: 'px-2 py-0.5 text-xs',
      /** Inside a calendar cell or on a thumbnail. */
      xs: 'px-1.5 text-xs leading-5',
    },
  },
  defaultVariants: { tone: 'accent', size: 'md' },
})

export function Badge(
  props: JSX.HTMLAttributes<HTMLSpanElement> &
    VariantProps<typeof badgeVariants>,
) {
  const [local, rest] = splitProps(props, ['tone', 'size', 'class'])
  return (
    <span
      class={cn(
        badgeVariants({ tone: local.tone, size: local.size }),
        local.class,
      )}
      {...rest}
    />
  )
}
