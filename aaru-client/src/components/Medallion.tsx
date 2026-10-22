import { Show } from 'solid-js'
import { initials } from '../lib/profile/initials'
import { cn } from '~/lib/utils'

// The user's own medallion: their initials on the medallion disc. Home's heading carries it to
// the profile (owner, 2026-10-22), and the profile's header repeats it.

export type Person = { displayName: string | null; handle: string | null }

export function Medallion(props: { person: Person; class?: string }) {
  return (
    <span
      aria-hidden="true"
      class={cn(
        'grid shrink-0 place-items-center rounded-full bg-medallion font-display font-medium text-black/75 shadow-[0_0_0_1px_var(--line-strong)]',
        props.class,
      )}
    >
      <Show
        when={initials(props.person)}
        fallback={
          <svg viewBox="0 0 24 24" class="size-1/2" fill="currentColor">
            <circle cx="12" cy="8" r="4" />
            <path d="M4 20c0-4 3.6-6 8-6s8 2 8 6z" />
          </svg>
        }
      >
        {(letters) => letters()}
      </Show>
    </span>
  )
}
