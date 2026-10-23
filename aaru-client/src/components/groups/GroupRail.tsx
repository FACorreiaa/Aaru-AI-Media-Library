import { Link, useParams } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import { badgeText, groupMonogram } from '../../lib/groups/model'
import { Button } from '~/components/ui'
import { useShell } from './shell'

/**
 * GroupRail (GRP-004): the groups you are in as monogram circles, an unread dot, a mention
 * count, and `+` to create. "All groups" sits on top with your waiting invites (UX-086: not
 * "Home", which is the app's Home).
 */
export function GroupRail(props: { class?: string }) {
  const shell = useShell()
  const params = useParams({ strict: false })
  const selected = () => (params() as { groupId?: string }).groupId

  const circle =
    'grid size-12 place-items-center font-display text-base font-medium transition-[border-radius,background-color] duration-200'

  return (
    <nav
      aria-label="Your groups"
      class={`w-[72px] shrink-0 flex-col items-center gap-2 overflow-y-auto border-r border-line bg-surface py-3 ${props.class ?? ''}`}
    >
      <Link
        to="/app/groups"
        activeOptions={{ exact: true }}
        aria-label={
          shell.invites().length > 0
            ? `All groups, ${shell.invites().length} invites`
            : 'All groups'
        }
        title="All groups"
        class="relative"
        onClick={() => shell.setDrawer(false)}
      >
        {(state) => (
          <>
            <span
              class={`${circle} ${state.isActive ? 'rounded-card bg-accent text-on-accent' : 'rounded-full bg-paper text-ink hover:rounded-card'}`}
            >
              <svg
                viewBox="0 0 24 24"
                class="size-5"
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                aria-hidden="true"
              >
                <rect x="4.5" y="4.5" width="6" height="6" rx="1.5" />
                <rect x="13.5" y="4.5" width="6" height="6" rx="1.5" />
                <rect x="4.5" y="13.5" width="6" height="6" rx="1.5" />
                <rect x="13.5" y="13.5" width="6" height="6" rx="1.5" />
              </svg>
            </span>
            <Show when={shell.invites().length > 0}>
              <span class="absolute -right-1 -bottom-1 min-w-5 rounded-full border-2 border-surface bg-danger px-1 text-center text-2xs leading-4 font-semibold text-paper">
                {badgeText(shell.invites().length)}
              </span>
            </Show>
          </>
        )}
      </Link>
      <span aria-hidden="true" class="my-1 h-px w-8 bg-line" />
      <For each={shell.groups()}>
        {(group) => {
          const active = () => selected() === group.id
          return (
            <Link
              to="/app/groups/$groupId/$channelId"
              params={{ groupId: group.id, channelId: group.defaultChannelId }}
              title={group.name}
              aria-label={`${group.name}${group.mentions > 0 ? `, ${group.mentions} mentions` : group.unread > 0 ? ', unread' : ''}`}
              aria-current={active() ? 'page' : undefined}
              class="group relative flex w-full justify-center"
            >
              <span
                aria-hidden="true"
                class={`absolute top-1/2 left-0 w-1 -translate-y-1/2 rounded-r-full bg-ink transition-[height] duration-200 ${active() ? 'h-8' : group.unread > 0 ? 'h-2' : 'h-0 group-hover:h-4'}`}
              />
              <span
                class={`${circle} ${active() ? 'rounded-card bg-accent text-on-accent' : 'rounded-full bg-paper text-ink group-hover:rounded-card'}`}
              >
                {groupMonogram(group.name)}
              </span>
              <Show when={group.mentions > 0}>
                <span class="absolute right-2 -bottom-1 min-w-5 rounded-full border-2 border-surface bg-danger px-1 text-center text-2xs leading-4 font-semibold text-paper tabular-nums">
                  {badgeText(group.mentions)}
                </span>
              </Show>
            </Link>
          )
        }}
      </For>
      <Button
        variant="ghost"
        size="bare"
        onClick={() => shell.openCreate()}
        title="Create a group"
        aria-label="Create a group"
        class={`${circle} rounded-full border border-dashed border-line text-accent hover:rounded-card hover:bg-paper hover:text-accent`}
      >
        <span aria-hidden="true" class="text-2xl leading-none">
          +
        </span>
      </Button>
    </nav>
  )
}
