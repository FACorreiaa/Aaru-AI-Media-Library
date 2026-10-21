import { splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'

/** A surface panel: the `rounded-[20px] bg-surface` block repeated across the app. */
export const cardClass = 'rounded-card bg-surface'

export function Card(props: JSX.HTMLAttributes<HTMLElement>) {
  const [local, rest] = splitProps(props, ['class'])
  return <section class={cn(cardClass, local.class)} {...rest} />
}
