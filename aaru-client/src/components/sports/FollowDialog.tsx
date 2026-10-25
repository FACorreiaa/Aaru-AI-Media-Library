import { For, Match, Show, Switch, createSignal, onCleanup } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { KIND_LABEL, entityLine, sportQuery } from '../../lib/sports/model'
import type { SportEntity, SportEntityKind } from '../../lib/sports/model'
import { searchSports } from '../../lib/sports/server'
import { Segmented } from '../Segmented'
import { SportBadge } from './SportBadge'

const DEBOUNCE_MS = 300

type KindFilter = 'all' | SportEntityKind

/**
 * SPT-003's search to follow: leagues, teams and players by name, each with a Follow toggle.
 * The toggle itself belongs to the page (`isFollowing`, `onToggle`), so a follow made here shows
 * in Favorites and the picks at once. `open` false plays the exit.
 */
export function FollowDialog(props: {
  open: boolean
  isFollowing: (entity: SportEntity) => boolean
  isBusy: (entity: SportEntity) => boolean
  onToggle: (entity: SportEntity) => void
  /** A follow that failed (100 already, Sports off), said here since the page is behind. */
  toggleProblem?: string | null
  onClose: () => void
}) {
  const [text, setText] = createSignal('')
  const [kind, setKind] = createSignal<KindFilter>('all')
  const [found, setFound] = createSignal<SportEntity[] | null>(null)
  const [searching, setSearching] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  let timer: ReturnType<typeof setTimeout> | undefined
  let latest = 0

  onCleanup(() => clearTimeout(timer))

  function ask(value: string, filter: KindFilter) {
    clearTimeout(timer)
    const q = sportQuery(value)
    const request = ++latest
    if (!q) {
      setFound(null)
      setSearching(false)
      return
    }
    setSearching(true)
    timer = setTimeout(() => void search(q, filter, request), DEBOUNCE_MS)
  }

  async function search(q: string, filter: KindFilter, request: number) {
    setProblem(null)
    try {
      const result = await searchSports({
        data: { q, kind: filter === 'all' ? undefined : filter },
      })
      if (request !== latest) return
      if (result.unavailable) setProblem('Sports aren’t answering right now.')
      setFound(result.items)
    } catch (error) {
      if (request === latest)
        setProblem(
          error instanceof Error
            ? error.message
            : 'Sports could not be searched right now.',
        )
    } finally {
      if (request === latest) setSearching(false)
    }
  }

  return (
    <Dialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          aria-labelledby="sport-follow-title"
          class="block gap-0 p-0 sm:max-w-md"
        >
          <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
            <h2
              id="sport-follow-title"
              class="font-display text-xl font-medium"
            >
              Follow
            </h2>
            <Button
              variant="ghost"
              size="bare"
              class="text-sm"
              onClick={() => props.onClose()}
            >
              Done
            </Button>
          </div>
          <div class="flex flex-col gap-3 px-5 pt-4">
            <TextField
              value={text()}
              onChange={(value) => {
                setText(value)
                ask(value, kind())
              }}
            >
              <TextFieldLabel class="sr-only">
                League, team or player
              </TextFieldLabel>
              <TextFieldInput
                type="search"
                autofocus
                autocomplete="off"
                spellcheck={false}
                placeholder="League, team or player"
                maxlength={100}
                class="rounded-full border-0 bg-surface px-4 text-sm"
              />
            </TextField>
            <Segmented
              label="Search in"
              variant="chip"
              itemClass="px-3 py-1 text-xs"
              options={[
                { value: 'all', label: 'All' },
                { value: 'league', label: 'Leagues' },
                { value: 'team', label: 'Teams' },
                { value: 'player', label: 'Players' },
              ]}
              value={kind()}
              onChange={(next) => {
                setKind(next)
                ask(text(), next)
              }}
            />
            <Show when={props.toggleProblem}>
              {(message) => (
                <p role="alert" class="text-sm text-danger">
                  {message()}
                </p>
              )}
            </Show>
          </div>
          <div
            class="max-h-[55dvh] min-h-40 overflow-y-auto px-3 py-3"
            aria-live="polite"
            aria-busy={searching()}
          >
            <Switch>
              <Match when={problem()}>
                {(message) => (
                  <p role="alert" class="px-2 py-3 text-sm text-danger">
                    {message()}
                  </p>
                )}
              </Match>
              <Match when={found() === null && !searching()}>
                <p class="px-2 py-3 text-sm text-muted">
                  Find a league, a team or a player to follow.
                </p>
              </Match>
              <Match
                when={found() === null || (searching() && !found()?.length)}
              >
                <p class="px-2 py-3 text-sm text-muted">Searching…</p>
              </Match>
              <Match when={found()?.length === 0}>
                <p class="px-2 py-3 text-sm text-muted">
                  Nothing by that name. Try its English name.
                </p>
              </Match>
              <Match when={found()}>
                {(items) => (
                  <ul>
                    <For each={items()}>
                      {(entity) => (
                        <li class="flex items-center gap-3 rounded-panel px-2 py-2">
                          <SportBadge
                            url={entity.badgeUrl}
                            name={entity.name}
                            class="size-8"
                          />
                          <span class="flex min-w-0 flex-1 flex-col">
                            <span class="truncate text-sm font-medium">
                              {entity.name}
                            </span>
                            <span class="truncate text-xs text-muted">
                              {KIND_LABEL[entity.kind]} · {entityLine(entity)}
                            </span>
                          </span>
                          <FollowToggle
                            entity={entity}
                            following={props.isFollowing(entity)}
                            busy={props.isBusy(entity)}
                            onToggle={props.onToggle}
                          />
                        </li>
                      )}
                    </For>
                  </ul>
                )}
              </Match>
            </Switch>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}

/** Follow / Following, one toggle: pressed while followed. */
export function FollowToggle(props: {
  entity: SportEntity
  following: boolean
  busy: boolean
  onToggle: (entity: SportEntity) => void
}) {
  return (
    <Button
      variant={props.following ? 'quiet' : 'ink'}
      size="xs"
      aria-pressed={props.following}
      aria-label={`${props.following ? 'Following' : 'Follow'} ${props.entity.name}`}
      disabled={props.busy}
      onClick={() => props.onToggle(props.entity)}
      class="shrink-0"
    >
      {props.following ? 'Following' : 'Follow'}
    </Button>
  )
}
