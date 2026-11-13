import { For } from 'solid-js'
import { Link } from '@tanstack/solid-router'
import { AI_SHARING } from '../../lib/ai-sharing/model'

/**
 * What Aaru sends its AI provider, and to whom (PRV-002): the one disclosure the first run, the
 * full-screen ask, the in-place ask and Settings all show. The heading and the buttons are the
 * caller's.
 */
export function AiSharingDisclosure(props: { class?: string }) {
  return (
    <div class={props.class}>
      <p class="text-base text-pretty">{AI_SHARING.lead}</p>
      <ul class="mt-3 flex list-disc flex-col gap-2 pl-5 text-sm text-pretty marker:text-muted">
        <For each={AI_SHARING.sent}>{(line) => <li>{line}</li>}</For>
      </ul>
      <p class="mt-4 text-sm text-pretty text-muted">{AI_SHARING.use}</p>
      <p class="mt-3 text-sm">
        <Link
          to="/privacy"
          target="_blank"
          class="font-medium underline underline-offset-4 hover:text-ink"
        >
          Privacy policy
        </Link>
      </p>
    </div>
  )
}
