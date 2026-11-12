import { createFileRoute } from '@tanstack/solid-router'
import support from '../../../docs/support.md?raw'
import { LegalPage } from '../components/LegalPage'
import { Prose } from '../components/Prose'
import { parseMarkdown } from '../lib/markdown'

// docs/support.md is the support page; this route only renders it, as /privacy and /terms do.
// It is the Support URL of the App Store listing. The doc links its siblings by file name.
const blocks = parseMarkdown(
  support
    .replace('](terms.md)', '](/terms)')
    .replace('](privacy.md)', '](/privacy)'),
)

export const Route = createFileRoute('/support')({
  head: () => ({
    meta: [
      { title: 'Support · Aaru' },
      {
        name: 'description',
        content:
          'How to reach Aaru, and how to sign in, export your data, delete your account and report someone.',
      },
    ],
  }),
  component: Support,
})

function Support() {
  return (
    <LegalPage>
      <article>
        <Prose blocks={blocks} />
      </article>
    </LegalPage>
  )
}
