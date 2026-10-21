import { Show, createContext, onCleanup, onMount, useContext } from 'solid-js'
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
  /** Whether the member column is shown on desktop. */
  membersOpen: Accessor<boolean>
  setMembersOpen: Setter<boolean>
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

/** A round monogram: groups in the rail, people in rows. */
export function Monogram(props: {
  text: string
  size?: 'sm' | 'md' | 'lg'
  class?: string
}) {
  const size = () =>
    props.size === 'lg'
      ? 'size-12 text-base'
      : props.size === 'sm'
        ? 'size-8 text-xs'
        : 'size-10 text-sm'
  return (
    <span
      aria-hidden="true"
      class={`grid shrink-0 place-items-center rounded-full bg-medallion/20 font-display font-medium ${size()} ${props.class ?? ''}`}
    >
      {props.text}
    </span>
  )
}

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

/** A small floating menu that closes on outside click or Escape. */
export function Menu(props: {
  open: boolean
  onClose: () => void
  class?: string
  children: JSX.Element
}) {
  let panel: HTMLDivElement | undefined
  onMount(() => {
    const onDown = (event: PointerEvent) => {
      if (props.open && panel && !panel.contains(event.target as Node))
        props.onClose()
    }
    const onKey = (event: KeyboardEvent) => {
      if (props.open && event.key === 'Escape') props.onClose()
    }
    document.addEventListener('pointerdown', onDown, true)
    document.addEventListener('keydown', onKey)
    onCleanup(() => {
      document.removeEventListener('pointerdown', onDown, true)
      document.removeEventListener('keydown', onKey)
    })
  })
  return (
    <Show when={props.open}>
      <div
        ref={panel}
        role="menu"
        class={`group-pop absolute z-50 min-w-48 overflow-hidden rounded-2xl border border-line bg-paper py-1 text-sm shadow-xl ${props.class ?? ''}`}
      >
        {props.children}
      </div>
    </Show>
  )
}

export function MenuItem(props: {
  onSelect: () => void
  danger?: boolean
  children: JSX.Element
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={() => props.onSelect()}
      class={`block w-full px-4 py-2 text-left hover:bg-surface ${props.danger ? 'text-danger' : ''}`}
    >
      {props.children}
    </button>
  )
}
