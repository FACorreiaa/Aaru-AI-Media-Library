import { createFileRoute } from '@tanstack/solid-router'
import policy from '../../../docs/privacy.md?raw'
import { LegalPage } from '../components/LegalPage'
import { Prose } from '../components/Prose'
import { parseMarkdown } from '../lib/markdown'

// LAND-003: docs/privacy.md is the policy; this page only renders it, so the two never drift.
const blocks = parseMarkdown(policy)

export const Route = createFileRoute('/privacy')({
  head: () => ({
    meta: [
      { title: 'Privacy policy · Aaru' },
      {
        name: 'description',
        content:
          'What Aaru stores, who else sees any of it, and how to delete it. No ads, no tracking.',
      },
    ],
  }),
  component: Privacy,
})

function Privacy() {
  return (
    <LegalPage>
      <article>
        <Prose blocks={blocks} />
      </article>
    </LegalPage>
  )
}
