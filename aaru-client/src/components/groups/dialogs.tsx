import { For, Show, createSignal, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { loadSocial } from '../../lib/social/server'
import type { SocialUser } from '../../lib/social/server'
import { monogram, personLabel } from '../../lib/social/model'
import { inviteToGroup } from '../../lib/groups/server'
import type { Channel, GroupDetail } from '../../lib/groups/server'
import { Monogram } from './shell'

// The groups dialogs: name a group, make or edit a channel, invite friends, confirm. Each is
// mounted when needed and opens as a modal on mount, like the episode sheet.

const dialogClass =
  'm-auto w-[min(28rem,calc(100vw-2rem))] rounded-[20px] bg-paper p-0 text-ink shadow-2xl backdrop:bg-black/40'
const inputClass =
  'mt-1 min-h-11 w-full rounded-xl border-0 bg-surface px-4 text-base focus:ring-2 focus:ring-accent'

function message(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback
}

function Frame(props: {
  label: string
  title: string
  onClose: () => void
  ref: (dialog: HTMLDialogElement) => void
  children: JSX.Element
}) {
  return (
    <dialog
      ref={props.ref}
      aria-label={props.label}
      class={dialogClass}
      onClose={() => props.onClose()}
    >
      <div class="px-5 pt-5 pb-5">
        <h2 class="font-display text-2xl font-medium">{props.title}</h2>
        {props.children}
      </div>
    </dialog>
  )
}

function Actions(props: {
  busy: boolean
  submit: string
  disabled?: boolean
  danger?: boolean
  onCancel: () => void
  extra?: JSX.Element
}) {
  return (
    <div class="mt-6 flex items-center justify-between gap-3">
      <div>{props.extra}</div>
      <div class="flex gap-2">
        <button
          type="button"
          onClick={() => props.onCancel()}
          class="rounded-full px-4 py-2 text-sm font-medium text-muted hover:text-ink"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={props.busy || props.disabled}
          class={`rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-40 ${props.danger ? 'bg-danger text-paper' : 'bg-accent text-on-accent'}`}
        >
          {props.submit}
        </button>
      </div>
    </div>
  )
}

/** One name field: create a group, or rename one. */
export function NameDialog(props: {
  title: string
  label: string
  initial?: string
  submit: string
  hint?: string
  onSubmit: (name: string) => Promise<void>
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [name, setName] = createSignal(props.initial ?? '')
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  onMount(() => dialog?.showModal())

  return (
    <Frame
      ref={(d) => (dialog = d)}
      label={props.title}
      title={props.title}
      onClose={props.onClose}
    >
      <form
        onSubmit={async (e) => {
          e.preventDefault()
          setBusy(true)
          setProblem(null)
          try {
            await props.onSubmit(name())
            dialog?.close()
          } catch (error) {
            setProblem(message(error, 'That was not saved.'))
          } finally {
            setBusy(false)
          }
        }}
      >
        <Show when={props.hint}>
          <p class="mt-2 text-sm text-muted">{props.hint}</p>
        </Show>
        <label class="mt-4 block text-sm font-medium">
          {props.label}
          <input
            value={name()}
            maxLength={50}
            autofocus
            onInput={(e) => setName(e.currentTarget.value)}
            class={inputClass}
          />
        </label>
        <Show when={problem()}>
          {(text) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {text()}
            </p>
          )}
        </Show>
        <Actions
          busy={busy()}
          submit={props.submit}
          disabled={!name().trim()}
          onCancel={() => dialog?.close()}
        />
      </form>
    </Frame>
  )
}

/** Make a text channel, or rename one and set its topic. */
export function ChannelDialog(props: {
  channel?: Channel
  onSubmit: (name: string, topic: string) => Promise<void>
  onDelete?: () => Promise<void>
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [name, setName] = createSignal(props.channel?.name ?? '')
  const [topic, setTopic] = createSignal(props.channel?.topic ?? '')
  const [busy, setBusy] = createSignal(false)
  const [confirming, setConfirming] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  onMount(() => dialog?.showModal())

  const preview = () =>
    name()
      .toLowerCase()
      .trim()
      .split(/[\s-]+/)
      .map((w) => w.replace(/[^\p{L}\p{N}_]/gu, ''))
      .filter(Boolean)
      .join('-')

  async function attempt(action: () => Promise<void>) {
    setBusy(true)
    setProblem(null)
    try {
      await action()
      dialog?.close()
    } catch (error) {
      setProblem(message(error, 'That was not saved.'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Frame
      ref={(d) => (dialog = d)}
      label={props.channel ? 'Edit channel' : 'New channel'}
      title={props.channel ? `#${props.channel.name}` : 'New channel'}
      onClose={props.onClose}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault()
          void attempt(() => props.onSubmit(name(), topic()))
        }}
      >
        <label class="mt-4 block text-sm font-medium">
          Name
          <div class="relative">
            <span
              aria-hidden="true"
              class="pointer-events-none absolute top-1/2 left-4 mt-0.5 -translate-y-1/2 text-muted"
            >
              #
            </span>
            <input
              value={name()}
              maxLength={40}
              autofocus
              placeholder="movie-night"
              onInput={(e) => setName(e.currentTarget.value)}
              class={`${inputClass} pl-8`}
            />
          </div>
        </label>
        <Show when={preview() && preview() !== name().trim()}>
          <p class="mt-1 text-xs text-muted">Saved as #{preview()}</p>
        </Show>
        <label class="mt-4 block text-sm font-medium">
          Topic <span class="font-normal text-muted">(optional)</span>
          <input
            value={topic()}
            maxLength={200}
            placeholder="What this channel is for"
            onInput={(e) => setTopic(e.currentTarget.value)}
            class={inputClass}
          />
        </label>
        <Show when={problem()}>
          {(text) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {text()}
            </p>
          )}
        </Show>
        <Actions
          busy={busy()}
          submit={props.channel ? 'Save' : 'Create'}
          disabled={!preview()}
          onCancel={() => dialog?.close()}
          extra={
            <Show when={props.onDelete}>
              {(remove) => (
                <Show
                  when={confirming()}
                  fallback={
                    <button
                      type="button"
                      onClick={() => setConfirming(true)}
                      class="text-sm font-medium text-danger"
                    >
                      Delete channel
                    </button>
                  }
                >
                  <button
                    type="button"
                    disabled={busy()}
                    onClick={() => void attempt(remove())}
                    class="text-sm font-semibold text-danger underline"
                  >
                    Delete it and its messages
                  </button>
                </Show>
              )}
            </Show>
          }
        />
      </form>
    </Frame>
  )
}

/** Friends to invite, with who is already in or invited. Only friends can be invited. */
export function InviteDialog(props: {
  detail: GroupDetail
  onInvited: () => Promise<void>
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [friends, setFriends] = createSignal<SocialUser[] | null>(null)
  const [sent, setSent] = createSignal<Set<string>>(new Set())
  const [busy, setBusy] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  onMount(async () => {
    dialog?.showModal()
    try {
      setFriends((await loadSocial()).friends)
    } catch (error) {
      setProblem(message(error, 'Your friends could not be loaded.'))
      setFriends([])
    }
  })

  const members = () => new Set(props.detail.members.map((m) => m.user.userId))
  const invited = () =>
    new Set([...props.detail.invited.map((u) => u.userId), ...sent()])

  async function invite(user: SocialUser) {
    setBusy(user.userId)
    setProblem(null)
    try {
      await inviteToGroup({
        data: { groupId: props.detail.group.id, userId: user.userId },
      })
      setSent(new Set([...sent(), user.userId]))
      await props.onInvited()
    } catch (error) {
      setProblem(message(error, 'That invite was not sent.'))
    } finally {
      setBusy(null)
    }
  }

  return (
    <Frame
      ref={(d) => (dialog = d)}
      label="Invite friends"
      title="Invite friends"
      onClose={props.onClose}
    >
      <p class="mt-2 text-sm text-muted">
        Only friends can join {props.detail.group.name}. They see an invite next
        time they open Groups.
      </p>
      <Show when={problem()}>
        {(text) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {text()}
          </p>
        )}
      </Show>
      <Show
        when={friends()}
        fallback={<p class="mt-6 text-sm text-muted">Loading friends…</p>}
      >
        {(list) => (
          <Show
            when={list().length > 0}
            fallback={
              <p class="mt-6 text-sm text-muted">
                No friends yet. Add friends by handle in{' '}
                <a href="/app/settings#profile" class="text-accent underline">
                  Settings
                </a>
                .
              </p>
            }
          >
            <ul class="mt-4 max-h-80 divide-y divide-line overflow-y-auto">
              <For each={list()}>
                {(friend) => (
                  <li class="flex items-center justify-between gap-3 py-2.5">
                    <span class="flex min-w-0 items-center gap-3">
                      <Monogram text={monogram(friend)} size="sm" />
                      <span class="truncate text-sm font-medium">
                        {personLabel(friend)}
                      </span>
                    </span>
                    <Show
                      when={!members().has(friend.userId)}
                      fallback={
                        <span class="text-xs text-muted">In group</span>
                      }
                    >
                      <Show
                        when={!invited().has(friend.userId)}
                        fallback={
                          <span class="text-xs text-muted">Invited</span>
                        }
                      >
                        <button
                          type="button"
                          disabled={busy() !== null}
                          onClick={() => void invite(friend)}
                          class="rounded-full bg-accent px-3 py-1 text-xs font-semibold text-on-accent disabled:opacity-40"
                        >
                          Invite
                        </button>
                      </Show>
                    </Show>
                  </li>
                )}
              </For>
            </ul>
          </Show>
        )}
      </Show>
      <div class="mt-6 flex justify-end">
        <button
          type="button"
          onClick={() => dialog?.close()}
          class="rounded-full bg-surface px-5 py-2 text-sm font-semibold"
        >
          Done
        </button>
      </div>
    </Frame>
  )
}

/** A yes-or-no for something that cannot be undone. */
export function ConfirmDialog(props: {
  title: string
  body: string
  confirm: string
  danger?: boolean
  onConfirm: () => Promise<void>
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  onMount(() => dialog?.showModal())
  return (
    <Frame
      ref={(d) => (dialog = d)}
      label={props.title}
      title={props.title}
      onClose={props.onClose}
    >
      <form
        onSubmit={async (e) => {
          e.preventDefault()
          setBusy(true)
          setProblem(null)
          try {
            await props.onConfirm()
            dialog?.close()
          } catch (error) {
            setProblem(message(error, 'That did not work.'))
          } finally {
            setBusy(false)
          }
        }}
      >
        <p class="mt-2 text-sm text-muted">{props.body}</p>
        <Show when={problem()}>
          {(text) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {text()}
            </p>
          )}
        </Show>
        <Actions
          busy={busy()}
          submit={props.confirm}
          danger={props.danger}
          onCancel={() => dialog?.close()}
        />
      </form>
    </Frame>
  )
}
