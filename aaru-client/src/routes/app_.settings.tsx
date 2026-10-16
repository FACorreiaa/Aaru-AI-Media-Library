import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { GoogleSignInButton } from '../components/GoogleSignInButton'
import { FILE_SOURCES, sourceLabel, stateLabel } from '../lib/imports/model'
import {
  deleteAccount,
  getAccount,
  listImports,
  uploadImport,
} from '../lib/imports/server'
import type { ImportJob } from '../lib/imports/server'
import {
  getSession,
  getSignInConfig,
  linkGoogle,
  signOut,
} from '../lib/session/session'

// APP-007 on the web: account, imports, and the way out.
const providerNames = {
  apple: 'Apple',
  email: 'Email',
  google: 'Google',
} as const
export const Route = createFileRoute('/app_/settings')({
  head: () => ({ meta: [{ title: 'Settings · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  loader: async () => {
    const [account, imports, signIn] = await Promise.all([
      getAccount(),
      listImports(),
      getSignInConfig(),
    ])
    return { account, imports, googleClientId: signIn.googleClientId }
  },
  component: Settings,
})

type FileSource = (typeof FILE_SOURCES)[number]['source']

function Settings() {
  const loaded = Route.useLoaderData()
  const router = useRouter()
  const navigate = useNavigate()
  const [jobs, setJobs] = createSignal<ImportJob[]>(loaded().imports)
  const [uploading, setUploading] = createSignal<FileSource | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [confirmingDelete, setConfirmingDelete] = createSignal(false)

  const [account, setAccount] = createSignal(loaded().account)
  const providers = () =>
    account()
      .providers.map((p) => providerNames[p])
      .join(', ') || '—'
  const canLinkGoogle = () =>
    loaded().googleClientId && !account().providers.includes('google')
      ? loaded().googleClientId
      : null

  async function upload(source: FileSource, file: File) {
    setProblem(null)
    if (file.size > 5 * 1024 * 1024) {
      setProblem('That file is larger than 5 MB. Check it is the right export.')
      return
    }
    setUploading(source)
    try {
      const job = await uploadImport({
        data: { source, filename: file.name, text: await file.text() },
      })
      setJobs([job, ...jobs()])
      await navigate({ to: '/app/imports/$id', params: { id: job.id } })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'That file could not be imported.',
      )
    } finally {
      setUploading(null)
    }
  }

  async function leave() {
    await signOut()
    await router.invalidate()
    await navigate({ to: '/' })
  }

  async function remove() {
    setProblem(null)
    try {
      await deleteAccount()
      await router.invalidate()
      await navigate({ to: '/' })
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'The account was not deleted.',
      )
    }
  }

  return (
    <div class="min-h-[100dvh]">
      <AppHeader class="max-w-3xl" />
      <main class="mx-auto max-w-3xl px-5 pb-20 md:px-8">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Settings
        </h1>

        <Show when={problem()}>
          {(message) => (
            <p
              role="alert"
              class="mt-4 rounded-[14px] bg-danger/10 px-4 py-3 text-sm text-danger"
            >
              {message()}
            </p>
          )}
        </Show>

        <section class="mt-8 rounded-[20px] bg-surface p-5">
          <h2 class="font-display text-xl font-medium">Account</h2>
          <dl class="mt-3 grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
            <dt class="text-muted">Name</dt>
            <dd>{account().displayName ?? 'Not set'}</dd>
            <dt class="text-muted">Signed in with</dt>
            <dd>{providers()}</dd>
          </dl>
          <Show when={canLinkGoogle()}>
            {(clientId) => (
              <div class="mt-4 max-w-xs">
                <p class="mb-2 text-sm text-muted">
                  Link Google to sign in with it too.
                </p>
                <GoogleSignInButton
                  clientId={clientId()}
                  text="signin_with"
                  onCredential={(credential) => {
                    setProblem(null)
                    linkGoogle({ data: credential })
                      .then(setAccount)
                      .catch((err: unknown) =>
                        setProblem(
                          err instanceof Error
                            ? err.message
                            : 'Google was not linked.',
                        ),
                      )
                  }}
                  onError={setProblem}
                />
              </div>
            )}
          </Show>
          <button
            type="button"
            onClick={leave}
            class="mt-4 rounded-full border border-ink/25 px-4 py-1.5 text-sm font-semibold"
          >
            Sign out
          </button>
        </section>

        <section class="mt-8">
          <h2 class="font-display text-2xl font-medium">Bring your history</h2>
          <p class="mt-2 max-w-[60ch] text-muted">
            Aaru matches every row first and shows you the plan. Nothing changes
            until you approve it, and an import undoes in one step.
          </p>
          <div class="mt-5 grid gap-3 sm:grid-cols-3">
            <For each={FILE_SOURCES}>
              {(option) => (
                <label class="flex cursor-pointer flex-col gap-1 rounded-[20px] border border-line p-4 hover:bg-surface">
                  <span class="font-medium">
                    {uploading() === option.source
                      ? 'Uploading…'
                      : `Import from ${option.label}`}
                  </span>
                  <span class="text-xs text-muted">{option.hint}</span>
                  <input
                    type="file"
                    accept=".csv,text/csv,text/plain"
                    class="sr-only"
                    disabled={uploading() !== null}
                    onChange={(e) => {
                      const file = e.currentTarget.files?.[0]
                      e.currentTarget.value = ''
                      if (file) void upload(option.source, file)
                    }}
                  />
                </label>
              )}
            </For>
          </div>
        </section>

        <Show when={jobs().length > 0}>
          <section class="mt-10">
            <h2 class="font-display text-2xl font-medium">Imports</h2>
            <ul class="mt-3 divide-y divide-line">
              <For each={jobs()}>
                {(job) => (
                  <li>
                    <Link
                      to="/app/imports/$id"
                      params={{ id: job.id }}
                      class="flex items-center justify-between gap-4 py-3 hover:text-accent"
                    >
                      <span class="min-w-0 truncate font-medium">
                        {job.filename ?? sourceLabel(job)}
                      </span>
                      <span
                        class="shrink-0 text-sm"
                        classList={{
                          'text-danger': job.state === 'failed',
                          'text-muted': job.state !== 'failed',
                        }}
                      >
                        {sourceLabel(job)} · {stateLabel(job)}
                      </span>
                    </Link>
                  </li>
                )}
              </For>
            </ul>
          </section>
        </Show>

        <section class="mt-12 rounded-[20px] border border-danger/30 p-5">
          <h2 class="font-display text-xl font-medium">Delete account</h2>
          <p class="mt-2 text-sm text-muted">
            Deletes your library, lists, imports and sessions from Aaru for
            good.
          </p>
          <Show
            when={confirmingDelete()}
            fallback={
              <button
                type="button"
                onClick={() => setConfirmingDelete(true)}
                class="mt-4 rounded-full border border-danger/50 px-4 py-1.5 text-sm font-semibold text-danger"
              >
                Delete account
              </button>
            }
          >
            <div class="mt-4 flex flex-wrap items-center gap-3">
              <span class="text-sm font-medium">This cannot be undone.</span>
              <button
                type="button"
                onClick={remove}
                class="rounded-full bg-danger px-4 py-1.5 text-sm font-semibold text-paper"
              >
                Delete account and library
              </button>
              <button
                type="button"
                onClick={() => setConfirmingDelete(false)}
                class="text-sm text-muted hover:text-ink"
              >
                Keep it
              </button>
            </div>
          </Show>
        </section>
      </main>
    </div>
  )
}
