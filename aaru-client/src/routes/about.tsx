import { Link, createFileRoute } from '@tanstack/solid-router'
import { Credits } from '../components/Credits'
import { LegalPage } from '../components/LegalPage'
import { CONTACT_EMAIL } from '../lib/credits'

export const Route = createFileRoute('/about')({
  head: () => ({
    meta: [
      { title: 'About · Aaru' },
      {
        name: 'description',
        content:
          'Aaru is a private library for films, shows, anime and books. Credits for the catalog data it uses.',
      },
    ],
  }),
  component: About,
})

const link =
  'font-medium text-accent underline underline-offset-2 hover:no-underline'

function About() {
  return (
    <LegalPage>
      <h1 class="font-display text-4xl leading-tight font-medium tracking-tight text-balance">
        About Aaru
      </h1>
      <p class="mt-4 leading-relaxed text-muted">
        Aaru keeps everything you watch and read on one shelf: films, shows,
        anime and books in one calm library, with four plain statuses. It is
        private by default, with no public profile and no ads. The name comes
        from the Egyptian Field of Reeds, a calm place where stories live.
      </p>

      <h2
        id="credits"
        class="mt-10 scroll-mt-6 font-display text-2xl font-medium"
      >
        Credits
      </h2>
      <p class="mt-4 mb-5 leading-relaxed text-muted">
        Titles, artwork and schedules come from these catalogs. Thank you.
      </p>
      <Credits />

      <h2 class="mt-10 font-display text-2xl font-medium">
        Privacy and contact
      </h2>
      <p class="mt-4 leading-relaxed text-muted">
        Read the{' '}
        <Link to="/privacy" class={link}>
          privacy policy
        </Link>{' '}
        for what Aaru stores and how to delete it. Questions:{' '}
        <a href={`mailto:${CONTACT_EMAIL}`} class={link}>
          {CONTACT_EMAIL}
        </a>
        .
      </p>
    </LegalPage>
  )
}
