import { For, Show } from 'solid-js'
import tmdbLogo from '../assets/brand/tmdb-blue-short.svg'
import { CREDITS, TMDB_NOTICE, TMDB_URL } from '../lib/credits'

const link =
  'font-medium text-accent underline underline-offset-2 hover:no-underline'

/**
 * Provider credits (PRV-001). TMDB's logo stays small: its terms require it to be less
 * prominent than Aaru's own mark.
 */
export function Credits() {
  return (
    <div class="space-y-4">
      <div class="flex flex-wrap items-center gap-4">
        <a href={TMDB_URL} rel="noopener" class="shrink-0">
          <img
            src={tmdbLogo}
            alt="TMDB"
            width="273"
            height="36"
            class="h-3.5 w-auto"
          />
        </a>
        <p class="min-w-0 flex-1 text-sm leading-relaxed text-muted">
          {TMDB_NOTICE}
        </p>
      </div>
      <ul class="space-y-2 text-sm text-muted">
        <For each={CREDITS}>
          {(credit) => (
            <li>
              {credit.lead}
              <a href={credit.href} rel="noopener" class={link}>
                {credit.name}
              </a>
              <Show when={credit.licence}>
                {(licence) => (
                  <>
                    {', '}
                    <a href={licence().href} rel="noopener" class={link}>
                      {licence().name}
                    </a>
                  </>
                )}
              </Show>
            </li>
          )}
        </For>
      </ul>
    </div>
  )
}
