import { Show, createSignal } from 'solid-js'
import { cn } from '~/lib/utils'

/** A league, team or fighter badge from the provider, hotlinked; the initial on the medallion
 * disc when there is none or it fails. Decorative: the name always sits beside it. */
export function SportBadge(props: {
  url?: string
  name: string
  class?: string
}) {
  const [broken, setBroken] = createSignal(false)
  return (
    <Show
      when={props.url && !broken() ? props.url : null}
      fallback={
        <span
          aria-hidden="true"
          class={cn(
            'grid size-6 shrink-0 place-items-center rounded-full bg-medallion font-display text-2xs font-medium text-ink',
            props.class,
          )}
        >
          {props.name.trim().charAt(0).toUpperCase()}
        </span>
      }
    >
      {(src) => (
        <img
          src={src()}
          alt=""
          loading="lazy"
          decoding="async"
          referrerpolicy="no-referrer"
          onError={() => setBroken(true)}
          class={cn('size-6 shrink-0 object-contain', props.class)}
        />
      )}
    </Show>
  )
}
