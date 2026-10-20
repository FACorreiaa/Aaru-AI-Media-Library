import { createFileRoute, redirect } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import { z } from 'zod'
import { Wordmark } from '../components/Brand'
import { answerOAuthRequest, getOAuthRequest } from '../lib/oauth/server'
import { getSession } from '../lib/session/session'

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
  validateSearch: z.object({ request: z.string().uuid() }),
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

      <label class="mt-6 flex flex-col gap-1 text-sm">
        <span class="font-medium">Name in your history</span>
        <input
          type="text"
          maxLength={80}
          placeholder={request().clientName}
          class="min-h-11 rounded-[10px] border border-line bg-paper px-3"
          value={name()}
          onInput={(e) => setName(e.currentTarget.value)}
        />
      </label>
      <label class="mt-4 flex items-start gap-2 text-sm">
        <input
          type="checkbox"
          class="mt-0.5"
          checked={allowWrites()}
          onChange={(e) => setAllowWrites(e.currentTarget.checked)}
        />
        <span>
          Allow changes
          <span class="block text-xs text-muted">
            One item at a time, as a tap would. Bigger changes wait for your
            approval here. Revoke it any time in Settings → Connections.
          </span>
        </span>
      </label>

      <div class="mt-6 flex flex-wrap gap-2">
        <button
          type="button"
          class="min-h-11 rounded-full bg-accent px-5 text-sm font-semibold text-on-accent disabled:opacity-50"
          disabled={busy()}
          onClick={() => void answer(true)}
        >
          Allow
        </button>
        <button
          type="button"
          class="min-h-11 rounded-full border border-ink/25 px-5 text-sm font-semibold disabled:opacity-50"
          disabled={busy()}
          onClick={() => void answer(false)}
        >
          Not now
        </button>
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
