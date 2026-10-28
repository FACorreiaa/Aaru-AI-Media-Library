import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { cardClass } from '~/components/ui'
import { cn } from '~/lib/utils'
import {
  isWorking,
  progressShare,
  sourceLabel,
  stateLabel,
} from '../lib/imports/model'
import type { ImportJob } from '../lib/imports/server'
import { AgentPresence } from './AgentPresence'

// The Field's last import, collapsed (DESIGN.md §1, VIEWS.md `JobLedger`): the source, where it
// stands, and the way into its ledger. The whole ledger, file name included, lives on the
// import's own page. The side column's one recipe: the label above, the card under it.
export function LastImportCard(props: { job: ImportJob }) {
  const job = () => props.job
  const share = () => progressShare(job())
  return (
    <section aria-labelledby="home-last-import">
      <h2 id="home-last-import" class="eyebrow">
        Last import
      </h2>
      <Link
        to="/app/imports/$id"
        params={{ id: job().id }}
        class={cn(cardClass, 'mt-3 block px-5 py-4 hover:border-line-strong')}
      >
        <span class="block truncate font-medium">{importName(job())}</span>
        <Show
          when={isWorking(job())}
          fallback={
            <span
              class="mt-0.5 block text-sm"
              classList={{
                'text-danger': job().state === 'failed',
                'text-muted': job().state !== 'failed',
                '!text-accent font-medium': job().state === 'planned',
              }}
            >
              {stateLabel(job())}
            </span>
          }
        >
          <AgentPresence label={stateLabel(job())} class="mt-1" />
          <Show when={share()}>
            {(value) => (
              <span
                class="mt-2 block h-1 overflow-hidden rounded-full bg-line"
                aria-hidden="true"
              >
                <span
                  class="block h-full rounded-full bg-gold"
                  style={{ width: `${Math.round(value() * 100)}%` }}
                />
              </span>
            )}
          </Show>
        </Show>
      </Link>
    </section>
  )
}

/** "From MyAnimeList", "From a CSV file": the source, never a raw file name. */
function importName(job: ImportJob): string {
  return job.source === 'csv' ? 'From a CSV file' : `From ${sourceLabel(job)}`
}
