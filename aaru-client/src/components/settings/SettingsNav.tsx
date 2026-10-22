import { Link, useLocation } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import { BackIcon } from '../shell/icons'
import { cn } from '~/lib/utils'

export type SettingsPage = {
  to:
    | '/app/settings/account'
    | '/app/settings/friends'
    | '/app/settings/notifications'
    | '/app/settings/import'
    | '/app/settings/connections'
    | '/app/settings/data'
    | '/app/settings/about'
    | '/app/settings/delete'
  label: string
  hint: string
  danger?: boolean
}

/** DESIGN.md §18: the eight pages, in this order, on every platform. */
export const SETTINGS_PAGES: SettingsPage[] = [
  {
    to: '/app/settings/account',
    label: 'Account',
    hint: 'Name and handle, how you sign in, appearance',
  },
  {
    to: '/app/settings/friends',
    label: 'Friends & privacy',
    hint: 'Friends, requests, blocks and your location',
  },
  {
    to: '/app/settings/notifications',
    label: 'Notifications',
    hint: 'New episodes, mentions and group invites',
  },
  {
    to: '/app/settings/import',
    label: 'Import',
    hint: 'Trakt, Stremio history, files and your imports',
  },
  {
    to: '/app/settings/connections',
    label: 'Connections',
    hint: 'Agents, the Stremio addon and music scrobblers',
  },
  {
    to: '/app/settings/data',
    label: 'Your data',
    hint: 'Recaps, history with undo, and export',
  },
  {
    to: '/app/settings/about',
    label: 'About',
    hint: 'Version, credits and privacy',
  },
  {
    to: '/app/settings/delete',
    label: 'Delete account',
    hint: 'Your account and library, for good',
    danger: true,
  },
]

const trimmed = (path: string) => path.replace(/\/+$/, '')

/** True on `/app/settings` itself, where a phone shows the list of pages. */
export function useSettingsIndex() {
  const location = useLocation()
  return () => trimmed(location().pathname) === '/app/settings'
}

/** The sub-nav beside a Settings page, from 768px. Delete account sits last, after a rule. */
export function SettingsRail() {
  const location = useLocation()
  const current = (to: string) => trimmed(location().pathname) === to
  return (
    <nav aria-label="Settings" class="hidden md:block">
      <ul class="sticky top-6 flex flex-col gap-0.5 text-sm font-medium">
        <For each={SETTINGS_PAGES}>
          {(page) => (
            <li class={cn(page.danger && 'mt-3 border-t border-line pt-3')}>
              <Link
                to={page.to}
                class={cn(
                  'block rounded-full px-3 py-2 hover:bg-surface',
                  page.danger ? 'text-danger' : 'text-muted hover:text-ink',
                  current(page.to) && 'bg-surface',
                  current(page.to) && !page.danger && 'text-ink',
                )}
                aria-current={current(page.to) ? 'page' : undefined}
              >
                {page.label}
              </Link>
            </li>
          )}
        </For>
      </ul>
    </nav>
  )
}

/** A phone's Settings: one row per page with its hint line. */
export function SettingsList() {
  return (
    <nav aria-label="Settings" class="md:hidden">
      <ul class="divide-y divide-line overflow-hidden rounded-card bg-surface">
        <For each={SETTINGS_PAGES}>
          {(page) => (
            <li>
              <Link
                to={page.to}
                class="flex min-h-14 items-center justify-between gap-4 px-4 py-3 hover:bg-stone/50"
              >
                <span class="min-w-0">
                  <span
                    class={cn(
                      'block font-medium',
                      page.danger && 'text-danger',
                    )}
                  >
                    {page.label}
                  </span>
                  <span class="block text-sm text-muted">{page.hint}</span>
                </span>
                <span aria-hidden="true" class="shrink-0 text-xl text-muted">
                  ›
                </span>
              </Link>
            </li>
          )}
        </For>
      </ul>
    </nav>
  )
}

/** A Settings page's title; on a phone it also leads back to the list ("‹ Settings"). */
export function SettingsPageTitle(props: {
  title: string
  description?: string
}) {
  return (
    <div class="mb-6">
      <Link
        to="/app/settings"
        class="-ml-1 inline-flex min-h-11 items-center gap-1 text-sm font-medium text-muted hover:text-ink md:hidden"
      >
        <BackIcon class="size-4" />
        Settings
      </Link>
      <h2 class="font-display text-2xl font-medium md:mt-1">{props.title}</h2>
      {/* eslint-disable-next-line no-restricted-syntax -- a string, not a JSX slot */}
      <Show when={props.description}>
        <p class="mt-1 max-w-prose text-sm text-muted">{props.description}</p>
      </Show>
    </div>
  )
}
