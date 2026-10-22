import { For, Show, children, createSignal, onCleanup, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { Link } from '@tanstack/solid-router'
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogPortal,
  DialogTitle,
  RadioGroup,
  RadioGroupItem,
  RadioGroupItemInput,
  RadioGroupItemLabel,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { ConfirmDialog as AskDialog } from '../ConfirmDialog'
import { loadSocial } from '../../lib/social/server'
import type { SocialUser } from '../../lib/social/server'
import { monogram, personLabel } from '../../lib/social/model'
import { inviteToGroup } from '../../lib/groups/server'
import type { Channel, GroupDetail } from '../../lib/groups/server'
import { KIND_OPTIONS, hitRef, kindGlyph } from '../../lib/groups/kinds'
import type { ChannelKind, MediaRef } from '../../lib/groups/kinds'
import { prefersReducedMotion } from '../../lib/reduced-motion'
import { Monogram } from './shell'
import { TitlePicker } from './TitlePicker'

// The groups dialogs: name a group, make or edit a channel, invite friends, confirm. Each is
// mounted when needed and opens on mount (WEB-002: shadcn-solid's Dialog, a bottom sheet on a
// phone). Closing plays Kobalte's exit first and then tells the owner, which unmounts it
// (WEB-011).

const inputClass = 'mt-1 w-full border-0 bg-surface px-4'

function message(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback
}

/** Open from mount; `close` lets the exit play, then calls `onClose`. */
export function useClosable(onClose: () => void) {
  const [open, setOpen] = createSignal(true)
  let timer: number | undefined
  onCleanup(() => window.clearTimeout(timer))
  const close = () => {
    if (!open()) return
    setOpen(false)
    // DialogContent's exit is 200ms; nothing moves under reduced motion.
    timer = window.setTimeout(() => onClose(), prefersReducedMotion() ? 0 : 200)
  }
  return { open, close }
}

function Frame(props: {
  open: boolean
  title: string
  description?: JSX.Element
  onClose: () => void
  children: JSX.Element
}) {
  // Resolved once: tested in `when` and shown in the body (see SettingsSection).
  const description = children(() => props.description)
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
          class="block w-[min(28rem,calc(100vw-2rem))] gap-0 p-5 sm:max-w-none"
        >
          <DialogTitle class="text-2xl">{props.title}</DialogTitle>
          <Show when={description()}>
            <DialogDescription class="mt-2">{description()}</DialogDescription>
          </Show>
          {props.children}
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}

function Problem(props: { text: string | null }) {
  return (
    <Show when={props.text}>
      {(text) => (
        <p role="alert" class="mt-3 text-sm text-danger">
          {text()}
        </p>
      )}
    </Show>
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
        <Button variant="ghost" size="sm" onClick={() => props.onCancel()}>
          Cancel
        </Button>
        <Button
          type="submit"
          size="sm"
          variant={props.danger ? 'destructive' : 'default'}
          disabled={props.busy || props.disabled}
        >
          {props.submit}
        </Button>
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
  const dialog = useClosable(() => props.onClose())
  const [name, setName] = createSignal(props.initial ?? '')
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  return (
    <Frame
      open={dialog.open()}
      title={props.title}
      description={props.hint}
      onClose={dialog.close}
    >
      <form
        onSubmit={async (e) => {
          e.preventDefault()
          setBusy(true)
          setProblem(null)
          try {
            await props.onSubmit(name())
            dialog.close()
          } catch (error) {
            setProblem(message(error, 'That was not saved.'))
          } finally {
            setBusy(false)
          }
        }}
      >
        <TextField value={name()} onChange={setName} class="mt-4 gap-0">
          <TextFieldLabel>{props.label}</TextFieldLabel>
          <TextFieldInput maxLength={50} autofocus class={inputClass} />
        </TextField>
        <Problem text={problem()} />
        <Actions
          busy={busy()}
          submit={props.submit}
          disabled={!name().trim()}
          onCancel={dialog.close}
        />
      </form>
    </Frame>
  )
}

/** What a new channel is: its kind, name, topic and, for a title channel, its title. */
export type ChannelInput = {
  kind: ChannelKind
  name: string
  topic: string
  title?: { ref: MediaRef; name: string }
}

/**
 * Make a channel (text, title, watch party or list), or rename one and set its topic. A title
 * channel is named after its title unless named by hand.
 */
export function ChannelDialog(props: {
  channel?: Channel
  onSubmit: (input: ChannelInput) => Promise<void>
  onDelete?: () => Promise<void>
  onClose: () => void
}) {
  const dialog = useClosable(() => props.onClose())
  const [kind, setKind] = createSignal<ChannelKind>(
    props.channel?.kind ?? 'text',
  )
  const [name, setName] = createSignal(props.channel?.name ?? '')
  const [topic, setTopic] = createSignal(props.channel?.topic ?? '')
  const [title, setTitle] = createSignal<ChannelInput['title']>()
  const [busy, setBusy] = createSignal(false)
  const [confirming, setConfirming] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  const slug = (text: string) =>
    text
      .toLowerCase()
      .trim()
      .split(/[\s-]+/)
      .map((w) => w.replace(/[^\p{L}\p{N}_]/gu, ''))
      .filter(Boolean)
      .join('-')
  const preview = () => slug(name()) || slug(title()?.name ?? '')
  const needsTitle = () => !props.channel && kind() === 'title' && !title()

  async function attempt(action: () => Promise<void>) {
    setBusy(true)
    setProblem(null)
    try {
      await action()
      dialog.close()
    } catch (error) {
      setProblem(message(error, 'That was not saved.'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Frame
      open={dialog.open()}
      title={
        props.channel
          ? `${kindGlyph(kind())} ${props.channel.name}`
          : 'New channel'
      }
      onClose={dialog.close}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault()
          void attempt(() =>
            props.onSubmit({
              kind: kind(),
              name: name(),
              topic: topic(),
              title: title(),
            }),
          )
        }}
      >
        <Show when={!props.channel}>
          <RadioGroup
            aria-label="Kind"
            class="mt-4 block"
            value={kind()}
            onChange={(next) => setKind(next as ChannelKind)}
          >
            <p class="text-sm font-medium" aria-hidden="true">
              Kind
            </p>
            <div class="mt-1 grid gap-1.5">
              <For each={KIND_OPTIONS}>
                {(option) => (
                  <RadioGroupItem value={option.kind} class="block">
                    <RadioGroupItemInput />
                    <RadioGroupItemLabel class="flex cursor-pointer items-start gap-3 rounded-xl bg-surface px-3 py-2 font-normal peer-focus-visible/radio-group:outline-2 peer-focus-visible/radio-group:outline-offset-2 peer-focus-visible/radio-group:outline-accent hover:bg-surface/70 data-[checked]:bg-accent/10 data-[checked]:ring-1 data-[checked]:ring-accent">
                      <span
                        aria-hidden="true"
                        class="mt-0.5 w-4 text-center text-muted"
                      >
                        {kindGlyph(option.kind)}
                      </span>
                      <span class="min-w-0">
                        <span class="block text-sm font-semibold">
                          {option.label}
                        </span>
                        <span class="block text-xs text-muted">
                          {option.hint}
                        </span>
                      </span>
                    </RadioGroupItemLabel>
                  </RadioGroupItem>
                )}
              </For>
            </div>
          </RadioGroup>
          <Show when={kind() === 'title'}>
            <div class="mt-4">
              <Show
                when={title()}
                fallback={
                  <>
                    <p class="text-sm font-medium">Title</p>
                    <div class="mt-1">
                      <TitlePicker
                        onPick={(hit) =>
                          setTitle({ ref: hitRef(hit), name: hit.title })
                        }
                      />
                    </div>
                  </>
                }
              >
                {(picked) => (
                  <p class="flex items-center justify-between gap-3 rounded-xl bg-surface px-4 py-3 text-sm">
                    <span class="min-w-0 truncate font-semibold">
                      {picked().name}
                    </span>
                    <Button
                      variant="link"
                      size="bare"
                      onClick={() => setTitle(undefined)}
                      class="shrink-0 text-accent"
                    >
                      Change
                    </Button>
                  </p>
                )}
              </Show>
            </div>
          </Show>
        </Show>
        <Show when={!needsTitle()}>
          <TextField value={name()} onChange={setName} class="mt-4 gap-0">
            <TextFieldLabel>
              Name
              <Show when={kind() === 'title' && !props.channel}>
                <span class="font-normal text-muted"> (optional)</span>
              </Show>
            </TextFieldLabel>
            <div class="relative">
              <span
                aria-hidden="true"
                class="pointer-events-none absolute top-1/2 left-4 mt-0.5 -translate-y-1/2 text-muted"
              >
                {kindGlyph(kind())}
              </span>
              <TextFieldInput
                maxLength={40}
                placeholder={
                  title() ? slug(title()?.name ?? '') : 'movie-night'
                }
                class={`${inputClass} pl-8`}
              />
            </div>
          </TextField>
          <Show when={preview() && preview() !== name().trim()}>
            <p class="mt-1 text-xs text-muted">Saved as {preview()}</p>
          </Show>
          <TextField value={topic()} onChange={setTopic} class="mt-4 gap-0">
            <TextFieldLabel>
              Topic <span class="font-normal text-muted">(optional)</span>
            </TextFieldLabel>
            <TextFieldInput
              maxLength={200}
              placeholder="What this channel is for"
              class={inputClass}
            />
          </TextField>
        </Show>
        <Problem text={problem()} />
        <Actions
          busy={busy()}
          submit={props.channel ? 'Save' : 'Create'}
          disabled={!preview() || needsTitle()}
          onCancel={dialog.close}
          extra={
            <Show when={props.onDelete}>
              {(remove) => (
                <Show
                  when={confirming()}
                  fallback={
                    <Button
                      variant="ghost"
                      size="bare"
                      onClick={() => setConfirming(true)}
                      class="text-sm text-danger hover:text-danger"
                    >
                      Delete channel
                    </Button>
                  }
                >
                  <Button
                    variant="ghost"
                    size="bare"
                    disabled={busy()}
                    onClick={() => void attempt(remove())}
                    class="text-sm font-semibold text-danger underline hover:text-danger"
                  >
                    Delete it and everything in it
                  </Button>
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
  const dialog = useClosable(() => props.onClose())
  const [friends, setFriends] = createSignal<SocialUser[] | null>(null)
  const [sent, setSent] = createSignal<Set<string>>(new Set())
  const [busy, setBusy] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  onMount(async () => {
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
      open={dialog.open()}
      title="Invite friends"
      description={`Only friends can join ${props.detail.group.name}. They see an invite next time they open Groups.`}
      onClose={dialog.close}
    >
      <Problem text={problem()} />
      <Show
        when={friends()}
        fallback={<p class="mt-6 text-sm text-muted">Loading friends…</p>}
      >
        {(list) => (
          <Show
            when={list().length > 0}
            fallback={
              <div class="mt-6 rounded-card bg-surface p-4">
                <p class="text-sm text-muted">
                  No friends yet. Friends find each other by exact handle.
                </p>
                {/* UX-074: a button to the fix, not a sentence. */}
                <Link
                  to="/app/settings/friends"
                  class="mt-3 inline-flex min-h-9 items-center rounded-full bg-ink px-4 text-sm font-semibold text-paper"
                >
                  Add friends
                </Link>
              </div>
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
                        <Button
                          size="xs"
                          disabled={busy() !== null}
                          onClick={() => void invite(friend)}
                          aria-label={`Invite ${personLabel(friend)}`}
                        >
                          Invite
                        </Button>
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
        <Button variant="secondary" size="sm" onClick={dialog.close}>
          Done
        </Button>
      </div>
    </Frame>
  )
}

/** Why something cannot happen yet, with the one way forward. */
export function NoticeDialog(props: {
  title: string
  body: string
  action: string
  onAction: () => void
  onClose: () => void
}) {
  const dialog = useClosable(() => props.onClose())
  return (
    <Frame
      open={dialog.open()}
      title={props.title}
      description={props.body}
      onClose={dialog.close}
    >
      <div class="mt-6 flex justify-end gap-2">
        <Button variant="ghost" size="sm" onClick={dialog.close}>
          Not now
        </Button>
        <Button
          size="sm"
          onClick={() => {
            dialog.close()
            props.onAction()
          }}
        >
          {props.action}
        </Button>
      </div>
    </Frame>
  )
}

/** A yes-or-no for something that cannot be undone, on the shared AlertDialog. */
export function ConfirmDialog(props: {
  title: string
  body: string
  confirm: string
  danger?: boolean
  onConfirm: () => Promise<void>
  onClose: () => void
}) {
  const dialog = useClosable(() => props.onClose())
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  return (
    <AskDialog
      open={dialog.open()}
      title={props.title}
      description={
        <>
          {props.body}
          <Show when={problem()}>
            {(text) => (
              <span role="alert" class="mt-3 block text-sm text-danger">
                {text()}
              </span>
            )}
          </Show>
        </>
      }
      confirmLabel={props.confirm}
      busy={busy()}
      onCancel={dialog.close}
      onConfirm={async () => {
        setBusy(true)
        setProblem(null)
        try {
          await props.onConfirm()
          dialog.close()
        } catch (error) {
          setProblem(message(error, 'That did not work.'))
        } finally {
          setBusy(false)
        }
      }}
    />
  )
}
