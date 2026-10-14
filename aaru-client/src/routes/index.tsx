import { Link, createFileRoute } from '@tanstack/solid-router'
import { For } from 'solid-js'
import { MascotMedallion, Wordmark } from '../components/Brand'
import { ImportSources } from '../components/ImportSources'
import { SITE_URL } from '../lib/site'
import reedMark from '../assets/brand/reed-mark.webp'
import appIcon from '../assets/brand/app-icon.webp'

const title = 'Aaru · A private shelf for films, shows, anime and books'
const description =
  'Track films, shows, anime and books in one private library. Import from Trakt, IMDb, Letterboxd and Goodreads. Export any time.'

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
    ],
  }),
  component: Landing,
})

const statuses = ['Wishlist', 'In progress', 'Finished', 'Dropped']

const faqs: Array<[string, string]> = [
  [
    'Is my library public?',
    'No. Everything is private. Sharing, when it arrives, is opt-in and friends only.',
  ],
  [
    'Can I take my data out?',
    'Yes. You can export your whole library as CSV or JSON at any time, and export will never be a paid feature.',
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
    'Aaru is in private beta on iPhone, Mac and the web. The App Store release follows once testers have used it end to end.',
  ],
  [
    'What will it cost?',
    'Pricing is not final. Your library, your export and your statistics will never sit behind a paywall.',
  ],
]

function Landing() {
  return (
    <>
      <header class="mx-auto flex h-18 max-w-6xl items-center justify-between px-5 md:px-8">
        <Wordmark />
        <nav class="flex items-center gap-6 text-sm font-medium text-muted">
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
          <Link
            to="/sign-in"
            class="text-ink transition-colors hover:text-accent"
          >
            Sign in
          </Link>
        </nav>
      </header>

      <main>
        <section class="mx-auto grid max-w-6xl items-center gap-10 px-5 pt-6 pb-16 md:grid-cols-[1.05fr_0.95fr] md:px-8 md:pt-10 md:pb-24">
          <div class="order-2 md:order-1">
            <h1 class="rise max-w-[14ch] font-display text-[2.6rem] leading-[1.05] font-medium tracking-tight text-balance md:text-6xl lg:text-[4.25rem]">
              Everything you watch and read, on one shelf.
            </h1>
            <p
              class="rise mt-6 max-w-[46ch] text-lg leading-relaxed text-muted"
              style={{ '--delay': '80ms' }}
            >
              Track films, shows, anime and books in one calm library. Private
              by default. Bring your history, leave whenever you like.
            </p>
            <div
              class="rise mt-9 flex flex-wrap items-center gap-x-6 gap-y-4"
              style={{ '--delay': '160ms' }}
            >
              <Link
                to="/sign-in"
                class="inline-flex items-center rounded-full bg-accent px-6 py-3.5 text-base font-semibold whitespace-nowrap text-on-accent shadow-[0_8px_24px_-12px_rgb(31_105_112/0.6)] transition-transform hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.98]"
              >
                Get started
              </Link>
              <span class="text-sm font-medium text-muted">
                In private beta on the web, iPhone and Mac
              </span>
            </div>
          </div>
          <div
            class="rise order-1 flex justify-center md:order-2"
            style={{ '--delay': '120ms' }}
          >
            <MascotMedallion class="w-[min(78vw,30rem)]" priority />
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

        <section class="mx-auto max-w-6xl px-5 py-20 md:px-8 md:py-28">
          <div class="grid gap-5 md:grid-cols-5 md:grid-rows-2">
            <article class="relative flex min-h-[22rem] flex-col justify-between overflow-hidden rounded-[28px] bg-[linear-gradient(160deg,#13505a_0%,#2f7c7f_45%,#e8cf9f_100%)] p-8 text-[#fbf6ec] md:col-span-3 md:row-span-2 md:p-10">
              <div class="relative z-10 max-w-[34ch]">
                <h3 class="font-display text-3xl leading-tight font-medium text-balance md:text-4xl">
                  One shelf for all of it
                </h3>
                <p class="mt-4 text-lg leading-relaxed text-[#fbf6ec]/85">
                  Films, shows, anime and books share one search, one library
                  and four plain statuses.
                </p>
              </div>
              <ul class="relative z-10 mt-10 flex flex-wrap gap-2">
                <For each={statuses}>
                  {(status) => (
                    <li class="rounded-full bg-[#0f2224]/35 px-4 py-2 text-sm font-medium text-[#fbf6ec] backdrop-blur-sm">
                      {status}
                    </li>
                  )}
                </For>
              </ul>
            </article>

            <article class="flex items-center gap-6 rounded-[28px] border border-line bg-paper p-8 md:col-span-2">
              <img
                src={reedMark}
                alt=""
                width="318"
                height="453"
                class="h-28 w-auto shrink-0"
              />
              <div>
                <h3 class="font-display text-2xl font-medium">
                  Private by default
                </h3>
                <p class="mt-2 leading-relaxed text-muted">
                  Nobody sees your shelf unless you invite them. No public
                  profile, no global feed, no ads.
                </p>
              </div>
            </article>

            <article class="rounded-[28px] bg-surface p-8 md:col-span-2">
              <h3 class="font-display text-2xl font-medium">
                Your week at a glance
              </h3>
              <p class="mt-2 leading-relaxed text-muted">
                Up next, air times and a week grid for the shows and anime you
                follow.
              </p>
            </article>
          </div>
        </section>

        <section class="mx-auto max-w-3xl px-5 pb-24 text-center md:px-8 md:pb-32">
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
            Native apps with widgets for what is next, and a web app on the same
            library.
          </p>
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
        <div class="mx-auto flex max-w-6xl flex-col items-start justify-between gap-4 px-5 py-10 text-sm text-muted md:flex-row md:items-center md:px-8">
          <div class="flex items-center gap-3">
            <img
              src={reedMark}
              alt=""
              width="318"
              height="453"
              class="h-11 w-auto"
            />
            <span>A calm place where stories live.</span>
          </div>
          <span>© {new Date().getFullYear()} Aaru</span>
        </div>
      </footer>
    </>
  )
}
