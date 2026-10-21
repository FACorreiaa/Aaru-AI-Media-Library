import { For, Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  handleProblem,
  monogram,
  normalizeHandle,
  personLabel,
  requestOutcome,
} from '../lib/social/model'
import {
  acceptFriendRequest,
  blockUser,
  loadSocial,
  removeFriend,
  saveProfile,
  sendFriendRequest,
  unblockUser,
  withdrawFriendRequest,
} from '../lib/social/server'
import type { SocialState, SocialUser } from '../lib/social/server'
import { InviteFriends } from './InviteFriends'

// SOC-001 / SOC-002: a handle, friends by exact handle, requests both ways, and blocks. Nobody
// can browse or search for anyone; you add a friend by typing their handle.
export function SocialSection(props: {
  handle?: string
  displayName?: string
  state: SocialState
  onProfileSaved: (user: SocialUser) => void
}) {
  const [state, setState] = createSignal(props.state)
  const [handle, setHandle] = createSignal(props.handle)
  const [editing, setEditing] = createSignal(!props.handle)
  const [draftHandle, setDraftHandle] = createSignal(props.handle ?? '')
  const [draftName, setDraftName] = createSignal(props.displayName ?? '')
  const [friendHandle, setFriendHandle] = createSignal('')
  const [confirmBlock, setConfirmBlock] = createSignal<string | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [notice, setNotice] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function run(action: () => Promise<void>, fallback: string) {
    setBusy(true)
    setProblem(null)
    setNotice(null)
    try {
      await action()
    } catch (error) {
      setProblem(error instanceof Error ? error.message : fallback)
    } finally {
      setBusy(false)
    }
  }

  const refresh = async () => setState(await loadSocial())

  function save(event: SubmitEvent) {
    event.preventDefault()
    const invalid = handleProblem(draftHandle())
    if (invalid) return setProblem(invalid)
    void run(async () => {
      const user = await saveProfile({
        data: {
          handle: normalizeHandle(draftHandle()),
          displayName: draftName(),
        },
      })
      setHandle(user.handle)
      setEditing(false)
      props.onProfileSaved(user)
    }, 'Your handle was not saved.')
  }

  function ask(event: SubmitEvent) {
    event.preventDefault()
    const invalid = handleProblem(friendHandle())
    if (invalid) return setProblem(invalid)
    void run(async () => {
      const view = await sendFriendRequest({
        data: { handle: normalizeHandle(friendHandle()) },
      })
      setFriendHandle('')
      await refresh()
      setNotice(requestOutcome(view.user, view.relationship))
    }, 'That request was not sent.')
  }

  return (
    <section
      id="profile"
      class="mt-10 scroll-mt-6 rounded-[20px] bg-surface p-5"
    >
      <h2 class="font-display text-xl font-medium">Profile and friends</h2>
      <p class="mt-2 max-w-[60ch] text-sm text-muted">
        Friends join with your invite link or find you by your exact handle.
        Nobody can search or browse for you, and your library stays private.
      </p>

      <Show
        when={!editing() && handle()}
        fallback={
          <form class="mt-4 flex flex-col gap-3" onSubmit={save}>
            <label class="flex flex-col gap-1 text-sm">
              <span class="font-medium">Handle</span>
              <span class="flex max-w-xs items-center rounded-[14px] border border-line bg-paper px-3">
                <span class="text-muted">@</span>
                <input
                  class="min-h-11 w-full bg-transparent px-1 outline-none"
                  autocomplete="username"
                  autocapitalize="none"
                  spellcheck={false}
                  maxLength={21}
                  value={draftHandle()}
                  onInput={(e) => setDraftHandle(e.currentTarget.value)}
                />
              </span>
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="font-medium">
                Name <span class="font-normal text-muted">(optional)</span>
              </span>
              <input
                class="min-h-11 max-w-xs rounded-[14px] border border-line bg-paper px-3 outline-none"
                autocomplete="name"
                maxLength={50}
                value={draftName()}
                onInput={(e) => setDraftName(e.currentTarget.value)}
              />
            </label>
            <div class="flex gap-2">
              <button
                type="submit"
                class="min-h-11 rounded-full bg-accent px-5 text-sm font-semibold text-on-accent disabled:opacity-50"
                disabled={busy()}
              >
                {handle() ? 'Save' : 'Choose handle'}
              </button>
              <Show when={handle()}>
                <button
                  type="button"
                  class="min-h-11 rounded-full border border-ink/25 px-5 text-sm font-semibold"
                  onClick={() => setEditing(false)}
                >
                  Cancel
                </button>
              </Show>
            </div>
          </form>
        }
      >
        <div class="mt-4 flex items-center gap-3 text-sm">
          <span class="text-muted">Your handle</span>
          <span class="font-medium">@{handle()}</span>
          <button
            type="button"
            class="text-sm font-semibold text-accent hover:underline"
            onClick={() => {
              setDraftHandle(handle() ?? '')
              setEditing(true)
            }}
          >
            Change
          </button>
        </div>
      </Show>

      <Show when={handle()}>
        <InviteFriends />
        <form class="mt-6 flex flex-wrap items-end gap-2" onSubmit={ask}>
          <label class="flex flex-col gap-1 text-sm">
            <span class="font-medium">Add a friend</span>
            <span class="flex w-64 max-w-full items-center rounded-[14px] border border-line bg-paper px-3">
              <span class="text-muted">@</span>
              <input
                class="min-h-11 w-full bg-transparent px-1 outline-none"
                placeholder="their handle"
                autocapitalize="none"
                spellcheck={false}
                value={friendHandle()}
                onInput={(e) => setFriendHandle(e.currentTarget.value)}
              />
            </span>
          </label>
          <button
            type="submit"
            class="min-h-11 rounded-full border border-ink/25 px-5 text-sm font-semibold disabled:opacity-50"
            disabled={busy() || friendHandle().trim() === ''}
          >
            Send request
          </button>
        </form>
      </Show>

      <Show when={notice()}>
        {(message) => (
          <p role="status" class="mt-3 text-sm">
            {message()}
          </p>
        )}
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>

      <Show when={state().incoming.length > 0}>
        <People title={`Asking you (${state().incoming.length})`}>
          <For each={state().incoming}>
            {(request) => (
              <Person user={request.user}>
                <SmallButton
                  primary
                  disabled={busy()}
                  onClick={() =>
                    void run(async () => {
                      const friend = await acceptFriendRequest({
                        data: { id: request.id },
                      })
                      await refresh()
                      setNotice(`You and @${friend.handle} are friends.`)
                    }, 'That request could not be accepted.')
                  }
                >
                  Accept
                </SmallButton>
                <SmallButton
                  disabled={busy()}
                  onClick={() =>
                    void run(async () => {
                      await withdrawFriendRequest({ data: { id: request.id } })
                      await refresh()
                    }, 'That request is already gone.')
                  }
                >
                  Decline
                </SmallButton>
              </Person>
            )}
          </For>
        </People>
      </Show>

      <Show when={state().outgoing.length > 0}>
        <People title={`Waiting on (${state().outgoing.length})`}>
          <For each={state().outgoing}>
            {(request) => (
              <Person user={request.user}>
                <SmallButton
                  disabled={busy()}
                  onClick={() =>
                    void run(async () => {
                      await withdrawFriendRequest({ data: { id: request.id } })
                      await refresh()
                    }, 'That request is already gone.')
                  }
                >
                  Cancel
                </SmallButton>
              </Person>
            )}
          </For>
        </People>
      </Show>

      <Show when={handle()}>
        <People title={`Friends (${state().friends.length})`}>
          <Show
            when={state().friends.length > 0}
            fallback={
              <li class="py-3 text-sm text-muted">
                No friends yet. Send someone an invite link, or ask for their
                handle.
              </li>
            }
          >
            <For each={state().friends}>
              {(friend) => (
                <Person user={friend}>
                  <Show
                    when={confirmBlock() === friend.userId}
                    fallback={
                      <>
                        <SmallButton
                          disabled={busy()}
                          onClick={() =>
                            void run(async () => {
                              await removeFriend({
                                data: { userId: friend.userId },
                              })
                              await refresh()
                            }, 'That friend was not removed.')
                          }
                        >
                          Remove
                        </SmallButton>
                        <SmallButton
                          danger
                          onClick={() => setConfirmBlock(friend.userId)}
                        >
                          Block
                        </SmallButton>
                      </>
                    }
                  >
                    <span class="text-xs text-muted">They won't be told.</span>
                    <SmallButton
                      danger
                      disabled={busy()}
                      onClick={() =>
                        void run(async () => {
                          await blockUser({ data: { userId: friend.userId } })
                          setConfirmBlock(null)
                          await refresh()
                        }, 'That person was not blocked.')
                      }
                    >
                      Block @{friend.handle}
                    </SmallButton>
                    <SmallButton onClick={() => setConfirmBlock(null)}>
                      Keep
                    </SmallButton>
                  </Show>
                </Person>
              )}
            </For>
          </Show>
        </People>
      </Show>

      <Show when={state().blocked.length > 0}>
        <details class="mt-6">
          <summary class="cursor-pointer text-sm font-semibold">
            Blocked ({state().blocked.length})
          </summary>
          <ul class="mt-2 divide-y divide-line">
            <For each={state().blocked}>
              {(person) => (
                <Person user={person}>
                  <SmallButton
                    disabled={busy()}
                    onClick={() =>
                      void run(async () => {
                        await unblockUser({ data: { userId: person.userId } })
                        await refresh()
                      }, 'That person was not unblocked.')
                    }
                  >
                    Unblock
                  </SmallButton>
                </Person>
              )}
            </For>
          </ul>
        </details>
      </Show>
    </section>
  )
}

function People(props: { title: string; children: JSX.Element }) {
  return (
    <div class="mt-6">
      <h3 class="text-sm font-semibold">{props.title}</h3>
      <ul class="mt-1 divide-y divide-line">{props.children}</ul>
    </div>
  )
}

function Person(props: { user: SocialUser; children: JSX.Element }) {
  return (
    <li class="flex flex-wrap items-center justify-between gap-3 py-3">
      <span class="flex min-w-0 items-center gap-3">
        <span
          aria-hidden="true"
          class="grid size-9 shrink-0 place-items-center rounded-full bg-medallion/20 font-display text-sm font-medium"
        >
          {monogram(props.user)}
        </span>
        <span class="truncate text-sm font-medium">
          {personLabel(props.user)}
        </span>
      </span>
      <span class="flex items-center gap-2">{props.children}</span>
    </li>
  )
}

function SmallButton(props: {
  onClick: () => void
  children: JSX.Element
  disabled?: boolean
  primary?: boolean
  danger?: boolean
}) {
  const tone = () =>
    props.primary
      ? 'bg-accent text-on-accent'
      : props.danger
        ? 'border border-danger/50 text-danger'
        : 'border border-ink/25'
  return (
    <button
      type="button"
      class={`min-h-9 rounded-full px-4 text-sm font-semibold disabled:opacity-50 ${tone()}`}
      disabled={props.disabled}
      onClick={() => props.onClick()}
    >
      {props.children}
    </button>
  )
}
