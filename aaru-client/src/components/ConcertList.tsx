import {
  For,
  Index,
  Show,
  batch,
  createEffect,
  createSignal,
  on,
  onMount,
} from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '~/lib/utils'
import { CREDITS } from '../lib/credits'
import {
  DEFAULT_RADIUS,
  MIN_SEARCH,
  RADII,
  artistsEmptyLine,
  dateBlock,
  detailLine,
  pendingLine,
  placeLine,
  roundPosition,
  searchEmptyLine,
  searchHeading,
} from '../lib/concerts/model'
import type {
  ArtistConcerts,
  Concert,
  ConcertPage,
  ConcertPerformer,
  ConcertPlaceSetting,
  Radius,
  SearchScope,
} from '../lib/concerts/model'
import {
  getArtistConcerts,
  getConcertsNear,
  searchConcertPerformers,
  searchConcerts,
} from '../lib/concerts/server'
import { play } from '../lib/motion'
import { CityPicker } from './CityPicker'
import {
  Alert,
  Button,
  TextField,
  TextFieldInput,
  TextFieldLabel,
  buttonVariants,
} from '~/components/ui'
import { Segmented } from './Segmented'
import { SearchIcon } from './shell/icons'

const TICKETMASTER = CREDITS.find((c) => c.name === 'Ticketmaster')?.href
// UX-050: the vendor stays in the credit line, not the error.
const UNAVAILABLE = 'Concert listings aren’t answering right now.'
/** Artists' concerts shown before "Show all". */
const ARTIST_PREVIEW = 5
const SKELETON_ROWS = 3

type Position = { latitude: number; longitude: number }

/** What the list keeps of a page, everything nearby or one artist's (MUS-010). */
type Listed = Pick<
  ConcertPage,
  'page' | 'hasMore' | 'unavailable' | 'place'
> & {
  /** Absent for a search anywhere. */
  radiusKm?: number
}

/** The artist the list is narrowed to (MUS-010): one picked performer, or every event matching the name. */
type Searched = { name: string; performerId?: string }

/** The performers offered for a submitted name, before one is picked. */
type Choices =
  | { state: 'loading'; name: string }
  | { state: 'ready'; name: string; performers: ConcertPerformer[] }

type Near =
  | { state: 'loading' }
  | { state: 'no_place' }
  | { state: 'failed'; message: string }
  | { state: 'ready'; page: Listed; items: Concert[] }

/**
 * MUS-003: Discover's Concerts view. Two date-led lists: upcoming shows by the artists of the
 * user's albums, then music events near the saved city or a one-off position, inside 25, 50 or
 * 100 km. A position is asked for only on a tap, rounded to two decimals here, sent once in a
 * POST body and kept nowhere but this component's memory. Tickets link out to Ticketmaster.
 */
export function ConcertList(props: {
  setting: ConcertPlaceSetting
  /** The viewer's local "YYYY-MM-DD": only decides when a date names its year. */
  today: string
  onSettingChange: (setting: ConcertPlaceSetting) => void
}) {
  const [artists, setArtists] = createSignal<ArtistConcerts | null>(null)
  const [artistsFailed, setArtistsFailed] = createSignal<string | null>(null)
  const [allArtists, setAllArtists] = createSignal(false)

  const [radius, setRadius] = createSignal<Radius>(DEFAULT_RADIUS)
  const [position, setPosition] = createSignal<Position | null>(null)
  const [near, setNear] = createSignal<Near>({ state: 'loading' })
  const [busy, setBusy] = createSignal(false)
  const [moreFailed, setMoreFailed] = createSignal<string | null>(null)
  const [locating, setLocating] = createSignal(false)
  const [locateProblem, setLocateProblem] = createSignal<string | null>(null)
  const [picking, setPicking] = createSignal(false)
  // MUS-010: an artist's name, looked up only once submitted (each lookup spends the provider's
  // daily calls). Submitting lists the provider's performers to pick from; the list is narrowed to
  // the one picked, or to every event matching the name, near the same centre or anywhere.
  const [text, setText] = createSignal('')
  const [query, setQuery] = createSignal<Searched | null>(null)
  const [choices, setChoices] = createSignal<Choices | null>(null)
  const [scope, setScope] = createSignal<SearchScope>('near')
  let latestChoices = 0
  let list: HTMLUListElement | undefined
  let latest = 0

  async function loadArtists() {
    setArtistsFailed(null)
    setArtists(null)
    try {
      setArtists(await getArtistConcerts())
    } catch (error) {
      setArtistsFailed(
        error instanceof Error
          ? error.message
          : 'Your artists’ concerts could not be loaded.',
      )
    }
  }
  onMount(() => void loadArtists())

  /** Page 1 replaces the list (fading the new one in after a tap); later pages append. */
  async function loadNear(page: number, fade = false) {
    const request = ++latest
    const at = position()
    const searched = query()
    const where = scope()
    setMoreFailed(null)
    // Anywhere needs no centre; everything else does.
    if (!at && !props.setting.place && !(searched && where === 'anywhere')) {
      setBusy(false)
      setNear({ state: 'no_place' })
      return
    }
    const current = near()
    if (page === 1 && current.state !== 'ready') setNear({ state: 'loading' })
    setBusy(true)
    try {
      const result = searched
        ? await searchConcerts({
            data: {
              q: searched.name,
              performerId: searched.performerId,
              scope: where,
              ...(at ?? {}),
              radiusKm: radius(),
              page,
            },
          })
        : await getConcertsNear({
            data: { ...(at ?? {}), radiusKm: radius(), page },
          })
      if (request !== latest) return
      if (result.noPlace) {
        setNear({ state: 'no_place' })
        return
      }
      const before = near()
      const kept = page > 1 && before.state === 'ready' ? before.items : []
      const seen = new Set(kept.map((c) => c.id))
      setNear({
        state: 'ready',
        page: result.page,
        items: [...kept, ...result.page.items.filter((c) => !seen.has(c.id))],
      })
      if (fade && list) void play(list, { opacity: [0, 1] }, 0.2)
    } catch (error) {
      if (request !== latest) return
      const message =
        error instanceof Error ? error.message : 'Concerts could not be loaded.'
      // A failed "Show more" keeps the rows already listed.
      if (page > 1) setMoreFailed(message)
      else setNear({ state: 'failed', message })
    } finally {
      if (request === latest) setBusy(false)
    }
  }

  // A new radius, position, saved city, artist or scope starts over at page 1.
  createEffect(
    on(
      () =>
        [
          radius(),
          position(),
          props.setting.place,
          query(),
          query() ? scope() : null,
        ] as const,
      (_, previous) => void loadNear(1, previous !== undefined),
    ),
  )

  function locate() {
    setLocateProblem(null)
    if (!('geolocation' in navigator)) {
      setLocateProblem('This browser can’t share a location. Choose a city.')
      return
    }
    setLocating(true)
    navigator.geolocation.getCurrentPosition(
      (found) => {
        setLocating(false)
        // Rounded before it is kept, so the precise reading never leaves this callback.
        setPosition(
          roundPosition({
            latitude: found.coords.latitude,
            longitude: found.coords.longitude,
          }),
        )
      },
      (error) => {
        setLocating(false)
        setLocateProblem(
          error.code === error.PERMISSION_DENIED
            ? 'Location is off for Aaru in this browser. Choose a city instead.'
            : 'Your location could not be found. Choose a city instead.',
        )
      },
      { enableHighAccuracy: false, maximumAge: 600_000, timeout: 15_000 },
    )
  }

  const savedName = () => props.setting.place?.name
  /** The city the list is around; null for a one-off position or no city. */
  const centreName = () => {
    if (position()) return null
    const current = near()
    return (
      (current.state === 'ready' ? current.page.place?.name : undefined) ??
      savedName() ??
      null
    )
  }
  const heading = () => {
    const searched = query()
    if (searched) return searchHeading(searched.name, scope(), centreName())
    const centre = centreName()
    return centre ? `Near ${centre}` : 'Near you'
  }

  /** Performers for the name first; with none to offer, straight to every event matching it. */
  async function submit(event: SubmitEvent) {
    event.preventDefault()
    const name = text().trim()
    if (name.length < MIN_SEARCH) return
    const request = ++latestChoices
    setChoices({ state: 'loading', name })
    let found: ConcertPerformer[] = []
    try {
      const offered = await searchConcertPerformers({ data: { q: name } })
      found = offered.unavailable ? [] : offered.items
    } catch {
      // A failed lookup still searches the name.
    }
    if (request !== latestChoices) return
    if (found.length === 0) chooseAll(name)
    else setChoices({ state: 'ready', name, performers: found })
  }
  function choosePerformer(performer: ConcertPerformer) {
    batch(() => {
      setChoices(null)
      setText(performer.name)
      setQuery({ name: performer.name, performerId: performer.id })
    })
  }
  function chooseAll(name: string) {
    batch(() => {
      setChoices(null)
      setQuery({ name })
    })
  }
  function typeName(value: string) {
    setText(value)
    // Emptying the field (its own ×) goes back to everything near.
    if (!value.trim()) clearSearch()
  }
  function clearSearch() {
    latestChoices++
    batch(() => {
      setText('')
      setChoices(null)
      setQuery(null)
    })
  }
  const shownArtists = () => {
    const items = artists()?.items ?? []
    return allArtists() ? items : items.slice(0, ARTIST_PREVIEW)
  }
  const ready = () => {
    const current = near()
    return current.state === 'ready' ? current : null
  }

  return (
    <div class="mt-8 max-w-3xl">
      <section aria-labelledby="artists-on-tour">
        <h2
          id="artists-on-tour"
          class="font-display text-2xl font-medium tracking-tight"
        >
          Your artists on tour
        </h2>
        <Show when={artistsFailed()}>
          {(message) => (
            <Retry message={message()} onRetry={() => void loadArtists()} />
          )}
        </Show>
        <Show
          when={artists()}
          fallback={<Show when={!artistsFailed()}>{skeleton()}</Show>}
        >
          {(found) => (
            <Show
              when={!found().unavailable}
              fallback={<Quiet>{UNAVAILABLE}</Quiet>}
            >
              <Show
                when={found().items.length > 0}
                fallback={<Quiet>{artistsEmptyLine(found())}</Quiet>}
              >
                <ul class="mt-3 divide-y divide-line">
                  <For each={shownArtists()}>
                    {(concert) => (
                      <ConcertRow concert={concert} today={props.today} />
                    )}
                  </For>
                </ul>
                <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2">
                  <Show
                    when={
                      !allArtists() && found().items.length > ARTIST_PREVIEW
                    }
                  >
                    <Button
                      variant="quiet"
                      size="sm"
                      onClick={() => setAllArtists(true)}
                    >
                      Show all {found().items.length}
                    </Button>
                  </Show>
                  <Show when={pendingLine(found().pending)}>
                    {(line) => <p class="text-sm text-muted">{line()}</p>}
                  </Show>
                </div>
              </Show>
            </Show>
          )}
        </Show>
      </section>

      <section class="mt-14" aria-labelledby="concerts-near">
        <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2">
          <h2
            id="concerts-near"
            class="font-display text-2xl font-medium tracking-tight"
            aria-live="polite"
          >
            {heading()}
          </h2>
          <Show when={near().state !== 'no_place'}>
            <div class="flex flex-wrap items-center gap-x-1 gap-y-2">
              <Show
                when={position() && savedName()}
                fallback={
                  <Button
                    variant="ghost"
                    size="sm"
                    disabled={locating()}
                    onClick={locate}
                  >
                    {locating() ? 'Finding you…' : 'Use my location'}
                  </Button>
                }
              >
                {(name) => (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setPosition(null)}
                  >
                    Back to {name()}
                  </Button>
                )}
              </Show>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setPicking(true)}
              >
                {savedName() ? 'Change city' : 'Choose a city'}
              </Button>
            </div>
          </Show>
        </div>

        <form
          role="search"
          class="mt-4 flex flex-wrap items-center gap-2"
          onSubmit={submit}
        >
          <TextField
            value={text()}
            onChange={typeName}
            class="min-w-0 flex-1 sm:max-w-sm"
          >
            <TextFieldLabel class="sr-only">Search an artist</TextFieldLabel>
            <TextFieldInput
              type="search"
              autocomplete="off"
              spellcheck={false}
              enterkeyhint="search"
              placeholder="Search an artist"
              maxlength={100}
              class="rounded-full border-0 bg-surface px-4 text-sm"
            />
          </TextField>
          <Button
            type="submit"
            variant="quiet"
            size="sm"
            disabled={text().trim().length < MIN_SEARCH}
          >
            Search
          </Button>
          <Show when={query() || choices()}>
            <Button variant="ghost" size="sm" onClick={clearSearch}>
              Clear
            </Button>
          </Show>
        </form>

        <Show when={query() && !choices()}>
          <Segmented
            label="Where"
            class="mt-3"
            itemClass="px-4 py-1.5 text-sm whitespace-nowrap"
            options={[
              { value: 'near', label: `Near ${centreName() ?? 'you'}` },
              { value: 'anywhere', label: 'Anywhere' },
            ]}
            value={scope()}
            onChange={setScope}
          />
        </Show>

        <Show
          when={
            near().state !== 'no_place' &&
            !choices() &&
            !(query() && scope() === 'anywhere')
          }
        >
          <Segmented
            label="Distance"
            variant="chip"
            class="mt-4"
            itemClass="px-4 py-1.5 text-sm tabular-nums whitespace-nowrap"
            options={RADII.map((km) => ({
              value: String(km),
              label: `${km} km`,
            }))}
            value={String(radius())}
            onChange={(next) => setRadius(Number(next) as Radius)}
          />
        </Show>

        <Show when={locateProblem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>

        <Show
          when={!choices()}
          fallback={
            <PerformerChoices
              choices={choices()!}
              onPick={choosePerformer}
              onAll={chooseAll}
            />
          }
        >
          <Show when={near().state === 'no_place'}>
            <div class="mt-4 rounded-panel bg-surface px-5 py-5">
              <p class="text-ink">
                Choose a city to see concerts around it, or share where you are
                this once.
              </p>
              <p class="mt-1 text-sm text-muted">
                Your location is rounded to about a kilometre and never saved.
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <Button
                  variant="default"
                  size="sm"
                  onClick={() => setPicking(true)}
                >
                  Choose a city
                </Button>
                <Button
                  variant="quiet"
                  size="sm"
                  disabled={locating()}
                  onClick={locate}
                >
                  {locating() ? 'Finding you…' : 'Use my location'}
                </Button>
              </div>
            </div>
          </Show>

          <Show when={near().state === 'loading'}>{skeleton()}</Show>

          <Show
            when={(() => {
              const current = near()
              return current.state === 'failed' ? current.message : null
            })()}
          >
            {(message) => (
              <Retry message={message()} onRetry={() => void loadNear(1)} />
            )}
          </Show>

          <Show when={ready()}>
            {(current) => (
              <Show
                when={!current().page.unavailable}
                fallback={
                  <div class="mt-3 flex flex-wrap items-center gap-3">
                    <Quiet class="mt-0">{UNAVAILABLE}</Quiet>
                    <Button
                      variant="quiet"
                      size="sm"
                      onClick={() => void loadNear(1)}
                    >
                      Try again
                    </Button>
                  </div>
                }
              >
                <Show
                  when={current().items.length > 0}
                  fallback={
                    <Show
                      when={query()}
                      fallback={
                        <Quiet>
                          No concerts within {current().page.radiusKm} km yet.
                          <Show when={radius() !== 100}>
                            {' '}
                            Try a wider distance.
                          </Show>
                        </Quiet>
                      }
                    >
                      {(name) => (
                        <div class="mt-3 flex flex-wrap items-center gap-3">
                          <Quiet class="mt-0">
                            {searchEmptyLine(
                              name().name,
                              scope(),
                              current().page.radiusKm,
                            )}
                          </Quiet>
                          <Show when={scope() === 'near'}>
                            <Button
                              variant="quiet"
                              size="sm"
                              onClick={() => setScope('anywhere')}
                            >
                              Try Anywhere
                            </Button>
                          </Show>
                        </div>
                      )}
                    </Show>
                  }
                >
                  <ul
                    ref={list}
                    class="mt-3 divide-y divide-line transition-opacity"
                    classList={{ 'opacity-60': busy() }}
                    aria-busy={busy()}
                  >
                    <For each={current().items}>
                      {(concert) => (
                        <ConcertRow concert={concert} today={props.today} />
                      )}
                    </For>
                  </ul>
                  <Show when={moreFailed()}>
                    {(message) => (
                      <p role="alert" class="mt-3 text-sm text-danger">
                        {message()}
                      </p>
                    )}
                  </Show>
                  <Show when={current().page.hasMore}>
                    <div class="mt-4">
                      <Button
                        variant="quiet"
                        disabled={busy()}
                        onClick={() => void loadNear(current().page.page + 1)}
                      >
                        {busy() ? 'Loading…' : 'Show more'}
                      </Button>
                    </div>
                  </Show>
                </Show>
              </Show>
            )}
          </Show>
        </Show>

        <p class="mt-8 text-xs text-muted">
          Concerts from{' '}
          <a
            href={TICKETMASTER}
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-accent hover:underline"
          >
            Ticketmaster
          </a>
        </p>
      </section>

      <Show when={picking()}>
        <CityPicker
          onSaved={(setting) =>
            // One reload for the new city, not one per change.
            batch(() => {
              setPosition(null)
              props.onSettingChange(setting)
            })
          }
          onClose={() => setPicking(false)}
        />
      </Show>
    </div>
  )
}

/** One concert: a ticket stub with the venue's date, what and where, and the way to tickets. */
function ConcertRow(props: { concert: Concert; today: string }) {
  const block = () => dateBlock(props.concert.localDate, props.today)
  const where = () => placeLine(props.concert)
  const detail = () => detailLine(props.concert)
  return (
    <li class="grid grid-cols-[4rem_minmax(0,1fr)] items-center gap-x-4 gap-y-2 py-4 sm:grid-cols-[4rem_minmax(0,1fr)_auto]">
      <time
        datetime={
          props.concert.localTime
            ? `${props.concert.localDate}T${props.concert.localTime.slice(0, 5)}`
            : props.concert.localDate
        }
        class="row-span-2 flex h-20 w-16 flex-col items-center justify-center rounded-panel bg-surface text-center sm:row-span-1"
      >
        <Show
          when={block()}
          fallback={
            <span class="px-1 text-xs text-muted">
              {props.concert.localDate}
            </span>
          }
        >
          {(b) => (
            <>
              <span class="sr-only">{b().label}</span>
              <span
                aria-hidden="true"
                class="text-xs font-medium whitespace-nowrap text-muted"
              >
                {b().month}
              </span>
              <span
                aria-hidden="true"
                class="font-display text-3xl leading-none font-medium tabular-nums text-ink"
              >
                {b().day}
              </span>
              <span aria-hidden="true" class="mt-0.5 text-xs text-muted">
                {b().weekday}
              </span>
            </>
          )}
        </Show>
      </time>
      <div class="min-w-0 self-end sm:self-center">
        <p class="line-clamp-2 font-medium text-ink">{props.concert.name}</p>
        <Show when={where()}>
          {(line) => <p class="truncate text-sm text-muted">{line()}</p>}
        </Show>
        <Show when={detail()}>
          {(line) => <p class="text-sm text-muted tabular-nums">{line()}</p>}
        </Show>
      </div>
      <a
        href={props.concert.url}
        target="_blank"
        rel="noopener noreferrer"
        aria-label={`Tickets for ${props.concert.name} on Ticketmaster (opens a new tab)`}
        class={buttonVariants({
          variant: 'quiet',
          size: 'sm',
          class: 'w-fit self-start sm:self-center',
        })}
      >
        Tickets <span aria-hidden="true">↗</span>
      </a>
    </li>
  )
}

/**
 * MUS-010: the provider's performers for a submitted name, best first, then every event matching
 * the name as free text, for festivals and bills without a named act.
 */
function PerformerChoices(props: {
  choices: Choices
  onPick: (performer: ConcertPerformer) => void
  onAll: (name: string) => void
}) {
  const row =
    'h-auto w-full justify-start gap-3 rounded-none px-1 py-2.5 text-left font-normal'
  return (
    <Show
      when={props.choices.state === 'ready' ? props.choices : null}
      fallback={skeleton()}
    >
      {(ready) => (
        <section class="mt-4" aria-label={`Artists named ${ready().name}`}>
          <p class="text-sm text-muted">Which one?</p>
          <ul class="mt-1 divide-y divide-line">
            <For each={ready().performers}>
              {(performer) => (
                <li>
                  <Button
                    variant="ghost"
                    size="bare"
                    class={row}
                    onClick={() => props.onPick(performer)}
                  >
                    <Show
                      when={performer.imageUrl}
                      fallback={
                        <span
                          aria-hidden="true"
                          class="flex size-10 shrink-0 items-center justify-center rounded-full bg-surface font-display text-ink"
                        >
                          {performer.name.slice(0, 1)}
                        </span>
                      }
                    >
                      {(src) => (
                        <img
                          src={src()}
                          alt=""
                          loading="lazy"
                          class="size-10 shrink-0 rounded-full object-cover"
                        />
                      )}
                    </Show>
                    <span class="truncate text-ink">{performer.name}</span>
                  </Button>
                </li>
              )}
            </For>
            <li>
              <Button
                variant="ghost"
                size="bare"
                class={row}
                onClick={() => props.onAll(ready().name)}
              >
                <span
                  aria-hidden="true"
                  class="flex size-10 shrink-0 items-center justify-center rounded-full border border-line"
                >
                  <SearchIcon class="size-4" />
                </span>
                <span class="truncate">
                  All events matching “{ready().name}”
                </span>
              </Button>
            </li>
          </ul>
        </section>
      )}
    </Show>
  )
}

/** Still placeholders at a row's real size: nothing shimmers. */
function skeleton() {
  return (
    <ul class="mt-3 divide-y divide-line" aria-hidden="true">
      <Index each={Array.from({ length: SKELETON_ROWS })}>
        {() => (
          <li class="flex items-center gap-4 py-4">
            <div class="h-20 w-16 shrink-0 rounded-panel bg-surface" />
            <div class="min-w-0 flex-1">
              <div class="h-4 w-1/2 rounded-full bg-surface" />
              <div class="mt-2.5 h-3.5 w-2/5 rounded-full bg-surface" />
              <div class="mt-2 h-3.5 w-1/4 rounded-full bg-surface" />
            </div>
          </li>
        )}
      </Index>
    </ul>
  )
}

function Quiet(props: { class?: string; children: JSX.Element }) {
  return <p class={cn('mt-3 text-muted', props.class)}>{props.children}</p>
}

function Retry(props: { message: string; onRetry: () => void }) {
  return (
    <Alert
      variant="destructive"
      class="mt-3 flex items-center justify-between gap-3"
    >
      <span>{props.message}</span>
      <Button variant="quiet" size="sm" onClick={() => props.onRetry()}>
        Try again
      </Button>
    </Alert>
  )
}
