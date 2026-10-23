import type { ComponentProps } from 'solid-js'
import { splitProps } from 'solid-js'
import type { VariantProps } from 'cva'

import { cva } from '~/lib/cva'

// shadcn-solid's Badge on Aaru's look: a pill, plus Aaru's tones (ink, scrim, soft) and an
// extra-small size for calendar cells and thumbnails. A plain span (WEB-001): Kobalte's Badge
// is role="status", which made every count and calendar tag a live region. A badge that must
// announce a change takes role="status" from its caller.
export const badgeVariants = cva({
  base: 'inline-flex items-center justify-center rounded-full border font-semibold w-fit whitespace-nowrap shrink-0 [&>svg]:size-3 gap-1 [&>svg]:pointer-events-none focus-visible:border-ring aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive transition-[color,box-shadow] overflow-hidden',
  variants: {
    variant: {
      default:
        'border-transparent bg-primary text-primary-foreground [a&]:hover:bg-primary/90',
      secondary:
        'border-transparent bg-secondary text-secondary-foreground [a&]:hover:bg-secondary/90',
      destructive:
        'border-transparent bg-destructive text-on-accent [a&]:hover:bg-destructive/90 focus-visible:ring-destructive/20 dark:focus-visible:ring-destructive/40',
      outline:
        'text-foreground [a&]:hover:bg-accent [a&]:hover:text-accent-foreground',
      // Aaru
      ink: 'border-transparent bg-ink text-paper',
      /** On top of artwork, where the page's colours would not read. */
      scrim: 'border-transparent bg-black/65 text-white',
      /** Quiet: a count or a filter on the page's own colours. */
      soft: 'border-transparent bg-ink/10 text-ink',
    },
    size: {
      default: 'px-2 py-0.5 text-xs',
      /** Inside a calendar cell or on a thumbnail. */
      xs: 'px-1.5 text-xs leading-5',
    },
  },
  defaultVariants: {
    variant: 'default',
    size: 'default',
  },
})

export type BadgeProps = ComponentProps<'span'> &
  VariantProps<typeof badgeVariants>

export const Badge = (props: BadgeProps) => {
  const [, rest] = splitProps(props, ['class', 'variant', 'size'])

  return (
    <span
      data-slot="badge"
      class={badgeVariants({
        variant: props.variant,
        size: props.size,
        class: props.class,
      })}
      {...rest}
    />
  )
}
