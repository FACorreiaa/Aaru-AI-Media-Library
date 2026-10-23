import { Show, createContext, onCleanup, useContext } from 'solid-js'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '~/components/ui'
import type { Accessor, JSX, Setter } from 'solid-js'
import { badgeText } from '../../lib/groups/model'
import type {
  GroupDetail,
  GroupInvite,
  GroupSummary,
  Me,
} from '../../lib/groups/server'

// Shared state for the groups screens: the shell (you, your groups, invites, the tablet drawer)
// and the open group. Routes fill these; panes read them.

export type Shell = {
  me: Accessor<Me>
  groups: Accessor<GroupSummary[]>
  setGroups: Setter<GroupSummary[]>
  invites: Accessor<GroupInvite[]>
  setInvites: Setter<GroupInvite[]>
  /** Refetches groups and invites. */
  refresh: () => Promise<void>
  /** The tablet drawer holding the rail and channels. */
  drawer: Accessor<boolean>
  setDrawer: Setter<boolean>
  openCreate: () => void
  /** A short, calm notice at the bottom of the screen (for example, removed from a group). */
  notify: (text: string) => void
}

export const ShellContext = createContext<Shell>()

export function useShell(): Shell {
  const shell = useContext(ShellContext)
  if (!shell) throw new Error('useShell outside the groups shell')
  return shell
}

export type GroupScope = {
  detail: Accessor<GroupDetail>
  setDetail: Setter<GroupDetail>
  /** Refetches the group's channels, members and invites. */
  refresh: () => Promise<void>
  openInvite: () => void
  /** Whether the member column is shown where it fits (1536px and up). */
  membersOpen: Accessor<boolean>
  setMembersOpen: Setter<boolean>
  /** Shows the members: the column where it fits, else the members sheet. */
  openMembers: () => void
  /** The members button: toggles the column where it fits, else opens the sheet. */
  toggleMembers: () => void
  /** Runs a leave or delete you started, so its own "removed" event is not announced to you. */
  leaving: (action: () => Promise<void>) => Promise<void>
}

export const GroupContext = createContext<GroupScope>()

export function useGroup(): GroupScope {
  const scope = useContext(GroupContext)
  if (!scope) throw new Error('useGroup outside a group')
  return scope
}

// Moved to lib so Home can poll too (SCR-008); the groups screens import it from here.
export { useVisiblePoll } from '../../lib/visible-poll'

/** Collapses a burst of calls into one, `ms` after the last. */
export function debounced(action: () => unknown, ms: number): () => void {
  let timer: number | undefined
  onCleanup(() => window.clearTimeout(timer))
  return () => {
    window.clearTimeout(timer)
    timer = window.setTimeout(() => void action(), ms)
  }
}

// Its own module, so a page that only shows people (the Board) does not load the menu below.
export { Monogram } from './Monogram'

/** A mention count pill; nothing at zero. */
export function MentionPill(props: { count: number; label?: string }) {
  return (
    <Show when={props.count > 0}>
      <span
        class="min-w-5 rounded-full bg-danger px-1.5 text-center text-[11px] leading-5 font-semibold text-paper tabular-nums"
        aria-label={props.label ?? `${props.count} mentions`}
      >
        {badgeText(props.count)}
      </span>
    </Show>
  )
}

/**
 * A small menu behind a trigger (WEB-003): shadcn-solid's DropdownMenu, so focus, arrow keys,
 * Escape and outside clicks behave like every other menu. Picking an item closes it.
 */
export function Menu(props: {
  /** The trigger's accessible name when its content is not text. */
  label?: string
  title?: string
  trigger: JSX.Element
  triggerClass: string
  placement?: 'bottom-start' | 'bottom-end' | 'top-start' | 'top-end'
  class?: string
  /** As the menu closes; `preventDefault()` keeps focus off the trigger (an item moved it). */
  onCloseAutoFocus?: (event: Event) => void
  children: JSX.Element
}) {
  return (
    <DropdownMenu placement={props.placement ?? 'bottom-end'}>
      <DropdownMenuTrigger
        aria-label={props.label}
        title={props.title}
        class={`group/menu-trigger ${props.triggerClass}`}
      >
        {props.trigger}
      </DropdownMenuTrigger>
      <DropdownMenuPortal>
        <DropdownMenuContent
          onCloseAutoFocus={(event: Event) => props.onCloseAutoFocus?.(event)}
          class={`min-w-48 rounded-2xl border-line bg-paper py-1 text-sm text-ink shadow-xl ${props.class ?? ''}`}
        >
          {props.children}
        </DropdownMenuContent>
      </DropdownMenuPortal>
    </DropdownMenu>
  )
}

export function MenuItem(props: {
  onSelect: () => void
  danger?: boolean
  children: JSX.Element
}) {
  return (
    <DropdownMenuItem
      onSelect={() => props.onSelect()}
      variant={props.danger ? 'destructive' : 'default'}
      class="block cursor-pointer rounded-none px-4 py-2 data-[highlighted]:bg-surface data-[highlighted]:text-ink data-[variant=destructive]:data-[highlighted]:bg-danger/10"
    >
      {props.children}
    </DropdownMenuItem>
  )
}

export function MenuSeparator() {
  return <DropdownMenuSeparator class="mx-0 bg-line" />
}
