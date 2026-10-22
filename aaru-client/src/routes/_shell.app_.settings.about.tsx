import { Link, createFileRoute } from '@tanstack/solid-router'
import { Credits } from '../components/Credits'
import { Wordmark } from '../components/Brand'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { SettingsSection } from '../components/settings/SettingsSection'
import { CONTACT_EMAIL } from '../lib/credits'

// Settings → About (DESIGN.md §18): the wordmark, credits, and the public pages, which lead
// back here while you are signed in (UX-014).
export const Route = createFileRoute('/_shell/app_/settings/about')({
  head: () => ({ meta: [{ title: 'About · Settings · Aaru' }] }),
  component: About,
})

const link = 'font-semibold text-accent hover:underline'

function About() {
  return (
    <>
      <SettingsPageTitle title="About" />
      <SettingsSection title="Aaru">
        <Wordmark to="/app" class="h-9 w-auto" />
        <p class="mt-3 max-w-prose text-sm text-muted">
          A calm place for the films, shows, anime, books and albums you watch,
          read and listen to. Private by default.
        </p>
      </SettingsSection>
      <SettingsSection title="Credits">
        <Credits />
      </SettingsSection>
      <SettingsSection title="More">
        <ul class="flex flex-wrap gap-x-6 gap-y-2 text-sm">
          <li>
            <Link to="/privacy" class={link}>
              Privacy policy
            </Link>
          </li>
          <li>
            <Link to="/about" class={link}>
              About Aaru
            </Link>
          </li>
          <li>
            <a href={`mailto:${CONTACT_EMAIL}`} class={link}>
              Contact
            </a>
          </li>
        </ul>
      </SettingsSection>
    </>
  )
}
