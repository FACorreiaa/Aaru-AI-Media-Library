import { Link, useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { CatImport } from '../CatImport'
import { StremioHistoryImport } from '../StremioHistoryImport'
import { TraktImport } from '../TraktImport'
import {
  Alert,
  AlertDescription,
  Button,
  buttonVariants,
  Card,
} from '~/components/ui'
import { FILE_SOURCES, sourceLabel, stateLabel } from '../../lib/imports/model'
import { readImportFile } from '../../lib/imports/file'
import { startAniListImport, uploadImport } from '../../lib/imports/server'
import type { ImportJob, TraktConnection } from '../../lib/imports/server'
import { SettingsPageTitle } from './SettingsNav'

type FileSource = (typeof FILE_SOURCES)[number]['source']

/** Settings → Imports & export: every way in, the jobs so far, and the way out. */
export function ImportsPage(props: {
  imports: ImportJob[]
  trakt: TraktConnection
  traktReturn: { ok: boolean; message: string } | null
}) {
  const navigate = useNavigate()
  const [trakt, setTrakt] = createSignal(props.trakt)
  const [jobs, setJobs] = createSignal<ImportJob[]>(props.imports)
  const [uploading, setUploading] = createSignal<FileSource | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [anilistName, setAnilistName] = createSignal('')
  const [anilistBusy, setAnilistBusy] = createSignal(false)
  const [anilistProblem, setAnilistProblem] = createSignal<string | null>(null)

  const open = (job: ImportJob) => {
    setJobs([job, ...jobs()])
    return navigate({ to: '/app/imports/$id', params: { id: job.id } })
  }

  async function upload(source: FileSource, file: File) {
    setProblem(null)
    setUploading(source)
    try {
      // MyAnimeList's export is gzipped; it is inflated here, the server takes XML.
      const text = await readImportFile(file)
      const filename = file.name.replace(/\.gz$/i, '')
      await open(await uploadImport({ data: { source, filename, text } }))
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
      setAnilistName('')
      await open(job)
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

  return (
    <>
      <SettingsPageTitle title="Imports & export" />

      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mt-4">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>
      <Show when={props.traktReturn}>
        {(result) =>
          result().ok ? (
            <p role="status" class="mt-4 rounded-panel bg-surface p-3 text-sm">
              {result().message}
            </p>
          ) : (
            <Alert variant="destructive" class="mt-4">
              <AlertDescription>{result().message}</AlertDescription>
            </Alert>
          )
        }
      </Show>

      <section class="mt-6">
        <h3 class="font-display text-xl font-medium">Bring your history</h3>
        <p class="mt-2 max-w-[60ch] text-muted">
          Aaru matches every row first and shows you the plan. Nothing changes
          until you approve it, and an import undoes in one step.
        </p>
        <div class="mt-5 grid gap-3 sm:grid-cols-2">
          <TraktImport
            connection={trakt()}
            returnTo={() => `${window.location.origin}/app/settings/import`}
            onDisconnected={() => setTrakt({ connected: false })}
          />
          <For each={FILE_SOURCES}>
            {(option) => (
              <label class="flex cursor-pointer flex-col gap-1 rounded-card border border-line p-4 hover:bg-surface">
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
            class="flex flex-col gap-2 rounded-card border border-line p-4 sm:col-span-2"
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
                class="min-h-11 min-w-0 flex-1 rounded-panel border-0 bg-surface px-4 text-base text-ink placeholder:text-muted/70 focus:ring-2 focus:ring-accent focus:outline-none"
                value={anilistName()}
                onInput={(e) => setAnilistName(e.currentTarget.value)}
                aria-describedby={
                  anilistProblem() ? 'anilist-problem' : undefined
                }
              />
              <Button
                variant="outline"
                type="submit"
                disabled={anilistBusy() || anilistName().trim() === ''}
              >
                {anilistBusy() ? 'Starting…' : 'Import'}
              </Button>
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
          <CatImport onImported={(job) => void open(job)} />
          <div class="flex flex-col gap-1 rounded-card border border-line p-4 sm:col-span-2">
            <span class="font-medium">Import from Stremio</span>
            <StremioHistoryImport class="mt-1" />
          </div>
        </div>
      </section>

      <Show when={jobs().length > 0}>
        <section id="imports" class="mt-10 scroll-mt-6">
          <h3 class="font-display text-xl font-medium">Imports</h3>
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

      <Card class="mt-10 block p-5">
        <h3 class="font-display text-xl font-medium">Export your data</h3>
        <p class="mt-2 text-sm text-muted">
          Everything Aaru holds for you. The spreadsheet opens anywhere and
          imports back into Aaru.
        </p>
        {/* Plain links, not router links: the Worker answers with a download. */}
        <div class="mt-4 flex flex-wrap gap-3">
          <a
            href="/app/export?format=json"
            download=""
            class={buttonVariants({ variant: 'outline', size: 'sm' })}
          >
            Everything (JSON)
          </a>
          <a
            href="/app/export?format=csv"
            download=""
            class={buttonVariants({ variant: 'outline', size: 'sm' })}
          >
            Library spreadsheet (CSV)
          </a>
        </div>
      </Card>
    </>
  )
}
