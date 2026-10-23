import { Link, createFileRoute } from '@tanstack/solid-router'
import { For, Show, createResource, createSignal, onMount } from 'solid-js'
import { AlbumLink, Cover, TopList } from '../components/music/TopList'
import { Button } from '~/components/ui'
import {
  TOP_BY,
  byDay,
  listenSubtitle,
  timeOfDay,
} from '../lib/music/listening-model'
import type { TopBy } from '../lib/music/listening-model'
import { listListens, topListens } from '../lib/music/listening'
import type { Listen } from '../lib/music/listening'
import { Segmented } from '../components/Segmented'

// MUS-008: Listens (the log) and its top lists. Recent and Top sit side by side on a wide
// screen and behind a switch on a phone. Everything loads in the browser, which knows the
// viewer's time zone.
export const Route = createFileRoute('/_shell/app_/music')({
  head: () => ({ meta: [{ title: 'Listens · Aaru' }] }),
  component: Music,
})

const PAGE = 50

const SPANS = [
  { span: 'last7', label: '7 days' },
  { span: 'last30', label: '30 days' },
  { span: 'year', label: 'Year' },
  { span: 'all', label: 'All time' },
] as const

type TopSpan = (typeof SPANS)[number]['span']

function Music() {
  const [now, setNow] = createSignal<Date | null>(null)
  const [view, setView] = createSignal<'recent' | 'top'>('recent')
  onMount(() => setNow(new Date()))

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Listens
        </h1>
        <Segmented
          label="Show"
          class="mt-6 md:hidden"
          itemClass="px-4 py-1.5 text-sm"
          options={[
            { value: 'recent', label: 'Recent' },
            { value: 'top', label: 'Top' },
          ]}
          value={view()}
          onChange={setView}
        />
        <Show when={now()}>
          {(today) => (
            <div class="mt-6 grid gap-10 md:grid-cols-2">
              <div classList={{ 'hidden md:block': view() !== 'recent' }}>
                <Recent now={today()} />
              </div>
              <div classList={{ 'hidden md:block': view() !== 'top' }}>
                <Top now={today()} />
              </div>
            </div>
          )}
        </Show>
      </div>
    </div>
  )
}

function Recent(props: { now: Date }) {
  const [listens, setListens] = createSignal<Listen[]>([])
  const [next, setNext] = createSignal<string | undefined>()
  const [state, setState] = createSignal<'loading' | 'ready' | 'failed'>(
    'loading',
  )

  async function load(before?: string) {
    setState('loading')
    try {
      const page = await listListens({ data: { before, limit: PAGE } })
      setListens([...listens(), ...page.items])
      setNext(page.next)
      setState('ready')
    } catch {
      setState('failed')
    }
  }
  onMount(() => void load())

  return (
    <section aria-labelledby="recent-heading">
      <h2
        id="recent-heading"
        class="hidden font-display text-2xl font-medium tracking-tight md:block"
      >
        Recent
      </h2>
      <Show
        when={listens().length > 0 || state() !== 'ready'}
        fallback={
          <p class="mt-4 text-muted">
            No listens yet.{' '}
            <Link
              to="/app/settings/connections"
              class="font-semibold text-accent hover:underline"
            >
              Connect a scrobbler
            </Link>{' '}
            and what you play shows up here.
          </p>
        }
      >
        <For each={byDay(listens(), props.now)}>
          {(day) => (
            <>
              <h3 class="mt-6 eyebrow">{day.heading}</h3>
              <ul class="mt-1 divide-y divide-line">
                <For each={day.listens}>
                  {(listen) => (
                    <li>
                      <AlbumLink
                        titleId={listen.albumRef?.titleId}
                        class="flex items-center gap-4 py-3"
                      >
                        <Cover url={listen.coverUrl} />
                        <span class="min-w-0 flex-1">
                          <span class="block truncate font-medium">
                            {listen.track}
                          </span>
                          <span class="block truncate text-sm text-muted">
                            {listenSubtitle(listen)}
                          </span>
                        </span>
                        <span class="shrink-0 text-sm text-muted tabular-nums">
                          {timeOfDay(listen)}
                        </span>
                      </AlbumLink>
                    </li>
                  )}
                </For>
              </ul>
            </>
          )}
        </For>
        <Show when={state() === 'failed'}>
          <p role="alert" class="mt-4 text-sm text-danger">
            Your listens could not be loaded.
          </p>
        </Show>
        <Show when={state() === 'loading'}>
          <p class="mt-4 text-sm text-muted">Loading…</p>
        </Show>
        <Show when={next() && state() === 'ready'}>
          <Button
            variant="outline"
            class="mt-4"
            onClick={() => void load(next())}
          >
            Load more
          </Button>
        </Show>
      </Show>
    </section>
  )
}

function Top(props: { now: Date }) {
  const [span, setSpan] = createSignal<TopSpan>('last30')
  const [by, setBy] = createSignal<TopBy>('artist')
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
  const [top] = createResource(
    () => ({ period: span(), rank: by() }),
    ({ period, rank }) =>
      topListens({
        data:
          period === 'year'
            ? { by: rank, year: props.now.getFullYear(), tz, limit: 20 }
            : { by: rank, span: period, tz, limit: 20 },
      }),
  )

  return (
    <section aria-labelledby="top-heading">
      <h2
        id="top-heading"
        class="hidden font-display text-2xl font-medium tracking-tight md:block"
      >
        Top
      </h2>
      <div class="flex flex-wrap gap-2 md:mt-4">
        <Segmented
          label="Period"
          itemClass="px-3 py-1.5 text-sm"
          options={SPANS.map((o) => ({ value: o.span, label: o.label }))}
          value={span()}
          onChange={setSpan}
        />
        <Segmented
          label="Rank"
          itemClass="px-3 py-1.5 text-sm"
          options={TOP_BY.map((o) => ({ value: o.by, label: o.label }))}
          value={by()}
          onChange={setBy}
        />
      </div>
      <div class="mt-2 min-h-16" aria-busy={top.loading}>
        <Show
          when={top()}
          fallback={
            <Show when={top.error}>
              <p role="alert" class="py-3 text-sm text-danger">
                The top list could not be loaded.
              </p>
            </Show>
          }
        >
          {(list) => (
            <Show
              when={list().items.length > 0}
              fallback={
                <p class="py-3 text-sm text-muted">Nothing played then.</p>
              }
            >
              <TopList rows={list().items} by={by()} />
            </Show>
          )}
        </Show>
      </div>
    </section>
  )
}
