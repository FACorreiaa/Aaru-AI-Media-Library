import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import { Match, Show, Switch, createSignal, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { Wordmark } from '../components/Brand'
import { Poster } from '../components/Poster'
import { SportBadge } from '../components/sports/SportBadge'
import { Button, buttonVariants } from '~/components/ui'
import { cn } from '~/lib/utils'
import { localDayKey } from '../lib/calendar/model'
import { placeLine as concertPlace } from '../lib/concerts/model'
import type { Concert } from '../lib/concerts/model'
import { kindName, kindOf, statusLabel } from '../lib/library/model'
import type { LibraryStatus } from '../lib/library/model'
import { addToLibrary } from '../lib/library/server'
import { addNext, shareDate, shouldAutoAdd } from '../lib/shares/model'
import type { SharePreview } from '../lib/shares/model'
import { rememberAdd, takeAdd } from '../lib/shares/pending-add'
import { loadShare } from '../lib/shares/server'
import { inviterName } from '../lib/social/model'
import {
  clockLabel,
  hasScore,
  isCard,
  placeLine,
  statusLabel as sportStatus,
  whenLine,
} from '../lib/sports/model'
import type { SportEvent } from '../lib/sports/model'
import { viewerTimeZone } from '../lib/timezone'

type TitleDetail = NonNullable<SharePreview['title']>

// SHR-002: a share link, aaruapp.com/s/{code}. Anyone who opens it sees the title, match or
// concert it points to; the sender and their note show only when the API sends `from`, which
// it does for the sender's friends alone. Signed in, one tap saves a title; signed out, "Add to
// my Aaru" goes through sign-in and back here with `?add=1`, which saves it once, and only in
// the browser that asked (`pending-add`).
export const Route = createFileRoute('/s/$code')({
  // `1`, not `true`: the router writes the value back into the address, and it must stay
  // `?add=1`, the one form `safeNext` lets sign-in return to.
  validateSearch: (search): { add?: 1 } => ({
    add: search.add === 1 || search.add === '1' ? 1 : undefined,
  }),
  loader: ({ params }) => loadShare({ data: { code: params.code } }),
  head: ({ loaderData }) => {
    const head = loaderData?.head
    const title = head?.title ?? 'Aaru'
    const description = head?.description ?? ''
    return {
      meta: [
        { title: `${title} · Aaru` },
        { name: 'robots', content: 'noindex' },
        { name: 'description', content: description },
        { property: 'og:type', content: 'website' },
        { property: 'og:title', content: title },
        { property: 'og:description', content: description },
        ...(head ? [{ property: 'og:image', content: head.image }] : []),
        { name: 'twitter:card', content: 'summary_large_image' },
      ],
    }
  },
  component: Share,
})

function Page(props: { children: JSX.Element }) {
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col justify-center px-5 py-10">
      <Wordmark class="h-9 w-auto" />
      <div class="mt-8">{props.children}</div>
      <Link
        to="/"
        class="mt-12 inline-block text-sm font-semibold text-muted hover:text-ink"
      >
        What is Aaru?
      </Link>
    </main>
  )
}

function Share() {
  const page = Route.useLoaderData()
  return (
    <Page>
      <Show when={page().preview} fallback={<Invalid />}>
        {(preview) => (
          <>
            <Show when={preview().from}>
              {(from) => (
                <div class="mb-6">
                  <p class="text-sm font-semibold">
                    From {inviterName(from().user)}
                  </p>
                  <Show when={from().note}>
                    {(note) => (
                      <p class="mt-1 leading-relaxed text-muted">“{note()}”</p>
                    )}
                  </Show>
                </div>
              )}
            </Show>
            <Switch>
              <Match when={preview().title}>
                {(title) => (
                  <TitleCard
                    title={title()}
                    preview={preview()}
                    signedIn={page().signedIn}
                  />
                )}
              </Match>
              <Match when={preview().sportEvent}>
                {(event) => (
                  <EventCard event={event()} signedIn={page().signedIn} />
                )}
              </Match>
              <Match when={preview().concert}>
                {(concert) => (
                  <ConcertCard concert={concert()} signedIn={page().signedIn} />
                )}
              </Match>
              <Match when={preview().unavailable}>
                <h1 class="font-display text-3xl leading-tight font-medium tracking-tight text-balance">
                  {preview().kind === 'sport_event'
                    ? 'This match’s details aren’t available right now.'
                    : 'This concert’s details aren’t available right now.'}
                </h1>
                <p class="mt-4 text-lg leading-relaxed text-muted">
                  Try the link again in a little while.
                </p>
              </Match>
            </Switch>
          </>
        )}
      </Show>
    </Page>
  )
}

/** A shared title: its cover and facts, then save it, open it, or sign in to save it. */
function TitleCard(props: {
  title: TitleDetail
  preview: SharePreview
  signedIn: boolean
}) {
  const params = Route.useParams()
  const search = Route.useSearch()
  const navigate = useNavigate()
  const [saved, setSaved] = createSignal<{
    id: string
    status: LibraryStatus
  } | null>(
    props.preview.libraryItemId && props.preview.status
      ? { id: props.preview.libraryItemId, status: props.preview.status }
      : null,
  )
  const [adding, setAdding] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const kind = () => kindOf(props.title.type, props.title.isAnime)
  const facts = () =>
    [kindName(kind()), props.title.year, props.title.byline]
      .filter(Boolean)
      .join(' · ')

  async function add() {
    if (adding() || saved()) return
    setAdding(true)
    setProblem(null)
    try {
      const entry = await addToLibrary({
        data: {
          type: props.title.type,
          ids: props.title.ids,
          title: props.title.title,
          year: props.title.year,
          status: 'wishlist',
        },
      })
      setSaved({ id: entry.id, status: entry.status })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : `${props.title.title} could not be added.`,
      )
    } finally {
      setAdding(false)
    }
  }

  onMount(() => {
    if (!search().add) return
    if (
      shouldAutoAdd({
        add: search().add === 1 && takeAdd(params().code),
        signedIn: props.signedIn,
        preview: props.preview,
      })
    )
      void add()
    // `add` runs once: the address loses it, so a reload or Back never adds again.
    void navigate({
      to: '/s/$code',
      params: { code: params().code },
      search: {},
      replace: true,
    })
  })

  const join = () => {
    rememberAdd(params().code)
    void navigate({ to: '/sign-in', search: { next: addNext(params().code) } })
  }

  return (
    <>
      <div class="flex items-start gap-5">
        <Poster
          url={props.title.posterUrl}
          kind={kind()}
          class="w-28 shrink-0 sm:w-32"
        />
        <div class="min-w-0">
          <h1 class="font-display text-3xl leading-tight font-medium tracking-tight text-balance">
            {props.title.title}
          </h1>
          <p class="mt-2 text-sm text-muted">{facts()}</p>
        </div>
      </div>
      <Show when={props.title.synopsis}>
        {(synopsis) => (
          <p class="mt-6 line-clamp-6 leading-relaxed text-pretty">
            {synopsis()}
          </p>
        )}
      </Show>
      <Show
        when={saved()}
        fallback={
          <Button
            variant="ink"
            size="lg"
            class="mt-10 min-h-13 w-full text-base"
            disabled={adding()}
            onClick={() => (props.signedIn ? void add() : join())}
          >
            {adding()
              ? 'Adding…'
              : props.signedIn
                ? `Add to ${statusLabel('wishlist', kind())}`
                : 'Add to my Aaru'}
          </Button>
        }
      >
        {(item) => (
          <div class="mt-10 flex items-center justify-between gap-4 rounded-panel bg-surface px-4 py-3">
            <p class="text-sm">
              In your library ·{' '}
              <span class="font-semibold">
                {statusLabel(item().status, kind())}
              </span>
            </p>
            <Link
              to="/app/title/$id"
              params={{ id: item().id }}
              class={buttonVariants({ variant: 'quiet', size: 'sm' })}
            >
              Open
            </Link>
          </div>
        )}
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-4 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
      <Show when={!props.signedIn && !saved()}>
        <p class="mt-4 text-sm leading-relaxed text-muted">
          Sign in or create an account, and you’ll come straight back here. Your
          library stays private: only friends see it.
        </p>
      </Show>
    </>
  )
}

/** A shared match: the score up front (or the kick-off), status, venue, then Sports. */
function EventCard(props: { event: SportEvent; signedIn: boolean }) {
  const [timeZone, setTimeZone] = createSignal('UTC')
  const [today, setToday] = createSignal(localDayKey(new Date(), 'UTC'))
  onMount(() => {
    setTimeZone(viewerTimeZone())
    setToday(localDayKey(new Date()))
  })
  const live = () => props.event.status === 'live'
  const place = () => placeLine(props.event)
  return (
    <>
      <Show when={props.event.league}>
        {(league) => (
          <div class="flex items-center gap-2">
            <SportBadge
              url={props.event.leagueBadgeUrl}
              name={league()}
              class="size-5"
            />
            <p class="eyebrow truncate">{league()}</p>
          </div>
        )}
      </Show>
      <Show
        when={!isCard(props.event)}
        fallback={
          <>
            <Show when={props.event.imageUrl}>
              {(src) => (
                <img
                  src={src()}
                  alt=""
                  referrerpolicy="no-referrer"
                  class="mt-4 aspect-video w-full rounded-panel bg-surface object-cover"
                />
              )}
            </Show>
            <h1 class="mt-4 font-display text-3xl leading-tight font-medium tracking-tight text-balance">
              {props.event.name}
            </h1>
          </>
        }
      >
        <h1 class="sr-only">
          {props.event.home?.name} v {props.event.away?.name}
        </h1>
        <div
          aria-hidden="true"
          class="mt-6 grid grid-cols-[1fr_auto_1fr] items-start gap-3"
        >
          <Side
            name={props.event.home?.name}
            badge={props.event.home?.badgeUrl}
          />
          <div class="flex min-w-24 flex-col items-center pt-3 text-center">
            <Show
              when={hasScore(props.event)}
              fallback={
                <span class="font-display text-2xl font-medium">v</span>
              }
            >
              <span
                class={cn(
                  'font-display text-5xl font-medium tabular-nums',
                  live() && 'text-accent',
                )}
              >
                {props.event.home?.score}–{props.event.away?.score}
              </span>
            </Show>
          </div>
          <Side
            name={props.event.away?.name}
            badge={props.event.away?.badgeUrl}
          />
        </div>
      </Show>
      <div class="mt-6 flex flex-col items-center gap-1 text-center text-sm">
        <Show
          when={live()}
          fallback={
            <p
              class={cn(
                'font-medium',
                (props.event.status === 'postponed' ||
                  props.event.status === 'cancelled') &&
                  'text-danger',
              )}
            >
              {props.event.status === 'scheduled'
                ? whenLine(props.event, today(), timeZone())
                : sportStatus(props.event, timeZone())}
            </p>
          }
        >
          <p class="flex items-center gap-1.5 font-semibold text-accent">
            <span aria-hidden="true" class="size-2 rounded-full bg-accent" />
            Live
            <Show when={clockLabel(props.event.progress)}>
              {(clock) => <span>· {clock()}</span>}
            </Show>
          </p>
        </Show>
        <Show when={place()}>
          {(line) => <p class="text-muted">{line()}</p>}
        </Show>
      </div>
      <Show
        when={props.signedIn}
        fallback={
          <Link
            to="/sign-in"
            search={{ next: '/app/sports' }}
            class={buttonVariants({
              variant: 'ink',
              size: 'lg',
              class: 'mt-10 min-h-13 w-full text-base',
            })}
          >
            Follow sports on Aaru
          </Link>
        }
      >
        <Link
          to="/app/sports"
          search={{ view: 'schedule', date: props.event.day }}
          class={buttonVariants({
            variant: 'ink',
            size: 'lg',
            class: 'mt-10 min-h-13 w-full text-base',
          })}
        >
          Open in Sports
        </Link>
      </Show>
    </>
  )
}

function Side(props: { name?: string; badge?: string }) {
  return (
    <div class="flex min-w-0 flex-col items-center gap-2 text-center">
      <SportBadge url={props.badge} name={props.name ?? ''} class="size-14" />
      <p class="text-sm font-semibold text-balance">{props.name}</p>
    </div>
  )
}

/** A shared concert: the bill, the day and place, then tickets on Ticketmaster. */
function ConcertCard(props: { concert: Concert; signedIn: boolean }) {
  const when = () =>
    [
      shareDate(props.concert.localDate),
      props.concert.localTime && /^\d{2}:\d{2}/.test(props.concert.localTime)
        ? props.concert.localTime.slice(0, 5)
        : null,
    ]
      .filter(Boolean)
      .join(' · ')
  const place = () => concertPlace(props.concert)
  return (
    <>
      <Show when={props.concert.imageUrl}>
        {(src) => (
          <img
            src={src()}
            alt=""
            referrerpolicy="no-referrer"
            class="aspect-video w-full rounded-panel bg-surface object-cover"
          />
        )}
      </Show>
      <h1 class="mt-5 font-display text-3xl leading-tight font-medium tracking-tight text-balance">
        {props.concert.name}
      </h1>
      <Show
        when={
          props.concert.artists.length > 0 &&
          props.concert.artists.join(', ') !== props.concert.name
        }
      >
        <p class="mt-1 text-muted">{props.concert.artists.join(', ')}</p>
      </Show>
      <p class="mt-3 font-medium tabular-nums">{when()}</p>
      <Show when={place()}>
        {(line) => <p class="text-sm text-muted">{line()}</p>}
      </Show>
      <a
        href={props.concert.url}
        target="_blank"
        rel="noopener noreferrer"
        aria-label={`Tickets for ${props.concert.name} on Ticketmaster (opens a new tab)`}
        class={buttonVariants({
          variant: 'ink',
          size: 'lg',
          class: 'mt-10 min-h-13 w-full text-base',
        })}
      >
        Tickets <span aria-hidden="true">↗</span>
      </a>
      <Link
        to={props.signedIn ? '/app/music' : '/sign-in'}
        search={props.signedIn ? undefined : { next: '/app/music' }}
        class="mt-4 inline-block text-sm font-semibold text-accent"
      >
        Concerts near you on Aaru
      </Link>
    </>
  )
}

function Invalid() {
  return (
    <>
      <h1 class="font-display text-4xl leading-tight font-medium tracking-tight">
        This link doesn’t work.
      </h1>
      <p class="mt-4 text-lg leading-relaxed text-muted">
        It may have been mistyped. Ask whoever sent it for the link again.
      </p>
    </>
  )
}
