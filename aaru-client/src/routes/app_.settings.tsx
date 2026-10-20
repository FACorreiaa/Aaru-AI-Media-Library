import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { TMDB_NOTICE } from '../lib/credits'
import { GoogleSignInButton } from '../components/GoogleSignInButton'
import { StremioSection } from '../components/StremioSection'
import { ConnectionsSection } from '../components/ConnectionsSection'
import { NotificationsSection } from '../components/NotificationsSection'
import { FILE_SOURCES, sourceLabel, stateLabel } from '../lib/imports/model'
import { periodLabel, recapShortcuts } from '../lib/recap/model'
import { readImportFile } from '../lib/imports/file'
import {
  deleteAccount,
  getAccount,
  listImports,
  startAniListImport,
  uploadImport,
} from '../lib/imports/server'
import type { ImportJob } from '../lib/imports/server'
import {
  getSession,
  getSignInConfig,
  linkGoogle,
  signOut,
} from '../lib/session/session'
import { listStremio } from '../lib/stremio/server'
import { listConnections } from '../lib/agents/server'
import { getPushSetup } from '../lib/push/server'

// APP-007 on the web: account, imports, connected apps, and the way out.
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
    const [account, imports, signIn, stremio, connections, push] =
      await Promise.all([
        getAccount(),
        listImports(),
        getSignInConfig(),
        listStremio(),
        listConnections(),
        getPushSetup(),
      ])
    return {
      account,
      imports,
      stremio,
      connections,
      push,
      googleClientId: signIn.googleClientId,
    }
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
  const [anilistName, setAnilistName] = createSignal('')
  const [anilistBusy, setAnilistBusy] = createSignal(false)
  const [anilistProblem, setAnilistProblem] = createSignal<string | null>(null)

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
    setUploading(source)
    try {
      // MyAnimeList's export is gzipped; it is inflated here, the server takes XML.
      const text = await readImportFile(file)
      const filename = file.name.replace(/\.gz$/i, '')
      const job = await uploadImport({ data: { source, filename, text } })
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

  async function importAniList(event: SubmitEvent) {
    event.preventDefault()
    if (anilistBusy()) return
    setAnilistProblem(null)
    setAnilistBusy(true)
    try {
      const job = await startAniListImport({
        data: { username: anilistName() },
      })
      setJobs([job, ...jobs()])
      setAnilistName('')
      await navigate({ to: '/app/imports/$id', params: { id: job.id } })
    } catch (error) {
      setAnilistProblem(
        error instanceof Error
          ? error.message
          : 'That AniList import could not be started.',
      )
    } finally {
      setAnilistBusy(false)
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
          <div class="mt-5 grid gap-3 sm:grid-cols-2">
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
                    accept={option.accept}
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
            <form
              class="flex flex-col gap-2 rounded-[20px] border border-line p-4 sm:col-span-2"
              onSubmit={importAniList}
            >
              <label for="anilist-username" class="font-medium">
                Import from AniList
              </label>
              <span class="text-xs text-muted">
                Your username. The anime list must be public.
              </span>
              <div class="flex flex-wrap gap-2">
                <input
                  id="anilist-username"
                  name="username"
                  autocomplete="off"
                  autocapitalize="off"
                  spellcheck={false}
                  placeholder="username"
                  class="min-h-11 min-w-0 flex-1 rounded-[14px] border-0 bg-surface px-4 text-base text-ink placeholder:text-muted/70 focus:ring-2 focus:ring-accent focus:outline-none"
                  value={anilistName()}
                  onInput={(e) => setAnilistName(e.currentTarget.value)}
                  aria-describedby={
                    anilistProblem() ? 'anilist-problem' : undefined
                  }
                />
                <button
                  type="submit"
                  class="min-h-11 rounded-full border border-ink/25 px-5 text-sm font-semibold disabled:opacity-50"
                  disabled={anilistBusy() || anilistName().trim() === ''}
                >
                  {anilistBusy() ? 'Starting…' : 'Import'}
                </button>
              </div>
              <Show when={anilistProblem()}>
                {(message) => (
                  <p
                    id="anilist-problem"
                    role="alert"
                    class="text-sm text-danger"
                  >
                    {message()}
                  </p>
                )}
              </Show>
            </form>
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

        <NotificationsSection setup={loaded().push} />

        <StremioSection links={loaded().stremio} />
        <ConnectionsSection connections={loaded().connections} />

        <section class="mt-10">
          <h2 class="font-display text-2xl font-medium">Recaps</h2>
          <p class="mt-1 text-sm text-muted">
            What you watched and read, as a story you can share.
          </p>
          <div class="mt-3 flex flex-wrap gap-2">
            <Link
              to="/app/insights"
              class="rounded-full border border-line px-4 py-2 text-sm font-medium text-accent hover:bg-surface"
            >
              Insights
            </Link>
            <For each={recapShortcuts(new Date())}>
              {(period) => (
                <Link
                  to="/app/recap"
                  search={period}
                  class="rounded-full bg-surface px-4 py-2 text-sm font-medium hover:text-accent"
                >
                  {periodLabel(period)}
                </Link>
              )}
            </For>
          </div>
        </section>

        <section class="mt-10 rounded-[20px] bg-surface p-5">
          <h2 class="font-display text-xl font-medium">About Aaru</h2>
          <p class="mt-2 text-sm text-muted">{TMDB_NOTICE}</p>
          <div class="mt-4 flex gap-4 text-sm font-semibold">
            <Link to="/about" class="text-accent hover:underline">
              About and credits
            </Link>
            <Link to="/privacy" class="text-accent hover:underline">
              Privacy policy
            </Link>
          </div>
        </section>

        <section class="mt-10 rounded-[20px] bg-surface p-5">
          <h2 class="font-display text-xl font-medium">Export your data</h2>
          <p class="mt-2 text-sm text-muted">
            Everything Aaru holds for you. The spreadsheet opens anywhere and
            imports back into Aaru.
          </p>
          {/* Plain links, not router links: the Worker answers with a download. */}
          <div class="mt-4 flex flex-wrap gap-3">
            <a
              href="/app/export?format=json"
              download=""
              class="rounded-full border border-ink/25 px-4 py-1.5 text-sm font-semibold"
            >
              Everything (JSON)
            </a>
            <a
              href="/app/export?format=csv"
              download=""
              class="rounded-full border border-ink/25 px-4 py-1.5 text-sm font-semibold"
            >
              Library spreadsheet (CSV)
            </a>
          </div>
        </section>

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
              <span class="text-sm font-medium">
                This cannot be undone. Export your data first if you want to
                keep it.
              </span>
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
