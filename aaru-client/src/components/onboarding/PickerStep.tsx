import {
  For,
  Match,
  Show,
  Switch,
  createEffect,
  createSignal,
  onCleanup,
  onMount,
} from 'solid-js'
import {
  Skeleton,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import type { components } from '../../lib/api/schema'
import { KINDS, hitKey } from '../../lib/library/model'
import type { CatalogHit, MediaKind } from '../../lib/library/model'
import { searchCatalog } from '../../lib/library/server'
import {
  continueLabel,
  cyclePick,
  hitKind,
  pickHeading,
  pickLabel,
  pickOptions,
  setPick,
} from '../../lib/onboarding/model'
import type { OnboardingPick } from '../../lib/onboarding/model'
import { getOnboardingRows } from '../../lib/onboarding/server'
import { LoadError } from '../groups/LoadError'
import { Row } from '../HomeRows'
import { PosterPick } from './PosterPick'
import { PillButton, StepFrame } from './StepFrame'
import type { Problem } from './StepFrame'

// A picker screen (DESIGN.md §0a, step 2…n), one per kind chosen: a search field, then rows of
// well-known titles. A tap cycles a poster's status; Continue saves the screen as one action.

type DiscoverRow = components['schemas']['DiscoverRow']

const SEARCH_LIMIT = 18

function chipFor(pick: OnboardingPick | undefined, kind: MediaKind) {
  return pick ? pickLabel(pick.status, kind) : null
}

export function PickerStep(props: {
  kind: MediaKind
  picks: OnboardingPick[]
  onPicks: (update: (picks: OnboardingPick[]) => OnboardingPick[]) => void
  /** This kind's rows, kept by the flow so Back does not load them again. */
  rows: DiscoverRow[] | undefined
  onRows: (rows: DiscoverRow[]) => void
  onContinue: () => void
  busy: boolean
  problem: Problem | null
}) {
  const [failed, setFailed] = createSignal<unknown>(null)
  const [query, setQuery] = createSignal('')
  const [hits, setHits] = createSignal<CatalogHit[]>([])
  const [searching, setSearching] = createSignal(false)
  const [searchProblem, setSearchProblem] = createSignal<string | null>(null)
  let latest = 0

  async function load() {
    setFailed(null)
    try {
      props.onRows(await getOnboardingRows({ data: { kind: props.kind } }))
    } catch (error) {
      setFailed(error)
    }
  }
  onMount(() => {
    if (!props.rows) void load()
  })

  // The same search as Add and the title picker, scoped to this kind.
  createEffect(() => {
    const text = query().trim()
    const scope = KINDS.find((k) => k.kind === props.kind)?.search ?? 'movie'
    const ticket = ++latest
    if (text.length < 2) {
      setHits([])
      setSearchProblem(null)
      setSearching(false)
      return
    }
    const timer = setTimeout(async () => {
      setSearching(true)
      try {
        const results = await searchCatalog({ data: { q: text, type: scope } })
        if (ticket === latest) {
          // An `all`-free scope can still bring a stray kind (a film among anime): keep this one.
          setHits(
            results.items
              .filter((hit) => hitKind(hit) === props.kind)
              .slice(0, SEARCH_LIMIT),
          )
          setSearchProblem(null)
        }
      } catch (error) {
        if (ticket === latest) {
          setHits([])
          setSearchProblem(
            error instanceof Error ? error.message : 'Search failed.',
          )
        }
      } finally {
        if (ticket === latest) setSearching(false)
      }
    }, 300)
    onCleanup(() => clearTimeout(timer))
  })

  const byKey = () => new Map(props.picks.map((pick) => [pick.key, pick]))
  const count = () =>
    props.picks.filter((pick) => pick.kind === props.kind).length
  const filledRows = () =>
    (props.rows ?? []).filter((row) => row.items.length > 0)
  const plural = () =>
    KINDS.find((k) => k.kind === props.kind)?.label.toLowerCase() ?? ''

  const card = (hit: CatalogHit, layout: 'row' | 'grid') => {
    const pick = () => byKey().get(hitKey(hit))
    const kind = hitKind(hit)
    // In the library before the flow: shown as added, never sent.
    const inLibrary = () => !pick() && !!hit.libraryItemId
    return (
      <PosterPick
        hit={hit}
        kind={kind}
        layout={layout}
        selected={!!pick()}
        locked={inLibrary() || !!pick()?.saved}
        chip={chipFor(pick(), kind)}
        note={
          inLibrary() ? 'In your library' : pick()?.saved ? 'Added' : undefined
        }
        onTap={() => props.onPicks((picks) => cyclePick(picks, hit))}
        menu={{
          current: pick()?.status ?? null,
          options: pickOptions(kind),
          onSet: (status) =>
            props.onPicks((picks) => setPick(picks, hit, status)),
        }}
      />
    )
  }

  return (
    <StepFrame
      title={pickHeading(props.kind)}
      problem={props.problem}
      footer={
        <PillButton busy={props.busy} onClick={props.onContinue}>
          {props.busy ? 'Saving…' : continueLabel(props.kind, count())}
        </PillButton>
      }
    >
      <TextField value={query()} onChange={setQuery} class="mt-6 max-w-xl">
        <TextFieldLabel class="sr-only">Search {plural()}</TextFieldLabel>
        <TextFieldInput
          type="search"
          placeholder={`Search ${plural()}`}
          class="w-full rounded-xl border-0 bg-surface px-4 text-base md:text-base"
        />
      </TextField>

      <Switch>
        <Match when={query().trim().length >= 2}>
          <div aria-busy={searching()} aria-live="polite">
            <Show when={searchProblem()}>
              {(text) => (
                <p role="alert" class="mt-4 text-sm text-danger">
                  {text()}
                </p>
              )}
            </Show>
            <Show
              when={hits().length > 0}
              fallback={
                <Show when={!searching() && !searchProblem()}>
                  <p class="mt-4 text-sm text-muted">Nothing found.</p>
                </Show>
              }
            >
              <ul class="mt-6 grid grid-cols-3 gap-4 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
                <For each={hits()}>{(hit) => <li>{card(hit, 'grid')}</li>}</For>
              </ul>
            </Show>
          </div>
        </Match>
        {/* A first load that failed is said as a failure, never as an empty screen. */}
        <Match when={failed()}>
          {(error) => (
            <LoadError
              what="These titles"
              error={error()}
              reset={() => void load()}
            />
          )}
        </Match>
        <Match when={!props.rows}>
          <div aria-hidden="true">
            <For each={[0, 1]}>
              {() => (
                <div class="mt-10">
                  <Skeleton class="h-7 w-40 rounded-field" />
                  <div class="mt-4 flex gap-4 overflow-hidden">
                    <For each={[0, 1, 2, 3, 4, 5]}>
                      {() => (
                        <Skeleton class="aspect-[2/3] w-32 shrink-0 rounded-field md:w-40" />
                      )}
                    </For>
                  </div>
                </div>
              )}
            </For>
          </div>
        </Match>
        {/* No rows for this kind (a provider down): the search above is the way in. */}
        <Match when={filledRows().length > 0}>
          <For each={filledRows()}>
            {(row) => (
              <Row title={row.title} note={row.note}>
                <For each={row.items}>{(hit) => card(hit, 'row')}</For>
              </Row>
            )}
          </For>
        </Match>
      </Switch>
    </StepFrame>
  )
}
