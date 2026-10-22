import { createFileRoute, redirect } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import { optionalString } from '../lib/search-params'
import { Wordmark } from '../components/Brand'
import {
  Button,
  Checkbox,
  CheckboxControl,
  CheckboxDescription,
  CheckboxInput,
  CheckboxLabel,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { answerOAuthRequest, getOAuthRequest } from '../lib/oauth/server'
import { getSession } from '../lib/session/session'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// OUT-004: an app (Claude's custom connector, or any OAuth MCP client) asks to reach this
// library. The user names it, chooses whether it may change things, and answers; the browser
// then returns to the app. Apps name themselves, so the return host is shown too.
export const Route = createFileRoute('/oauth/consent')({
  head: () => ({
    meta: [
      { title: 'Connect an app · Aaru' },
      { name: 'robots', content: 'noindex' },
    ],
  }),
  validateSearch: (search): { request: string } => {
    const request = optionalString(search.request)
    if (!request || !UUID.test(request)) throw new Error('Invalid request id')
    return { request }
  },
  beforeLoad: async ({ search }) => {
    const session = await getSession()
    if (!session.signedIn)
      throw redirect({
        to: '/sign-in',
        search: { next: `/oauth/consent?request=${search.request}` },
      })
  },
  loaderDeps: ({ search }) => ({ request: search.request }),
  loader: ({ deps }) => getOAuthRequest({ data: { id: deps.request } }),
  errorComponent: () => (
    <Page>
      <h1 class="font-display text-3xl font-medium">Request expired</h1>
      <p class="mt-3 text-muted">
        This connection request is no longer open. Start again from the app you
        were connecting.
      </p>
    </Page>
  ),
  component: Consent,
})

function Page(props: { children: JSX.Element }) {
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col justify-center px-4 py-10">
      <Wordmark />
      <div class="mt-8">{props.children}</div>
    </main>
  )
}

function Consent() {
  const request = Route.useLoaderData()
  const [name, setName] = createSignal('')
  const [allowWrites, setAllowWrites] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function answer(approve: boolean) {
    setBusy(true)
    setProblem(null)
    try {
      const next = await answerOAuthRequest({
        data: {
          id: request().id,
          approve,
          name: name() || undefined,
          allowLibraryWrites: allowWrites(),
        },
      })
      window.location.assign(next)
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Your answer was not sent.',
      )
      setBusy(false)
    }
  }

  return (
    <Page>
      <h1 class="font-display text-3xl font-medium">
        Connect {request().clientName} to Aaru?
      </h1>
      <p class="mt-3 text-muted">
        It will read your library: what you are watching, what airs soon, what
        you have finished. You go back to{' '}
        <strong class="text-ink">{request().redirectHost}</strong> after you
        answer.
      </p>

      <TextField value={name()} onChange={setName} class="mt-6 gap-1">
        <TextFieldLabel>Name in your history</TextFieldLabel>
        <TextFieldInput
          type="text"
          maxLength={80}
          placeholder={request().clientName}
        />
      </TextField>
      <Checkbox
        class="mt-4 flex items-start gap-2.5"
        checked={allowWrites()}
        onChange={setAllowWrites}
      >
        <CheckboxInput />
        <CheckboxControl class="mt-0.5" />
        <span class="flex flex-col gap-1">
          <CheckboxLabel class="cursor-pointer leading-snug font-normal">
            Allow changes
          </CheckboxLabel>
          <CheckboxDescription class="text-xs text-muted">
            One item at a time, as a tap would. Bigger changes wait for your
            approval here. Disconnect it any time in Settings → Connections.
          </CheckboxDescription>
        </span>
      </Checkbox>

      <div class="mt-6 flex flex-wrap gap-2">
        <Button
          variant="default"
          disabled={busy()}
          onClick={() => void answer(true)}
        >
          Allow
        </Button>
        <Button
          variant="outline"
          disabled={busy()}
          onClick={() => void answer(false)}
        >
          Not now
        </Button>
      </div>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-4 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </Page>
  )
}
