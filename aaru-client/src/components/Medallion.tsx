import { Show } from 'solid-js'
import { initials } from '../lib/profile/initials'
import { avatarSrc } from '../lib/profile/avatar-src'
import { Avatar, AvatarFallback, AvatarImage } from '~/components/ui'
import { cn } from '~/lib/utils'

// The user's own medallion: their photo, else their initials, on the medallion disc. Home's
// heading carries it to the profile (owner, 2026-10-22), and the profile's header repeats it.

export type Person = {
  displayName: string | null
  handle: string | null
  avatarUrl?: string | null
}

export function Medallion(props: { person: Person; class?: string }) {
  return (
    <Avatar
      aria-hidden="true"
      class={cn(
        'font-display font-medium text-ink shadow-[0_0_0_1px_var(--line-strong)]',
        props.class,
      )}
    >
      <Show when={avatarSrc(props.person.avatarUrl)}>
        {(src) => <AvatarImage src={src()} alt="" />}
      </Show>
      <AvatarFallback>
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
      </AvatarFallback>
    </Avatar>
  )
}
