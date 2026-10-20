import { splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'

/** A failure the page could not recover from on its own, announced as it appears. */
export function Alert(props: JSX.HTMLAttributes<HTMLParagraphElement>) {
  const [local, rest] = splitProps(props, ['class'])
  return (
    <p
      role="alert"
      class={cn(
        'rounded-panel bg-danger/10 px-4 py-3 text-sm text-danger',
        local.class,
      )}
      {...rest}
    />
  )
}
