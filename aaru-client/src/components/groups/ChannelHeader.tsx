import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import type { Channel } from '../../lib/groups/server'
import { reconnecting } from '../../lib/realtime/socket'
import { ChannelGlyph } from './ChannelGlyph'
import { useGroup, useShell } from './shell'

/**
 * The bar above a channel: back to channels on a phone, the drawer on a tablet, the channel's
 * glyph, name and topic, "Reconnecting…" when the socket has been down a while, the
 * "Not end-to-end" chip where people write, and the member list.
 */
export function ChannelHeader(props: {
  channel: Channel
  onOpenMembers: () => void
  /** The "Not end-to-end" chip; off where nobody writes messages (a shelf). */
  e2e?: boolean
}) {
  const shell = useShell()
  const scope = useGroup()
  const groupId = () => scope.detail().group.id
  return (
    <header class="flex h-14 shrink-0 items-center gap-2 border-b border-line px-3 md:px-4">
      <Link
        to="/app/groups/$groupId"
        params={{ groupId: groupId() }}
        aria-label="Channels"
        class="-ml-1 grid size-9 place-items-center rounded-full text-muted hover:bg-surface hover:text-ink md:hidden"
      >
        <svg
          viewBox="0 0 20 20"
          class="size-5"
          fill="currentColor"
          aria-hidden="true"
        >
          <path d="M12.5 4.2a.75.75 0 0 1 0 1.06L7.8 10l4.7 4.74a.75.75 0 1 1-1.06 1.06l-5.24-5.27a.75.75 0 0 1 0-1.06l5.24-5.27a.75.75 0 0 1 1.06 0Z" />
        </svg>
      </Link>
      <button
        type="button"
        aria-label="Groups and channels"
        onClick={() => shell.setDrawer(true)}
        class="-ml-1 hidden size-9 place-items-center rounded-full text-muted hover:bg-surface hover:text-ink md:max-lg:grid"
      >
        <svg
          viewBox="0 0 20 20"
          class="size-5"
          fill="currentColor"
          aria-hidden="true"
        >
          <path d="M3 5.75A.75.75 0 0 1 3.75 5h12.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 5.75Zm0 4.25a.75.75 0 0 1 .75-.75h12.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 10Zm.75 3.5a.75.75 0 0 0 0 1.5h12.5a.75.75 0 0 0 0-1.5z" />
        </svg>
      </button>
      <h1 class="flex min-w-0 items-center gap-1.5 font-semibold">
        <ChannelGlyph channel={props.channel} />
        <span class="truncate">{props.channel.name}</span>
      </h1>
      <Show when={props.channel.topic}>
        {(topic) => (
          <p class="hidden min-w-0 flex-1 truncate border-l border-line pl-3 text-sm text-muted md:block">
            {topic()}
          </p>
        )}
      </Show>
      <span class="flex-1 md:hidden" />
      <Show when={!props.channel.topic}>
        <span class="hidden flex-1 md:block" />
      </Show>
      <Show when={reconnecting()}>
        <span
          role="status"
          class="shrink-0 text-xs text-muted motion-safe:animate-pulse"
        >
          Reconnecting…
        </span>
      </Show>
      <Show when={props.e2e !== false}>
        <details class="group/e2e relative shrink-0">
          <summary class="flex cursor-pointer list-none items-center gap-1 rounded-full border border-line px-2.5 py-1 text-xs font-medium text-muted hover:text-ink [&::-webkit-details-marker]:hidden">
            {/* An open lock: a closed one would read as "encrypted". */}
            <svg
              viewBox="0 0 20 20"
              class="size-3.5"
              fill="none"
              stroke="currentColor"
              stroke-width="1.6"
              stroke-linecap="round"
              aria-hidden="true"
            >
              <rect x="4" y="9" width="12" height="8" rx="1.5" />
              <path d="M7 9V6a3 3 0 0 1 5.8-1.1" />
            </svg>
            <span class="hidden sm:inline">Not end-to-end</span>
            <span class="sm:hidden">Not E2E</span>
          </summary>
          <div class="group-pop absolute top-full right-0 z-30 mt-2 w-72 rounded-2xl border border-line bg-paper p-4 text-sm leading-relaxed shadow-xl">
            Group messages are stored readable on Aaru's server so the group
            works on every device, and every member can read them. Nobody
            outside the group can see this channel.
          </div>
        </details>
      </Show>
      <button
        type="button"
        aria-label="Members"
        title="Members"
        aria-pressed={scope.membersOpen()}
        onClick={() => props.onOpenMembers()}
        class={`grid size-9 shrink-0 place-items-center rounded-full text-muted hover:bg-surface hover:text-ink ${scope.membersOpen() ? 'lg:bg-surface lg:text-ink' : ''}`}
      >
        <svg
          viewBox="0 0 20 20"
          class="size-5"
          fill="currentColor"
          aria-hidden="true"
        >
          <path d="M7 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm6.5 0a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5ZM1.6 15.6C2.3 12.9 4.4 11 7 11s4.7 1.9 5.4 4.6a1 1 0 0 1-1 1.4H2.6a1 1 0 0 1-1-1.4Zm12.2 1.4h2.6a1 1 0 0 0 1-1.3c-.6-2.1-2.2-3.7-4.3-3.7-.6 0-1.1.1-1.6.3 1 1 1.8 2.3 2.3 3.8.1.3.1.6 0 .9Z" />
        </svg>
      </button>
    </header>
  )
}
