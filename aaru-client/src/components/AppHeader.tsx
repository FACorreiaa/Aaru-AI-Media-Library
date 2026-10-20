import { Link, useNavigate, useRouter } from '@tanstack/solid-router'
import { For, Show } from 'solid-js'
import { signOut } from '../lib/session/session'
import { Wordmark } from './Brand'

const DESTINATIONS = [
  { to: '/app', label: 'Home', exact: true },
  { to: '/app/discover', label: 'Discover', exact: false },
  { to: '/app/library', label: 'Library', exact: false },
  { to: '/app/week', label: 'Calendar', exact: false },
  { to: '/app/lists', label: 'Lists', exact: false },
  { to: '/app/settings', label: 'Settings', exact: false },
] as const

/**
 * The signed-in web app's navigation, the twin of the Apple apps' tabs and sidebar: Home,
 * Discover, Library, Calendar, Lists, Settings. Search opens in place where the page can host it
 * (`onSearch`), otherwise on the Library.
 */
export function AppHeader(props: { onSearch?: () => void; class?: string }) {
  const router = useRouter()
  const navigate = useNavigate()

  async function leave() {
    await signOut()
    await router.invalidate()
    await navigate({ to: '/' })
  }

  const searchClass =
    'rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent active:scale-[0.98]'

  return (
    <header class={`mx-auto px-4 md:px-8 ${props.class ?? 'max-w-6xl'}`}>
      <div class="flex h-16 items-center justify-between gap-4">
        <Wordmark />
        <div class="flex items-center gap-4 text-sm font-medium">
          <Show
            when={props.onSearch}
            fallback={
              <Link
                to="/app/library"
                search={{ search: true }}
                class={searchClass}
              >
                Search
              </Link>
            }
          >
            {(open) => (
              <button
                type="button"
                onClick={() => open()()}
                class={searchClass}
              >
                Search
              </button>
            )}
          </Show>
          <button
            type="button"
            onClick={leave}
            class="text-muted hover:text-ink"
          >
            Sign out
          </button>
        </div>
      </div>
      <nav
        aria-label="Aaru"
        class="-mx-4 flex gap-1 overflow-x-auto px-4 pb-2 text-sm font-medium md:mx-0 md:px-0"
      >
        <For each={DESTINATIONS}>
          {(d) => (
            <Link
              to={d.to}
              activeOptions={{ exact: d.exact, includeSearch: false }}
              class="shrink-0 rounded-full px-3 py-1.5 text-muted hover:bg-surface hover:text-ink"
              activeProps={{
                class: 'bg-surface !text-ink',
                'aria-current': 'page',
              }}
            >
              {d.label}
            </Link>
          )}
        </For>
      </nav>
    </header>
  )
}
