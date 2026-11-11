import { createFileRoute } from '@tanstack/solid-router'
import terms from '../../../docs/terms.md?raw'
import { LegalPage } from '../components/LegalPage'
import { Prose } from '../components/Prose'
import { parseMarkdown } from '../lib/markdown'

// LAND-003: docs/terms.md is the terms; this page only renders it, so the two never drift.
// The doc links its sibling by file name; on the site that page is /privacy.
const blocks = parseMarkdown(terms.replace('](privacy.md)', '](/privacy)'))

export const Route = createFileRoute('/terms')({
  head: () => ({
    meta: [
      { title: 'Terms of use · Aaru' },
      {
        name: 'description',
        content:
          'The plain rules for using Aaru: who can use it, what you keep, what Aaru expects, and how to leave.',
      },
    ],
  }),
  component: Terms,
})

function Terms() {
  return (
    <LegalPage>
      <article>
        <Prose blocks={blocks} />
      </article>
    </LegalPage>
  )
}
