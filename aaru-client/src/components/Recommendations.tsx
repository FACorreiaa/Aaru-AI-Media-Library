import { For, Show, createSignal, onMount } from 'solid-js'
import { kindOf, statusLabel } from '../lib/library/model'
import type { CatalogHit } from '../lib/library/model'
import { searchCatalog } from '../lib/library/server'
import { listGroups, inviteToGroup } from '../lib/groups/server'
import type { GroupSummary } from '../lib/groups/server'
import { inviterName, monogram } from '../lib/social/model'
import {
  answerRecommendation,
  loadSocial,
  recommend,
} from '../lib/social/server'
import type {
  MediaRef,
  RecommendationItem,
  SocialUser,
} from '../lib/social/server'
import { Poster } from './Poster'
import { Button } from './ui/button'
import { Dialog } from './ui/dialog'

// SOC-006: titles friends sent you, at the top of Friends. One tap puts it on Plan to watch,
// the same write as Add; Dismiss lets it go. Neither side is told.
export function RecommendationInbox(props: { items: RecommendationItem[] }) {
  const [items, setItems] = createSignal(props.items)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function answer(item: RecommendationItem, add: boolean) {
    const before = items()
    setItems(items().filter((i) => i.id !== item.id))
    setProblem(null)
    try {
      await answerRecommendation({ data: { id: item.id, add } })
    } catch (error) {
      setItems(before)
      setProblem(error instanceof Error ? error.message : 'That was not saved.')
    }
  }

  return (
    <Show when={items().length > 0}>
      <section aria-labelledby="for-you" class="mt-8">
        <h2 id="for-you" class="font-display text-xl font-medium">
          For you from friends
        </h2>
        <ul class="mt-2 divide-y divide-line">
          <For each={items()}>
            {(item) => {
              const kind = kindOf(item.title.type, item.title.isAnime)
              return (
                <li class="flex gap-4 py-4">
                  <Poster
                    url={item.title.posterUrl}
                    kind={kind}
                    radius="thumb"
                    class="w-16 shrink-0"
                  />
                  <div class="min-w-0 flex-1">
                    <p class="text-sm">
                      <span class="font-medium">{inviterName(item.from)}</span>{' '}
                      recommends{' '}
                      <span class="font-medium">{item.title.title}</span>
                    </p>
                    <Show when={item.note}>
                      {(note) => (
                        <p class="mt-1 font-display text-base italic">
                          “{note()}”
                        </p>
                      )}
                    </Show>
                    <div class="mt-3 flex flex-wrap gap-2">
                      <Button
                        variant="primary"
                        size="sm"
                        onClick={() => void answer(item, true)}
                      >
                        Add to {statusLabel('wishlist', kind)}
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => void answer(item, false)}
                      >
                        Dismiss
                      </Button>
                    </div>
                  </div>
                </li>
              )
            }}
          </For>
        </ul>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
      </section>
    </Show>
  )
}

type Picked = {
  ref: MediaRef
  name: string
  posterUrl?: string
  kind: ReturnType<typeof kindOf>
}

/**
 * Sends one title to friends (SOC-006). From a title page the title is fixed and you pick
 * friends; from a friend's profile the friend is fixed and you find a title.
 */
export function RecommendDialog(props: {
  title?: Picked
  friend?: SocialUser
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [title, setTitle] = createSignal<Picked | null>(props.title ?? null)
  const [friends, setFriends] = createSignal<SocialUser[] | null>(
    props.friend ? [props.friend] : null,
  )
  const [chosen, setChosen] = createSignal<Set<string>>(
    new Set(props.friend ? [props.friend.userId] : []),
  )
  const [query, setQuery] = createSignal('')
  const [hits, setHits] = createSignal<CatalogHit[]>([])
  const [note, setNote] = createSignal('')
  const [busy, setBusy] = createSignal(false)
  const [sent, setSent] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  onMount(async () => {
    if (props.friend) return
    try {
      setFriends((await loadSocial()).friends)
    } catch (error) {
      setFriends([])
      setProblem(
        error instanceof Error
          ? error.message
          : 'Your friends could not be loaded.',
      )
    }
  })

  async function search(event: SubmitEvent) {
    event.preventDefault()
    if (query().trim().length < 2) return
    try {
      const results = await searchCatalog({
        data: { q: query().trim(), type: 'all' },
      })
      setHits(results.items.slice(0, 5))
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Search is not available.',
      )
    }
  }

  function toggle(id: string) {
    const next = new Set(chosen())
    if (next.has(id)) next.delete(id)
    else if (next.size < 10) next.add(id)
    setChosen(next)
  }

  async function send() {
    const picked = title()
    if (!picked || chosen().size === 0 || busy()) return
    setBusy(true)
    setProblem(null)
    try {
      await recommend({
        data: {
          to: [...chosen()],
          title: picked.ref,
          note: note().trim() || undefined,
        },
      })
      setSent(true)
    } catch (error) {
      setProblem(error instanceof Error ? error.message : 'It was not sent.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog
      ref={dialog}
      openOnMount
      placement="sheet"
      aria-label="Recommend a title"
      class="w-[min(28rem,calc(100vw-2rem))]"
      onClose={() => props.onClose()}
    >
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 class="font-display text-xl font-medium">
          {props.friend
            ? `Recommend to ${inviterName(props.friend)}`
            : 'Recommend'}
        </h2>
        <Button
          variant="ghost"
          size="bare"
          class="text-sm"
          onClick={() => dialog?.close()}
        >
          {sent() ? 'Done' : 'Cancel'}
        </Button>
      </div>
      <div class="max-h-[70dvh] overflow-y-auto px-5 py-4">
        <Show
          when={!sent()}
          fallback={
            <p class="py-6 text-center text-sm">
              Sent. It waits at the top of their Friends.
            </p>
          }
        >
          <Show
            when={title()}
            fallback={
              <>
                <form class="flex gap-2" onSubmit={(e) => void search(e)}>
                  <label for="recommend-search" class="sr-only">
                    Find a title
                  </label>
                  <input
                    id="recommend-search"
                    type="search"
                    placeholder="A film, show or book"
                    value={query()}
                    onInput={(e) => setQuery(e.currentTarget.value)}
                    class="min-h-10 flex-1 rounded-full border-0 bg-surface px-4 text-sm focus:ring-2 focus:ring-accent"
                  />
                  <Button
                    type="submit"
                    size="sm"
                    disabled={query().trim().length < 2}
                  >
                    Find
                  </Button>
                </form>
                <ul class="mt-2 divide-y divide-line">
                  <For each={hits()}>
                    {(hit) => (
                      <li>
                        <button
                          type="button"
                          class="flex min-h-12 w-full items-center gap-3 py-2 text-left text-sm hover:bg-surface"
                          onClick={() =>
                            setTitle({
                              ref: {
                                type: hit.type,
                                ids: hit.ids,
                                title: hit.title,
                                year: hit.year,
                              },
                              name: hit.title,
                              posterUrl: hit.posterUrl,
                              kind: kindOf(hit.type, hit.isAnime),
                            })
                          }
                        >
                          <Poster
                            url={hit.posterUrl}
                            kind={kindOf(hit.type, hit.isAnime)}
                            radius="thumb"
                            class="w-8 shrink-0"
                          />
                          <span class="min-w-0 truncate font-medium">
                            {hit.title}
                          </span>
                          <Show when={hit.year}>
                            <span class="text-muted">{hit.year}</span>
                          </Show>
                        </button>
                      </li>
                    )}
                  </For>
                </ul>
              </>
            }
          >
            {(picked) => (
              <div class="flex items-center gap-3">
                <Poster
                  url={picked().posterUrl}
                  kind={picked().kind}
                  radius="thumb"
                  class="w-12 shrink-0"
                />
                <p class="min-w-0 flex-1 font-medium">{picked().name}</p>
                <Show when={!props.title}>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setTitle(null)}
                  >
                    Change
                  </Button>
                </Show>
              </div>
            )}
          </Show>

          <Show when={!props.friend}>
            <h3 class="mt-5 text-sm font-semibold">To</h3>
            <Show
              when={(friends() ?? []).length > 0}
              fallback={
                <p class="mt-1 text-sm text-muted">
                  {friends() === null
                    ? 'Loading…'
                    : 'No friends yet. Invite someone from Friends.'}
                </p>
              }
            >
              <ul class="mt-1">
                <For each={friends() ?? []}>
                  {(friend) => (
                    <li>
                      <label class="flex min-h-11 cursor-pointer items-center gap-3 text-sm">
                        <input
                          type="checkbox"
                          checked={chosen().has(friend.userId)}
                          onChange={() => toggle(friend.userId)}
                          class="size-5 accent-[var(--accent)]"
                        />
                        <span
                          aria-hidden="true"
                          class="grid size-8 place-items-center rounded-full bg-medallion/20 font-display text-xs font-medium"
                        >
                          {monogram(friend)}
                        </span>
                        {inviterName(friend)}
                      </label>
                    </li>
                  )}
                </For>
              </ul>
            </Show>
          </Show>

          <label for="recommend-note" class="mt-5 block text-sm font-semibold">
            Note <span class="font-normal text-muted">(optional)</span>
          </label>
          <input
            id="recommend-note"
            maxLength={140}
            placeholder="Why they’ll love it"
            value={note()}
            onInput={(e) => setNote(e.currentTarget.value)}
            class="mt-1 min-h-11 w-full rounded-[14px] border border-line bg-surface px-3 text-sm outline-none focus:ring-2 focus:ring-accent"
          />
          <Button
            variant="primary"
            class="mt-5 w-full"
            disabled={busy() || !title() || chosen().size === 0}
            onClick={() => void send()}
          >
            {busy() ? 'Sending…' : 'Send'}
          </Button>
        </Show>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
      </div>
    </Dialog>
  )
}

/** Invites a friend into one of your groups, from their profile (existing group invites). */
export function GroupInviteDialog(props: {
  friend: SocialUser
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [groups, setGroups] = createSignal<GroupSummary[] | null>(null)
  const [done, setDone] = createSignal<Set<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)

  onMount(async () => {
    try {
      setGroups(await listGroups())
    } catch (error) {
      setGroups([])
      setProblem(
        error instanceof Error
          ? error.message
          : 'Your groups could not be loaded.',
      )
    }
  })

  async function invite(group: GroupSummary) {
    setProblem(null)
    try {
      await inviteToGroup({
        data: { groupId: group.id, userId: props.friend.userId },
      })
      setDone(new Set([...done(), group.id]))
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That invite was not sent.',
      )
    }
  }

  return (
    <Dialog
      ref={dialog}
      openOnMount
      aria-label={`Invite ${inviterName(props.friend)} to a group`}
      class="w-[min(26rem,calc(100vw-2rem))]"
      onClose={() => props.onClose()}
    >
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 class="font-display text-xl font-medium">Invite to a group</h2>
        <Button
          variant="ghost"
          size="bare"
          class="text-sm"
          onClick={() => dialog?.close()}
        >
          Done
        </Button>
      </div>
      <ul class="max-h-80 overflow-y-auto px-3 py-3">
        <Show when={groups() === null}>
          <li class="px-2 py-4 text-sm text-muted">Loading…</li>
        </Show>
        <Show when={groups()?.length === 0}>
          <li class="px-2 py-4 text-sm text-muted">
            You have no groups yet. Start one from Groups.
          </li>
        </Show>
        <For each={groups() ?? []}>
          {(group) => (
            <li class="flex items-center justify-between gap-3 rounded-[12px] px-2 py-2">
              <span class="truncate text-sm font-medium">{group.name}</span>
              <Button
                size="sm"
                variant={done().has(group.id) ? 'ghost' : 'outline'}
                disabled={done().has(group.id)}
                onClick={() => void invite(group)}
              >
                {done().has(group.id) ? 'Invited' : 'Invite'}
              </Button>
            </li>
          )}
        </For>
      </ul>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="px-5 pb-4 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </Dialog>
  )
}
