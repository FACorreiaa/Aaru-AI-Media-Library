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
  Button,
  SwitchControl,
  SwitchDescription,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
  TextField,
  TextFieldInput,
  TextFieldLabel,
  Switch as Toggle,
} from '~/components/ui'
import { Segmented } from '../Segmented'
import {
  COUNTDOWN_DEFAULT,
  REACTIONS,
  canHost,
  countdownSeconds,
  hitRef,
  markLabel,
  partyPhase,
  partyTarget,
  partyWord,
  phaseLabel,
  readingTarget,
  serverOffset,
  validEpisode,
} from '../../lib/groups/kinds'
import type { PartyPhase } from '../../lib/groups/kinds'
import {
  endWatchParty,
  getWatchParty,
  markWatchPartyWatched,
  openWatchParty,
  setWatchPartyReady,
  startWatchParty,
} from '../../lib/groups/kinds-server'
import type { WatchPartyView } from '../../lib/groups/kinds-server'
import type { Channel } from '../../lib/groups/server'
import { undoAction } from '../../lib/history/server'
import { kindOf } from '../../lib/library/model'
import type { CatalogHit } from '../../lib/library/model'
import { sendReaction, useRealtime } from '../../lib/realtime/socket'
import { Poster } from '../Poster'
import { TitlePicker } from './TitlePicker'
import { useGroup, useShell } from './shell'

type Floating = { id: number; emoji: string }

const COUNTDOWNS = ['5', '10', '30'].map((value) => ({
  value,
  label: `${value} s`,
}))

const numberClass = 'mt-0.5 min-h-9 w-16 rounded-lg border-0 px-2 text-sm'

/**
 * WatchPanel (GRP-009, ROOM-005): a watch channel's party above its chat. Lobby with who has
 * joined, a countdown every client runs against the server's clock, and live reactions. Being
 * ready is joining: when the host ends, the server marks the title for everyone who joined and
 * left "Mark it for me" on, and the ended party offers Undo. Someone who switched it off, or
 * never joined, keeps "Mark watched for me". A book or manga makes it a reading session, with a
 * page or a chapter. Aaru never touches anyone's player and shares no screen.
 */
export function WatchPanel(props: { channel: Channel }) {
  const shell = useShell()
  const scope = useGroup()
  const ref = () => ({
    groupId: scope.detail().group.id,
    channelId: props.channel.id,
  })
  const meId = () => shell.me().userId

  const [view, setView] = createSignal<WatchPartyView | null>(null)
  const [offset, setOffset] = createSignal(0)
  const [now, setNow] = createSignal(Date.now())
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [picking, setPicking] = createSignal(false)
  const [picked, setPicked] = createSignal<CatalogHit | null>(null)
  const [season, setSeason] = createSignal('1')
  const [episode, setEpisode] = createSignal('1')
  const [chapter, setChapter] = createSignal('')
  const [volume, setVolume] = createSignal('')
  const [page, setPage] = createSignal('')
  const [countdown, setCountdown] = createSignal(COUNTDOWN_DEFAULT)
  const [undone, setUndone] = createSignal<string | null>(null)
  const [floating, setFloating] = createSignal<Floating[]>([])
  let floatId = 0

  const party = () => view()?.party
  const phase = (): PartyPhase | null => {
    const p = party()
    return p ? partyPhase(p, now(), offset()) : null
  }
  const secondsLeft = () => {
    const startsAt = party()?.startsAt
    return startsAt ? countdownSeconds(startsAt, now(), offset()) : 0
  }
  const hosting = () => {
    const p = party()
    return p ? canHost(p, meId(), scope.detail().group.role) : false
  }
  const ready = () => party()?.ready.some((u) => u.userId === meId()) ?? false
  /** The end of the party will mark it for me: I joined and left "Mark it for me" on. */
  const willMark = () => ready() && (view()?.autoMark ?? true)
  const word = () => partyWord(party()?.title.type ?? 'movie')
  const reading = () =>
    readingTarget(picked()?.type ?? '', {
      chapter: chapter(),
      volume: volume(),
      page: page(),
    })

  /** Takes a party response, timing the server's clock from the middle of the round trip. */
  async function take(request: () => Promise<WatchPartyView>) {
    const sent = Date.now()
    const next = await request()
    const received = Date.now()
    setOffset(serverOffset(next.serverTime, (sent + received) / 2))
    setNow(received)
    setView(next)
  }

  async function load() {
    try {
      await take(() => getWatchParty({ data: ref() }))
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : "The watch party didn't load.",
      )
    }
  }

  async function act(request: () => Promise<WatchPartyView>) {
    setBusy(true)
    setProblem(null)
    try {
      await take(request)
    } catch (error) {
      setProblem(error instanceof Error ? error.message : 'That did not work.')
    } finally {
      setBusy(false)
    }
  }

  onMount(() => void load())

  // A countdown ticks four times a second; nothing ticks otherwise.
  createEffect(() => {
    if (phase() !== 'countdown') return
    const timer = window.setInterval(() => setNow(Date.now()), 250)
    onCleanup(() => window.clearInterval(timer))
  })

  function float(emoji: string) {
    const id = ++floatId
    setFloating((list) => [...list.slice(-11), { id, emoji }])
    window.setTimeout(
      () => setFloating((list) => list.filter((f) => f.id !== id)),
      2500,
    )
  }

  useRealtime((event) => {
    if (event.type === 'ready') return void load()
    if (event.channelId !== props.channel.id) return
    if (event.type === 'watch.updated') void load()
    if (event.type === 'watch.reaction' && event.emoji) float(event.emoji)
  })

  function react(emoji: string) {
    if (sendReaction(ref().groupId, ref().channelId, emoji)) float(emoji)
  }

  function open() {
    const hit = picked()
    if (!hit) return
    const isShow = hit.type === 'show'
    if (isShow && !validEpisode(Number(season()), Number(episode()))) return
    const target = reading()
    if (!target) return
    void act(async () => {
      const next = await openWatchParty({
        data: {
          ...ref(),
          title: hitRef(hit),
          ...(isShow
            ? { season: Number(season()), episode: Number(episode()) }
            : target),
        },
      })
      setPicking(false)
      setPicked(null)
      setChapter('')
      setVolume('')
      setPage('')
      return next
    })
  }

  function markWatched() {
    void act(async () => {
      await markWatchPartyWatched({ data: ref() })
      return getWatchParty({ data: ref() })
    })
  }

  /** Takes back what the party marked for me: my own action, nobody else's. */
  async function undo() {
    const id = view()?.actionId
    if (!id) return
    setBusy(true)
    setProblem(null)
    try {
      await undoAction({ data: { id } })
      setUndone(id)
    } catch (error) {
      const text = error instanceof Error ? error.message : ''
      if (text === 'That was already undone.') setUndone(id)
      else setProblem(text || 'That could not be undone.')
    } finally {
      setBusy(false)
    }
  }

  const targetLine = () => {
    const p = party()
    return p ? partyTarget(p) : null
  }

  /** My side of the check-off, once the party has started or ended. */
  const mine = () => (
    <Show
      when={view()?.markedForYou}
      fallback={
        <Show when={!willMark() || phase() === 'ended'}>
          <Button
            variant="outline"
            size="sm"
            disabled={busy()}
            onClick={markWatched}
            title="Marks it in your own library only"
          >
            {markLabel(party()?.title.type ?? 'movie')}
          </Button>
        </Show>
      }
    >
      <span role="status" class="text-sm font-medium text-accent">
        {undone() && undone() === view()?.actionId
          ? 'Undone'
          : 'Marked in your library ✓'}
      </span>
      <Show when={view()?.actionId && undone() !== view()?.actionId}>
        <Button
          variant="link"
          size="bare"
          disabled={busy()}
          onClick={() => void undo()}
          class="text-accent"
        >
          Undo
        </Button>
      </Show>
    </Show>
  )

  return (
    <section
      aria-label={word()}
      class="relative shrink-0 border-b border-line bg-surface/40 px-4 py-3 md:px-6"
    >
      <Switch>
        <Match when={picking()}>
          <div class="max-w-xl">
            <div class="flex items-center justify-between">
              <h2 class="font-display text-lg font-medium">
                Start a watch party
              </h2>
              <Button
                variant="ghost"
                size="bare"
                onClick={() => {
                  setPicking(false)
                  setPicked(null)
                }}
                class="font-normal"
              >
                Cancel
              </Button>
            </div>
            <Show
              when={picked()}
              fallback={
                <div class="mt-2">
                  <TitlePicker
                    kinds={['film', 'show', 'anime', 'manga', 'book']}
                    onPick={setPicked}
                  />
                </div>
              }
            >
              {(hit) => (
                <div class="mt-3 flex flex-wrap items-end gap-3">
                  <p class="min-w-0 flex-1 truncate font-semibold">
                    {hit().title}
                    <Button
                      variant="link"
                      size="bare"
                      onClick={() => setPicked(null)}
                      class="ml-2 text-accent"
                    >
                      Change
                    </Button>
                  </p>
                  <Show when={hit().type === 'show'}>
                    <TextField
                      value={season()}
                      onChange={setSeason}
                      class="w-auto gap-0"
                    >
                      <TextFieldLabel class="text-xs font-medium">
                        Season
                      </TextFieldLabel>
                      <TextFieldInput
                        type="number"
                        min="0"
                        inputmode="numeric"
                        class={numberClass}
                      />
                    </TextField>
                    <TextField
                      value={episode()}
                      onChange={setEpisode}
                      class="w-auto gap-0"
                    >
                      <TextFieldLabel class="text-xs font-medium">
                        Episode
                      </TextFieldLabel>
                      <TextFieldInput
                        type="number"
                        min="1"
                        inputmode="numeric"
                        class={numberClass}
                      />
                    </TextField>
                  </Show>
                  <Show when={hit().type === 'manga'}>
                    <TextField
                      value={chapter()}
                      onChange={setChapter}
                      class="w-auto gap-0"
                    >
                      <TextFieldLabel class="text-xs font-medium">
                        To chapter
                      </TextFieldLabel>
                      <TextFieldInput
                        type="number"
                        min="0"
                        inputmode="numeric"
                        class={numberClass}
                      />
                    </TextField>
                    <TextField
                      value={volume()}
                      onChange={setVolume}
                      class="w-auto gap-0"
                    >
                      <TextFieldLabel class="text-xs font-medium">
                        Volume
                      </TextFieldLabel>
                      <TextFieldInput
                        type="number"
                        min="0"
                        inputmode="numeric"
                        class={numberClass}
                      />
                    </TextField>
                  </Show>
                  <Show when={hit().type === 'book'}>
                    <TextField
                      value={page()}
                      onChange={setPage}
                      class="w-auto gap-0"
                    >
                      <TextFieldLabel class="text-xs font-medium">
                        To page
                      </TextFieldLabel>
                      <TextFieldInput
                        type="number"
                        min="0"
                        inputmode="numeric"
                        class={`${numberClass} w-20`}
                      />
                    </TextField>
                  </Show>
                  <Button
                    size="sm"
                    disabled={
                      busy() ||
                      !reading() ||
                      (hit().type === 'show' &&
                        !validEpisode(Number(season()), Number(episode())))
                    }
                    onClick={open}
                  >
                    Open the lobby
                  </Button>
                </div>
              )}
            </Show>
          </div>
        </Match>
        <Match when={view() && party() && phase() !== 'ended' && party()}>
          {(p) => (
            <div class="flex flex-wrap items-center gap-4">
              <Poster
                url={p().title.posterUrl}
                kind={kindOf(p().title.type, p().title.isAnime)}
                class="w-12 shrink-0"
              />
              <div class="min-w-0 flex-1">
                <p class="eyebrow text-accent">
                  {phaseLabel(phase() ?? 'lobby')}
                </p>
                <p class="truncate font-display text-lg leading-tight font-medium">
                  {p().title.title}
                  <Show when={targetLine()}>
                    {(code) => (
                      <span class="ml-1.5 font-sans text-sm text-muted">
                        {code()}
                      </span>
                    )}
                  </Show>
                </p>
                <p class="mt-0.5 truncate text-xs text-muted">
                  <Show when={p().host}>
                    {(host) => <>Hosted by @{host().handle} · </>}
                  </Show>
                  <Show
                    when={p().ready.length > 0}
                    fallback={'Nobody has joined yet'}
                  >
                    Joined:{' '}
                    {p()
                      .ready.map((u) => u.displayName ?? `@${u.handle}`)
                      .join(', ')}
                  </Show>
                </p>
              </div>
              <Switch>
                <Match when={phase() === 'countdown'}>
                  <p
                    role="timer"
                    aria-live="assertive"
                    class="font-display text-5xl leading-none font-medium tabular-nums"
                  >
                    {secondsLeft()}
                  </p>
                </Match>
                <Match when={phase() === 'lobby'}>
                  <div class="flex flex-wrap items-center gap-2">
                    <Button
                      variant={ready() ? 'soft' : 'outline'}
                      size="sm"
                      aria-pressed={ready()}
                      disabled={busy()}
                      onClick={() =>
                        void act(() =>
                          setWatchPartyReady({
                            data: { ...ref(), ready: !ready() },
                          }),
                        )
                      }
                      class={ready() ? 'bg-accent/15 text-accent' : ''}
                    >
                      {ready() ? "I'm ready ✓" : "I'm ready"}
                    </Button>
                    <Show when={hosting()}>
                      <Segmented
                        label="Countdown"
                        options={COUNTDOWNS}
                        value={String(countdown())}
                        onChange={(value) => setCountdown(Number(value))}
                        itemClass="min-h-8 px-3 text-sm"
                      />
                      <Button
                        size="sm"
                        disabled={busy()}
                        onClick={() =>
                          void act(() =>
                            startWatchParty({
                              data: { ...ref(), countdownSeconds: countdown() },
                            }),
                          )
                        }
                      >
                        Start countdown
                      </Button>
                    </Show>
                  </div>
                </Match>
                <Match when={phase() === 'live'}>
                  <div
                    class="flex items-center gap-1"
                    role="group"
                    aria-label="React"
                  >
                    <For each={REACTIONS}>
                      {(emoji) => (
                        <Button
                          variant="ghost"
                          size="bare"
                          onClick={() => react(emoji)}
                          aria-label={`React ${emoji}`}
                          class="size-9 text-xl font-normal hover:bg-paper"
                        >
                          {emoji}
                        </Button>
                      )}
                    </For>
                  </div>
                </Match>
              </Switch>
              <div class="flex items-center gap-2">
                <Show when={phase() === 'live'}>{mine()}</Show>
                <Show when={hosting()}>
                  <Button
                    variant="ghost"
                    size="sm"
                    disabled={busy()}
                    onClick={() =>
                      void act(() => endWatchParty({ data: ref() }))
                    }
                    class="px-3"
                  >
                    End {word().toLowerCase()}
                  </Button>
                </Show>
              </div>
              <Show
                when={ready()}
                fallback={
                  <Show when={phase() === 'lobby'}>
                    <p class="w-full text-xs text-muted">
                      Joining means that when the host ends, this is marked in
                      your library. You can switch that off, and undo it after.
                    </p>
                  </Show>
                }
              >
                <Toggle
                  class="flex w-full items-start gap-3 text-sm"
                  checked={view()?.autoMark ?? true}
                  disabled={busy()}
                  onChange={(next) =>
                    void act(() =>
                      setWatchPartyReady({
                        data: { ...ref(), ready: true, autoMark: next },
                      }),
                    )
                  }
                >
                  <SwitchInput />
                  <SwitchControl>
                    <SwitchThumb />
                  </SwitchControl>
                  <span>
                    <SwitchLabel class="cursor-pointer">
                      Mark it for me
                    </SwitchLabel>
                    <SwitchDescription class="block text-xs">
                      When the host ends, this is marked in your library. You
                      can undo it after.
                    </SwitchDescription>
                  </span>
                </Toggle>
              </Show>
            </div>
          )}
        </Match>
        <Match when={view()}>
          <div class="flex flex-wrap items-center gap-3">
            <Show
              when={party()}
              fallback={
                <p class="min-w-0 flex-1 text-sm text-muted">
                  Pick something to watch or read, count down together, react as
                  it goes. When the host ends, it is marked for everyone who
                  joined.
                </p>
              }
            >
              {(p) => (
                <p class="min-w-0 flex-1 truncate text-sm text-muted">
                  Last {word().toLowerCase()}:{' '}
                  <span class="font-medium text-ink">{p().title.title}</span>
                  <Show when={targetLine()}> {targetLine()}</Show>
                </p>
              )}
            </Show>
            <Show when={party()}>{mine()}</Show>
            <Button size="sm" onClick={() => setPicking(true)}>
              Start a watch party
            </Button>
          </div>
        </Match>
      </Switch>
      <Show when={problem()}>
        {(text) => (
          <p role="alert" class="mt-2 text-sm text-danger">
            {text()}
          </p>
        )}
      </Show>
      <div
        aria-hidden="true"
        class="pointer-events-none absolute right-6 bottom-2 flex gap-1"
      >
        <For each={floating()}>
          {(f) => <span class="reaction-float text-2xl">{f.emoji}</span>}
        </For>
      </div>
      <Show when={floating().length > 0}>
        <span class="sr-only" aria-live="polite">
          {floating().at(-1)?.emoji}
        </span>
      </Show>
    </section>
  )
}
