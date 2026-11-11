import { Link } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { Show } from 'solid-js'
import { Wordmark } from './Brand'
import { BackIcon } from './shell/icons'
import { useSignedIn } from '../lib/session/use-signed-in'

/** The footer links every public page carries: About · Privacy · Terms. */
export function LegalLinks(props: { class?: string }) {
  return (
    <nav aria-label="About Aaru" class={props.class ?? 'flex gap-4'}>
      <Link to="/about" class="py-3 hover:text-ink md:py-0">
        About
      </Link>
      <Link to="/privacy" class="py-3 hover:text-ink md:py-0">
        Privacy
      </Link>
      <Link to="/terms" class="py-3 hover:text-ink md:py-0">
        Terms
      </Link>
    </nav>
  )
}

/** Public long-form page: wordmark, a readable measure, About · Privacy · Terms at the foot. */
export function LegalPage(props: { children: JSX.Element }) {
  // UX-014: opened from Settings → About, the page leads back into the app.
  const signedIn = useSignedIn()
  return (
    <div class="min-h-[100dvh] bg-paper text-ink">
      <header class="mx-auto flex max-w-[36rem] items-center justify-between gap-4 px-5 pt-8 md:pt-12">
        <Wordmark class="h-8 w-auto" to={signedIn() ? '/app' : '/'} />
        <Show when={signedIn()}>
          <Link
            to="/app/settings/about"
            class="flex items-center gap-1 text-sm font-medium text-muted hover:text-ink"
          >
            <BackIcon class="size-4" />
            Settings
          </Link>
        </Show>
      </header>
      <main class="mx-auto max-w-[36rem] px-5 pt-10 pb-16 break-words">
        {props.children}
      </main>
      <footer class="border-t border-line">
        <div class="mx-auto flex max-w-[36rem] flex-wrap items-center justify-between gap-4 px-5 py-8 text-sm text-muted">
          <span>© {new Date().getFullYear()} Aaru</span>
          <LegalLinks />
        </div>
      </footer>
    </div>
  )
}
