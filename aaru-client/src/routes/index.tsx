import { Link, createFileRoute } from '@tanstack/solid-router'
import { For } from 'solid-js'
import { MascotMedallion, Wordmark } from '../components/Brand'
import { ImportSources } from '../components/ImportSources'
import { KindCard } from '../components/KindCard'
import { LegalLinks } from '../components/LegalPage'
import { PosterFan } from '../components/PosterFan'
import { StoreButtons } from '../components/StoreButtons'
import { FAN, KIND_CARDS } from '../lib/landing/art'
import { SITE_URL, X_URL } from '../lib/site'
import appIcon from '../assets/brand/app-icon.webp'
import tmdbLogo from '../assets/brand/tmdb-blue-short.svg'

const title = 'Aaru · One private shelf for everything you follow'
const description =
  'Track TV shows, movies, anime, books, music and sports in one private library. Import from Trakt, IMDb, Letterboxd and Goodreads. No ads, no tracking.'

// LAND-001: static marketing page. It never reads the session.
export const Route = createFileRoute('/')({
  head: () => ({
    meta: [
      { title },
      { name: 'description', content: description },
      { property: 'og:type', content: 'website' },
      { property: 'og:title', content: title },
      { property: 'og:description', content: description },
      { property: 'og:image', content: `${SITE_URL}/og.jpg` },
      { name: 'twitter:card', content: 'summary_large_image' },
      { name: 'twitter:site', content: '@fatc88' },
    ],
  }),
  component: Landing,
})

const faqs: Array<[string, string]> = [
  [
    'Is my library public?',
    'No. Everything is private. Sharing, when it arrives, is opt-in and friends only.',
  ],
  [
    'Can I take my data out?',
    'Yes. Export your whole library any time from Settings, as JSON or a CSV spreadsheet that imports back into Aaru. Export will never be a paid feature.',
  ],
  [
    'Where can I import from?',
    'Trakt, IMDb, Letterboxd, Goodreads, TV Time, MyAnimeList, AniList and a Pogdesign CAT show list.',
  ],
  [
    'Does it handle anime properly?',
    'Yes. Anime is first-class, with AniList and MyAnimeList ids and episode-level progress.',
  ],
  [
    'When can I use it?',
    'Aaru is in private beta on iPhone, Mac and the web. The App Store and Google Play releases follow once testers have used it end to end.',
  ],
  [
    'What will it cost?',
    'Pricing is not final. Your library, your export and your statistics will never sit behind a paywall.',
  ],
]

function XIcon(props: { class?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      class={props.class ?? 'h-4 w-4'}
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z" />
    </svg>
  )
}

function Landing() {
  return (
    <>
      <header class="mx-auto flex h-18 max-w-6xl items-center justify-between px-5 md:px-8">
        <Wordmark />
        <nav class="flex items-center gap-6 text-sm font-medium text-muted">
          <a
            href="#kinds"
            class="hidden transition-colors hover:text-ink md:inline"
          >
            What you track
          </a>
          <a
            href="#how"
            class="hidden transition-colors hover:text-ink sm:inline"
          >
            How it works
          </a>
          <a
            href="#faq"
            class="hidden transition-colors hover:text-ink sm:inline"
          >
            FAQ
          </a>
          <a
            href={X_URL}
            target="_blank"
            rel="me noopener"
            aria-label="Aaru on X"
            class="transition-colors hover:text-ink"
          >
            <XIcon />
          </a>
          <Link
            to="/sign-in"
            class="text-ink transition-colors hover:text-accent"
          >
            Sign in
          </Link>
        </nav>
      </header>

      <main>
        <section class="overflow-hidden">
          <div class="mx-auto flex max-w-4xl flex-col items-center px-5 pt-10 text-center md:px-8 md:pt-16">
            <a
              href="#kinds"
              class="rise inline-flex items-center gap-2 rounded-full border border-line bg-surface/70 px-4 py-1.5 text-sm font-medium text-muted transition-colors hover:text-ink"
            >
              <span class="h-1.5 w-1.5 rounded-full bg-accent" />
              Private by default. No ads, no feed.
            </a>
            <h1
              class="rise mt-7 font-display text-[2.5rem] leading-[1.05] font-medium tracking-tight text-balance md:text-6xl lg:text-[4.25rem]"
              style={{ '--delay': '60ms' }}
            >
              Everything you watch, read and follow.
              <span class="block text-accent">One calm shelf.</span>
            </h1>
            <p
              class="rise mt-6 max-w-[48ch] text-lg leading-relaxed text-muted"
              style={{ '--delay': '120ms' }}
            >
              TV shows, movies, anime, books, music and sports in one private
              library. Bring your history, leave whenever you like.
            </p>
            <div
              class="rise mt-9 flex flex-col items-center gap-5"
              style={{ '--delay': '180ms' }}
            >
              <Link
                to="/sign-in"
                class="inline-flex items-center rounded-full bg-accent px-7 py-3.5 text-base font-semibold whitespace-nowrap text-on-accent shadow-[0_8px_24px_-12px_rgb(31_105_112/0.6)] transition-transform hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98]"
              >
                Get started on the web
              </Link>
              <StoreButtons align="center" />
            </div>
          </div>
          <div class="mt-12 md:mt-16">
            <PosterFan covers={FAN} />
          </div>
        </section>

        <section
          id="kinds"
          class="mx-auto max-w-6xl scroll-mt-6 px-5 py-20 md:px-8 md:py-24"
        >
          <h2 class="max-w-[22ch] font-display text-3xl leading-tight font-medium tracking-tight md:text-5xl">
            All of it, on one shelf.
          </h2>
          <p class="mt-4 max-w-[52ch] text-lg leading-relaxed text-muted">
            One search, one library and four plain statuses for everything you
            follow.
          </p>
          <div class="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            <For each={KIND_CARDS}>{(kind) => <KindCard kind={kind} />}</For>
          </div>
        </section>

        <section id="how" class="scroll-mt-6 bg-surface">
          <div class="mx-auto max-w-6xl px-5 py-20 md:px-8 md:py-24">
            <h2 class="max-w-[22ch] font-display text-3xl leading-tight font-medium tracking-tight md:text-5xl">
              Bring your history with you.
            </h2>
            <p class="mt-4 max-w-[52ch] text-lg leading-relaxed text-muted">
              Import from the services you already use. Export everything, any
              time, for free.
            </p>
            <div class="mt-10">
              <ImportSources />
            </div>
          </div>
        </section>

        <section class="mx-auto max-w-3xl px-5 py-24 text-center md:px-8 md:py-32">
          <img
            src={appIcon}
            alt=""
            width="512"
            height="512"
            loading="lazy"
            class="mx-auto h-28 w-28 rounded-[22.5%] shadow-[0_18px_40px_-18px_rgb(19_80_90/0.55)] md:h-32 md:w-32"
          />
          <h2 class="mt-10 font-display text-3xl leading-tight font-medium tracking-tight md:text-5xl">
            Made for iPhone, iPad, Mac and the web
          </h2>
          <p class="mx-auto mt-4 max-w-[46ch] text-lg leading-relaxed text-muted">
            Native apps with widgets for what is next, a web app on the same
            library, and Android to follow.
          </p>
          <StoreButtons class="mt-9" align="center" />
        </section>

        <section id="faq" class="scroll-mt-6 border-t border-line">
          <div class="mx-auto grid max-w-6xl gap-10 px-5 py-20 md:grid-cols-[1fr_2fr] md:px-8 md:py-24">
            <h2 class="font-display text-3xl font-medium tracking-tight md:text-4xl">
              Questions
            </h2>
            <div class="flex flex-col gap-3">
              <For each={faqs}>
                {([question, answer]) => (
                  <details class="group rounded-[20px] bg-surface px-6 py-5 open:pb-6">
                    <summary class="flex cursor-pointer list-none items-center justify-between gap-6 text-lg font-medium [&::-webkit-details-marker]:hidden">
                      {question}
                      <span
                        aria-hidden="true"
                        class="text-2xl leading-none text-muted transition-transform group-open:rotate-45"
                      >
                        +
                      </span>
                    </summary>
                    <p class="mt-3 max-w-[60ch] leading-relaxed text-muted">
                      {answer}
                    </p>
                  </details>
                )}
              </For>
            </div>
          </div>
        </section>
      </main>

      <footer class="border-t border-line">
        <div class="mx-auto flex max-w-6xl flex-col gap-6 px-5 py-10 text-sm text-muted md:px-8">
          <div class="flex flex-col items-start justify-between gap-4 md:flex-row md:items-center">
            <div class="flex items-center gap-3">
              <MascotMedallion class="w-12 shrink-0" />
              <span>A calm place where stories live.</span>
            </div>
            <div class="flex items-center gap-4">
              <LegalLinks />
              <a
                href={X_URL}
                target="_blank"
                rel="me noopener"
                class="inline-flex items-center gap-1.5 hover:text-ink"
              >
                <XIcon class="h-3.5 w-3.5" />
                @fatc88
              </a>
              <span>© {new Date().getFullYear()} Aaru</span>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-3 text-xs">
            <img
              src={tmdbLogo}
              alt="TMDB"
              width="273"
              height="36"
              class="h-3 w-auto"
            />
            <span>
              Artwork from TMDB, Open Library and the Cover Art Archive. Not
              endorsed or certified by TMDB.
            </span>
          </div>
        </div>
      </footer>
    </>
  )
}
