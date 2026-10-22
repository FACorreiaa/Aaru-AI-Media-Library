import { Show, createSignal } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldDescription,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { handleProblem, normalizeHandle } from '../../lib/social/model'
import { saveProfile } from '../../lib/social/server'
import type { SocialUser } from '../../lib/social/server'
import { SettingsSection } from './SettingsSection'

/** Account → Name and handle: one editor for both (UX-030). Friends find you by the handle. */
export function ProfileEditor(props: {
  handle?: string
  displayName?: string
  onSaved: (user: SocialUser) => void
}) {
  const [handle, setHandle] = createSignal(props.handle)
  const [name, setName] = createSignal(props.displayName)
  const [editing, setEditing] = createSignal(!props.handle)
  const [draftHandle, setDraftHandle] = createSignal(props.handle ?? '')
  const [draftName, setDraftName] = createSignal(props.displayName ?? '')
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function save(event: SubmitEvent) {
    event.preventDefault()
    const invalid = handleProblem(draftHandle())
    if (invalid) return setProblem(invalid)
    setBusy(true)
    setProblem(null)
    try {
      const user = await saveProfile({
        data: {
          handle: normalizeHandle(draftHandle()),
          displayName: draftName(),
        },
      })
      setHandle(user.handle)
      setName(user.displayName)
      setEditing(false)
      props.onSaved(user)
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Your handle was not saved.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <SettingsSection
      id="handle"
      title="Name and handle"
      description="Friends find you by your exact handle. Your name is what they see."
    >
      <Show
        when={!editing() && handle()}
        fallback={
          <form class="flex flex-col gap-4" onSubmit={save}>
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
            <TextField
              class="max-w-xs gap-1.5"
              value={draftName()}
              onChange={setDraftName}
            >
              <TextFieldLabel>
                Name <span class="font-normal text-muted">(optional)</span>
              </TextFieldLabel>
              <TextFieldInput autocomplete="name" maxLength={50} />
            </TextField>
            <div class="flex gap-2">
              <Button type="submit" disabled={busy()}>
                {handle() ? 'Save' : 'Choose handle'}
              </Button>
              <Show when={handle()}>
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
            <dd class="font-medium">{name() ?? 'Not set'}</dd>
            <dt class="text-muted">Handle</dt>
            <dd class="font-medium">@{handle()}</dd>
          </dl>
          <Button
            variant="outline"
            size="sm"
            class="sm:ml-auto"
            onClick={() => {
              setDraftHandle(handle() ?? '')
              setDraftName(name() ?? '')
              setEditing(true)
            }}
          >
            Edit
          </Button>
        </div>
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
