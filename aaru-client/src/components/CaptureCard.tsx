import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { captureHeadline } from '../lib/capture/model'
import { stateLabel } from '../lib/imports/model'
import type { ImportJob } from '../lib/imports/server'
import { AgentPresence } from './AgentPresence'

// AG-006: a capture waiting under "Waiting for you", beside agents' requests. While Aaru reads
// it, the owl; once planned, what it adds and what needs a pick. The review is the import page.
export function CaptureCard(props: { job: ImportJob }) {
  return (
    <Link
      to="/app/imports/$id"
      params={{ id: props.job.id }}
      class="edge-lit block rounded-card bg-surface p-5 hover:bg-surface/80"
    >
      <span class="flex items-center gap-2 eyebrow">
        <span class="size-1.5 rounded-full bg-gold" aria-hidden="true" />
        Your capture
      </span>
      <Show
        when={captureHeadline(props.job)}
        fallback={<AgentPresence label={stateLabel(props.job)} class="mt-2" />}
      >
        {(headline) => (
          <>
            <span class="mt-1 block font-display text-xl font-medium">
              {headline()}
            </span>
            <span class="mt-1 block text-sm text-muted">
              Nothing changes until you approve · Review
            </span>
          </>
        )}
      </Show>
    </Link>
  )
}
