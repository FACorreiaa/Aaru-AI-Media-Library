import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  Button,
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
  TextField,
  TextFieldInput,
  TextFieldLabel,
  buttonVariants,
} from '~/components/ui'
import {
  handleProblem,
  monogram,
  normalizeHandle,
  personLabel,
  requestOutcome,
} from '../../lib/social/model'
import {
  acceptFriendRequest,
  blockUser,
  loadSocial,
  removeFriend,
  sendFriendRequest,
  unblockUser,
  withdrawFriendRequest,
} from '../../lib/social/server'
import type { SocialState, SocialUser } from '../../lib/social/server'
import { InviteFriends } from '../InviteFriends'
import { SettingsSection } from './SettingsSection'

// SOC-001 / SOC-002 on the Friends page: invite links, friends by exact handle, requests both ways, and
// blocks. Nobody can browse or search for anyone; you add a friend by typing their handle.
export function FriendsSection(props: { handle?: string; state: SocialState }) {
  const [state, setState] = createSignal(props.state)
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
    <>
      <Show
        when={props.handle}
        fallback={
          <SettingsSection
            title="Add a friend"
            description="Choose a handle first: it is how friends find you."
          >
            <Link
              to="/app/settings/account"
              class={buttonVariants({ variant: 'default' })}
            >
              Choose a handle
            </Link>
          </SettingsSection>
        }
      >
        <InviteFriends />
        <SettingsSection
          id="add-friend"
          title="Add a friend"
          description={`You are @${props.handle}. Friends join with your invite link, or find you by your exact handle.`}
        >
          <form class="flex flex-wrap items-end gap-2" onSubmit={ask}>
            <TextField
              class="w-64 max-w-full gap-1.5"
              value={friendHandle()}
              onChange={setFriendHandle}
            >
              <TextFieldLabel>Their handle</TextFieldLabel>
              <div class="relative">
                <span
                  aria-hidden="true"
                  class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted"
                >
                  @
                </span>
                <TextFieldInput
                  class="w-full pl-7"
                  autocapitalize="none"
                  spellcheck={false}
                />
              </div>
            </TextField>
            <Button
              type="submit"
              variant="outline"
              disabled={busy() || friendHandle().trim() === ''}
            >
              Send request
            </Button>
          </form>
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
        </SettingsSection>
      </Show>

      <Show when={state().incoming.length > 0}>
        <SettingsSection title={`Asking you (${state().incoming.length})`}>
          <People>
            <For each={state().incoming}>
              {(request) => (
                <Person user={request.user}>
                  <Button
                    size="sm"
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
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={busy()}
                    onClick={() =>
                      void run(async () => {
                        await withdrawFriendRequest({
                          data: { id: request.id },
                        })
                        await refresh()
                      }, 'That request is already gone.')
                    }
                  >
                    Decline
                  </Button>
                </Person>
              )}
            </For>
          </People>
        </SettingsSection>
      </Show>

      <Show when={state().outgoing.length > 0}>
        <SettingsSection title={`Waiting on (${state().outgoing.length})`}>
          <People>
            <For each={state().outgoing}>
              {(request) => (
                <Person user={request.user}>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={busy()}
                    onClick={() =>
                      void run(async () => {
                        await withdrawFriendRequest({
                          data: { id: request.id },
                        })
                        await refresh()
                      }, 'That request is already gone.')
                    }
                  >
                    Cancel
                  </Button>
                </Person>
              )}
            </For>
          </People>
        </SettingsSection>
      </Show>

      <Show when={props.handle}>
        <SettingsSection
          id="friends"
          title={`Friends (${state().friends.length})`}
        >
          <Show
            when={state().friends.length > 0}
            fallback={
              <p class="text-sm text-muted">
                No friends yet. Send someone an invite link, or ask for their
                handle.
              </p>
            }
          >
            <People>
              <For each={state().friends}>
                {(friend) => (
                  <Person user={friend} profile>
                    <Show
                      when={confirmBlock() === friend.userId}
                      fallback={
                        <>
                          <Button
                            size="sm"
                            variant="outline"
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
                          </Button>
                          <Button
                            size="sm"
                            variant="danger-outline"
                            onClick={() => setConfirmBlock(friend.userId)}
                          >
                            Block
                          </Button>
                        </>
                      }
                    >
                      <span class="text-xs text-muted">
                        They won't be told.
                      </span>
                      <Button
                        size="sm"
                        variant="danger-outline"
                        disabled={busy()}
                        onClick={() =>
                          void run(async () => {
                            await blockUser({
                              data: { userId: friend.userId },
                            })
                            setConfirmBlock(null)
                            await refresh()
                          }, 'That person was not blocked.')
                        }
                      >
                        Block @{friend.handle}
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => setConfirmBlock(null)}
                      >
                        Keep
                      </Button>
                    </Show>
                  </Person>
                )}
              </For>
            </People>
          </Show>
        </SettingsSection>
      </Show>

      <Show when={state().blocked.length > 0}>
        <SettingsSection title="Blocked">
          <Collapsible>
            <CollapsibleTrigger
              class={buttonVariants({ variant: 'outline', size: 'sm' })}
            >
              Show {state().blocked.length} blocked
            </CollapsibleTrigger>
            <CollapsibleContent>
              <People>
                <For each={state().blocked}>
                  {(person) => (
                    <Person user={person}>
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={busy()}
                        onClick={() =>
                          void run(async () => {
                            await unblockUser({
                              data: { userId: person.userId },
                            })
                            await refresh()
                          }, 'That person was not unblocked.')
                        }
                      >
                        Unblock
                      </Button>
                    </Person>
                  )}
                </For>
              </People>
            </CollapsibleContent>
          </Collapsible>
        </SettingsSection>
      </Show>
    </>
  )
}

function People(props: { children: JSX.Element }) {
  return <ul class="-my-3 divide-y divide-line">{props.children}</ul>
}

/** One person in a list; a friend's name opens their profile (SOC-001/003). */
function Person(props: {
  user: SocialUser
  children: JSX.Element
  profile?: boolean
}) {
  const who = (
    <>
      <span
        aria-hidden="true"
        class="grid size-9 shrink-0 place-items-center rounded-full bg-medallion/20 font-display text-sm font-medium"
      >
        {monogram(props.user)}
      </span>
      <span class="truncate text-sm font-medium">
        {personLabel(props.user)}
      </span>
    </>
  )
  return (
    <li class="flex flex-wrap items-center justify-between gap-3 py-3">
      <Show
        when={props.profile}
        fallback={<span class="flex min-w-0 items-center gap-3">{who}</span>}
      >
        <Link
          to="/app/friends/$handle"
          params={{ handle: props.user.handle }}
          class="flex min-w-0 items-center gap-3 rounded-full hover:text-accent"
        >
          {who}
        </Link>
      </Show>
      <span class="flex flex-wrap items-center gap-2">{props.children}</span>
    </li>
  )
}
