import type { ComponentProps, ValidComponent } from 'solid-js'
import { splitProps } from 'solid-js'
import { Root as ButtonPrimitive } from '@kobalte/core/button'
import type { VariantProps } from 'cva'

import { cva } from '~/lib/cva'

// shadcn-solid's Button on Aaru's look: pills, a 44 pt default height, press feedback, and
// Aaru's extra variants (quiet, ink, danger-outline, soft) and sizes (xs, bare). The shared
// names keep shadcn's meaning: `default` is the filled accent, `destructive` the filled danger.
export const buttonVariants = cva({
  base: [
    'inline-flex items-center justify-center gap-2 rounded-full font-medium transition-[transform,background-color,color,box-shadow] [&_svg:not([class*=size-])]:size-4 outline-none motion-safe:active:scale-[0.98]',
    'disabled:pointer-events-none disabled:opacity-50',
    '[&_svg]:pointer-events-none [&_svg]:shrink-0',
    'focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]',
    'aria-[invalid]:ring-destructive/20 aria-[invalid]:dark:ring-destructive/40 aria-[invalid]:border-destructive',
  ],

  variants: {
    variant: {
      default:
        'bg-primary font-semibold text-primary-foreground hover:bg-primary/90',
      destructive:
        'bg-destructive font-semibold text-on-accent hover:bg-destructive/90 focus-visible:ring-destructive/20 focus-visible:dark:ring-destructive/40',
      outline: 'border border-ink/25 font-semibold hover:bg-surface',
      secondary:
        'bg-secondary font-semibold text-secondary-foreground hover:bg-secondary/80',
      ghost: 'text-muted hover:text-ink',
      link: 'text-primary underline-offset-4 hover:underline',
      // Aaru
      quiet: 'border border-line font-semibold hover:bg-surface',
      ink: 'bg-ink font-semibold text-paper',
      'danger-outline': 'border border-danger/50 font-semibold text-danger',
      soft: 'hover:bg-surface',
    },
    size: {
      default: 'min-h-11 px-5 text-sm',
      sm: 'px-4 py-1.5 text-sm',
      lg: 'px-6 py-3 text-base',
      icon: 'size-11',
      'icon-sm': 'size-8',
      'icon-lg': 'size-10',
      // Aaru
      xs: 'px-3 py-1 text-xs',
      /** No box at all: an inline text button. */
      bare: '',
    },
  },
  defaultVariants: {
    variant: 'default',
    size: 'default',
  },
})

export type ButtonProps<T extends ValidComponent = 'button'> = ComponentProps<
  typeof ButtonPrimitive<T>
> &
  VariantProps<typeof buttonVariants>

export const Button = <T extends ValidComponent = 'button'>(
  props: ButtonProps<T>,
) => {
  const [, rest] = splitProps(props as ButtonProps, [
    'class',
    'variant',
    'size',
  ])

  return (
    <ButtonPrimitive
      data-slot="button"
      class={buttonVariants({
        variant: props.variant,
        size: props.size,
        class: props.class,
      })}
      {...rest}
    />
  )
}
