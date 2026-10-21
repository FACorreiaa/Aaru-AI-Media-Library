import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import {
  isWorking,
  progressShare,
  sourceLabel,
  stateLabel,
} from '../lib/imports/model'
import type { ImportJob } from '../lib/imports/server'
import { AgentPresence } from './AgentPresence'

// The Field's last import, collapsed (DESIGN.md §1, VIEWS.md `JobLedger`): the source, where it
// stands, and the way into its ledger. The whole ledger lives on the import's own page.
export function LastImportCard(props: { job: ImportJob }) {
  const job = () => props.job
  const share = () => progressShare(job())
  return (
    <Link
      to="/app/imports/$id"
      params={{ id: job().id }}
      class="block rounded-panel border border-line bg-surface/70 p-4 hover:border-line-strong"
    >
      <span class="eyebrow">Last import</span>
      <span class="mt-1 block truncate font-medium">
        {job().filename ?? sourceLabel(job())}
      </span>
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
  )
}
