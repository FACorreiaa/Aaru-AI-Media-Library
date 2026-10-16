import { Link } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { Wordmark } from './Brand'

/** The footer links every public page carries: About · Privacy. */
export function LegalLinks(props: { class?: string }) {
  return (
    <nav aria-label="About Aaru" class={props.class ?? 'flex gap-4'}>
      <Link to="/about" class="hover:text-ink">
        About
      </Link>
      <Link to="/privacy" class="hover:text-ink">
        Privacy
      </Link>
    </nav>
  )
}

/** Public long-form page: wordmark, a readable measure, About · Privacy at the foot. */
export function LegalPage(props: { children: JSX.Element }) {
  return (
    <div class="min-h-[100dvh] bg-paper text-ink">
      <header class="mx-auto max-w-[36rem] px-5 pt-8 md:pt-12">
        <Wordmark class="h-8 w-auto" />
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
