import { Link, useLocation } from '@tanstack/solid-router'
import { For } from 'solid-js'

/** Settings' groups, in order. The same groups as the Apple apps' Settings list. */
export const SETTINGS_GROUPS = [
  {
    to: '/app/settings/account',
    label: 'Account',
    hint: 'Name, sign-in, friends, notifications, appearance and concerts',
  },
  {
    to: '/app/settings/imports',
    label: 'Imports & export',
    hint: 'Trakt, files, AniList, CAT, Stremio history and your data',
  },
  {
    to: '/app/settings/connected',
    label: 'Connected apps',
    hint: 'Stremio and agents',
  },
  {
    to: '/app/settings/recaps',
    label: 'Insights & recaps',
    hint: 'Your months and years as a story',
  },
  {
    to: '/app/settings/about',
    label: 'About',
    hint: 'Credits, privacy and deleting your account',
  },
] as const

const trimmed = (path: string) => path.replace(/\/+$/, '')

/** True on `/app/settings` itself, where a phone shows the group list. */
export function useSettingsIndex() {
  const location = useLocation()
  return () => trimmed(location().pathname) === '/app/settings'
}

/** The desktop rail. `/app/settings` shows Account beside it, so Account reads as current. */
export function SettingsRail() {
  const location = useLocation()
  const current = (to: string) => {
    const path = trimmed(location().pathname)
    return (
      path === to ||
      (to === '/app/settings/account' && path === '/app/settings')
    )
  }
  return (
    <nav aria-label="Settings" class="hidden md:block">
      <ul class="sticky top-6 flex flex-col gap-1 text-sm font-medium">
        <For each={SETTINGS_GROUPS}>
          {(group) => (
            <li>
              <Link
                to={group.to}
                class="block rounded-full px-3 py-1.5 text-muted hover:bg-surface hover:text-ink"
                classList={{ 'bg-surface !text-ink': current(group.to) }}
                aria-current={current(group.to) ? 'page' : undefined}
              >
                {group.label}
              </Link>
            </li>
          )}
        </For>
      </ul>
    </nav>
  )
}

/** A phone's Settings: one row per group, each opening its page. */
export function SettingsList() {
  return (
    <nav aria-label="Settings" class="md:hidden">
      <ul class="divide-y divide-line rounded-card bg-surface">
        <For each={SETTINGS_GROUPS}>
          {(group) => (
            <li>
              <Link
                to={group.to}
                class="flex min-h-14 items-center justify-between gap-4 px-4 py-3 hover:text-accent"
              >
                <span class="min-w-0">
                  <span class="block font-medium">{group.label}</span>
                  <span class="block text-sm text-muted">{group.hint}</span>
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

/** A Settings page's title; on a phone it also leads back to the group list. */
export function SettingsPageTitle(props: { title: string }) {
  return (
    <div>
      <Link
        to="/app/settings"
        class="inline-flex min-h-11 items-center text-sm font-medium text-muted hover:text-ink md:hidden"
      >
        ‹ Settings
      </Link>
      <h2 class="font-display text-2xl font-medium md:mt-1">{props.title}</h2>
    </div>
  )
}
