import { Link, useRouter } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { cn } from '~/lib/utils'
import { useAppShell } from './context'
import { BackIcon } from './icons'

const linkClass =
  'inline-flex min-h-11 items-center gap-1 rounded-full pr-3 text-sm font-medium text-muted hover:text-ink'

/**
 * A detail page's way back (UX-006): it names the page you came from ("‹ Calendar",
 * "‹ Andor") and goes back in history, so that page keeps its place. Opened cold, it names the
 * page's owning destination instead.
 */
export function BackLink(props: { to: string; label: string; class?: string }) {
  const shell = useAppShell()
  const router = useRouter()
  return (
    <Show
      when={shell.previous()}
      fallback={
        <Link to={props.to} class={cn(linkClass, props.class)}>
          <BackIcon class="size-4" />
          {props.label}
        </Link>
      }
    >
      {(previous) => (
        <a
          href={previous().href}
          class={cn(linkClass, props.class)}
          onClick={(event) => {
            if (event.metaKey || event.ctrlKey || event.shiftKey) return
            event.preventDefault()
            router.history.back()
          }}
        >
          <BackIcon class="size-4" />
          {previous().label}
        </a>
      )}
    </Show>
  )
}
