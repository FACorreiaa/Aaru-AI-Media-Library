import { splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import { cva } from 'class-variance-authority'
import type { VariantProps } from 'class-variance-authority'
import { cn } from '../../lib/cn'

// solid-ui's Button, on Aaru's tokens. A `Link` that looks like a button takes
// `class={buttonVariants({ ... })}` instead of a polymorphic `as`.
export const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-full transition-[transform,background-color,color] disabled:pointer-events-none disabled:opacity-50 motion-safe:active:scale-[0.98]',
  {
    variants: {
      variant: {
        primary: 'bg-accent font-semibold text-on-accent',
        outline: 'border border-ink/25 font-semibold hover:bg-surface',
        quiet: 'border border-line font-semibold hover:bg-surface',
        ink: 'bg-ink font-semibold text-paper',
        danger: 'bg-danger font-semibold text-on-accent',
        'danger-outline': 'border border-danger/50 font-semibold text-danger',
        ghost: 'font-medium text-muted hover:text-ink',
        soft: 'font-medium hover:bg-surface',
      },
      size: {
        xs: 'px-3 py-1 text-xs',
        sm: 'px-4 py-1.5 text-sm',
        md: 'min-h-11 px-5 text-sm',
        lg: 'px-6 py-3',
        icon: 'size-11',
        bare: '',
      },
    },
    defaultVariants: { variant: 'outline', size: 'md' },
  },
)

export type ButtonProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonVariants>

export function Button(props: ButtonProps) {
  const [local, rest] = splitProps(props, ['variant', 'size', 'class', 'type'])
  return (
    <button
      type={local.type ?? 'button'}
      class={cn(
        buttonVariants({ variant: local.variant, size: local.size }),
        local.class,
      )}
      {...rest}
    />
  )
}
