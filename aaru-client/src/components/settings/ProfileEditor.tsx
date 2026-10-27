import { Link } from '@tanstack/solid-router'
import { Show, Suspense, createSignal, lazy } from 'solid-js'
import {
  Button,
  Switch,
  SwitchControl,
  SwitchDescription,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
  TextField,
  TextFieldDescription,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { handleProblem, normalizeHandle } from '../../lib/social/model'
import {
  removeAvatar,
  saveProfile,
  saveSocialSettings,
  uploadAvatar,
} from '../../lib/social/server'
import type { Me, SocialSettings } from '../../lib/social/server'
import { Medallion } from '../Medallion'
import { SettingsSection } from './SettingsSection'

const PhotoPicker = lazy(() => import('./PhotoPicker'))

/** Account → Profile (SOC-001b): photo, first and last name, handle and email in one editor
 * (UX-030). Friends find you by the handle and see the two names joined. */
export function ProfileEditor(props: {
  account: Me
  /** Null when the sharing switches could not be loaded: the email switch stays hidden. */
  sharing: SocialSettings | null
  /** Sports is on for this server: link to the follows it keeps. */
  sports: boolean
  onSaved: (account: Me) => void
}) {
  const [editing, setEditing] = createSignal(!props.account.handle)
  const [draftHandle, setDraftHandle] = createSignal(props.account.handle ?? '')
  const [draftFirst, setDraftFirst] = createSignal(
    props.account.firstName ?? '',
  )
  const [draftLast, setDraftLast] = createSignal(props.account.lastName ?? '')
  const [shareEmail, setShareEmail] = createSignal(
    props.sharing?.shareEmailWithFriends ?? false,
  )
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  const photoLabel = () =>
    props.account.avatarUrl ? 'Change photo' : 'Add photo'

  function startEditing() {
    setDraftHandle(props.account.handle ?? '')
    setDraftFirst(props.account.firstName ?? '')
    setDraftLast(props.account.lastName ?? '')
    setProblem(null)
    setEditing(true)
  }

  async function run(work: () => Promise<Me>, fallback: string) {
    setBusy(true)
    setProblem(null)
    try {
      props.onSaved(await work())
      return true
    } catch (error) {
      setProblem(error instanceof Error ? error.message : fallback)
      return false
    } finally {
      setBusy(false)
    }
  }

  async function save(event: SubmitEvent) {
    event.preventDefault()
    // A name needs no handle; once you have one, it can change but not go.
    const handle = draftHandle().trim()
    const invalid =
      handle || props.account.handle ? handleProblem(handle) : null
    if (invalid) return setProblem(invalid)
    const saved = await run(
      () =>
        saveProfile({
          data: {
            handle: handle ? normalizeHandle(handle) : undefined,
            firstName: draftFirst(),
            lastName: draftLast(),
          },
        }),
      'Your profile was not saved.',
    )
    if (saved && props.account.handle) setEditing(false)
  }

  async function choosePhoto(file: File) {
    await run(async () => {
      const { squareAvatar } = await import('../../lib/profile/avatar-image')
      return uploadAvatar({ data: { image: await squareAvatar(file) } })
    }, 'Your photo was not saved.')
  }

  async function changeSharing(next: boolean) {
    setShareEmail(next)
    setProblem(null)
    try {
      await saveSocialSettings({ data: { shareEmailWithFriends: next } })
    } catch (error) {
      setShareEmail(!next)
      setProblem(error instanceof Error ? error.message : 'That was not saved.')
    }
  }

  return (
    <SettingsSection
      id="handle"
      title="Profile"
      description="Friends find you by your exact handle. They see your name and photo."
    >
      <div class="mb-6 flex flex-wrap items-center gap-4">
        <Medallion
          person={{
            displayName: props.account.displayName ?? null,
            handle: props.account.handle ?? null,
            avatarUrl: props.account.avatarUrl,
          }}
          class="size-16 text-2xl"
        />
        <div class="flex flex-wrap gap-2">
          <Suspense
            fallback={
              <Button variant="outline" size="sm" disabled>
                {photoLabel()}
              </Button>
            }
          >
            <PhotoPicker
              label={photoLabel()}
              disabled={busy()}
              onPick={(file) => void choosePhoto(file)}
              onReject={() =>
                setProblem('Choose a photo: a JPEG, PNG, WebP or HEIC.')
              }
            />
          </Suspense>
          <Show when={props.account.avatarUrl}>
            <Button
              variant="ghost"
              size="sm"
              disabled={busy()}
              onClick={() =>
                void run(() => removeAvatar(), 'Your photo was not removed.')
              }
            >
              Remove
            </Button>
          </Show>
        </div>
      </div>

      <Show
        when={!editing() && props.account.handle}
        fallback={
          <form class="flex flex-col gap-4" onSubmit={save}>
            <div class="flex flex-wrap gap-4">
              <TextField
                class="w-full max-w-xs gap-1.5"
                value={draftFirst()}
                onChange={setDraftFirst}
              >
                <TextFieldLabel>
                  First name{' '}
                  <span class="font-normal text-muted">(optional)</span>
                </TextFieldLabel>
                <TextFieldInput autocomplete="given-name" maxLength={50} />
              </TextField>
              <TextField
                class="w-full max-w-xs gap-1.5"
                value={draftLast()}
                onChange={setDraftLast}
              >
                <TextFieldLabel>
                  Last name{' '}
                  <span class="font-normal text-muted">(optional)</span>
                </TextFieldLabel>
                <TextFieldInput autocomplete="family-name" maxLength={50} />
              </TextField>
            </div>
            <TextField
              class="max-w-xs gap-1.5"
              value={draftHandle()}
              onChange={setDraftHandle}
              validationState={problem() ? 'invalid' : 'valid'}
            >
              <TextFieldLabel>Handle</TextFieldLabel>
              <div class="relative">
                <span
                  aria-hidden="true"
                  class="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted"
                >
                  @
                </span>
                <TextFieldInput
                  class="w-full pl-7"
                  autocomplete="username"
                  autocapitalize="none"
                  spellcheck={false}
                  maxLength={21}
                />
              </div>
              <TextFieldDescription class="text-xs text-muted">
                3–20 letters, numbers or _.
              </TextFieldDescription>
            </TextField>
            <div class="flex gap-2">
              <Button type="submit" disabled={busy()}>
                Save
              </Button>
              <Show when={props.account.handle}>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => {
                    setProblem(null)
                    setEditing(false)
                  }}
                >
                  Cancel
                </Button>
              </Show>
            </div>
          </form>
        }
      >
        <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
          <dl class="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-sm">
            <dt class="text-muted">Name</dt>
            <dd class="font-medium">
              {props.account.displayName ?? 'Not set'}
            </dd>
            <dt class="text-muted">Handle</dt>
            <dd class="font-medium">@{props.account.handle}</dd>
          </dl>
          <Button
            variant="outline"
            size="sm"
            class="sm:ml-auto"
            onClick={startEditing}
          >
            Edit
          </Button>
        </div>
      </Show>

      <Show when={props.account.email}>
        {(email) => (
          <div class="mt-6 flex flex-col gap-3 border-t border-line pt-4">
            <dl class="grid grid-cols-[auto_1fr] gap-x-6 text-sm">
              <dt class="text-muted">Email</dt>
              <dd class="font-medium break-all">{email()}</dd>
            </dl>
            <Show
              when={props.account.emailShareable}
              fallback={
                <p class="max-w-prose text-xs text-muted">
                  This is an Apple “Hide My Email” address. It takes mail only
                  from Aaru, so it can’t be shared with friends.
                </p>
              }
            >
              <Show when={props.sharing}>
                <Switch
                  class="flex items-start gap-3 text-sm"
                  checked={shareEmail()}
                  onChange={(next) => void changeSharing(next)}
                >
                  <SwitchInput />
                  <SwitchControl>
                    <SwitchThumb />
                  </SwitchControl>
                  <span>
                    <SwitchLabel class="cursor-pointer">
                      Friends can see my email
                    </SwitchLabel>
                    <SwitchDescription class="block text-xs">
                      On your profile, for friends only. People in your groups
                      never see it.
                    </SwitchDescription>
                  </span>
                </Switch>
              </Show>
            </Show>
          </div>
        )}
      </Show>

      <Show when={props.sports}>
        <p class="mt-6 border-t border-line pt-4 text-sm">
          <Link
            to="/app/sports"
            class="font-medium underline-offset-4 hover:underline"
          >
            Sports you follow
          </Link>
          <span class="text-muted">
            {' '}
            — leagues, teams and players, in Sports. They stay off your profile.
          </span>
        </p>
      </Show>

      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </SettingsSection>
  )
}
