import { Link, useNavigate } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { CatImport } from '../CatImport'
import { StremioHistoryImport } from '../StremioHistoryImport'
import { TraktImport } from '../TraktImport'
import {
  Alert,
  AlertDescription,
  Button,
  FileField,
  FileFieldHiddenInput,
  FileFieldTrigger,
  TextField,
  TextFieldDescription,
  TextFieldErrorMessage,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { FILE_SOURCES, sourceLabel, stateLabel } from '../../lib/imports/model'
import { LISTEN_FILE_SOURCES } from '../../lib/imports/listens'
import { readImportFile, readListenFile } from '../../lib/imports/file'
import { startAniListImport, uploadImport } from '../../lib/imports/server'
import {
  startListenAccountImport,
  uploadListenHistory,
} from '../../lib/imports/listens-server'
import type { ImportJob, TraktConnection } from '../../lib/imports/server'
import { SettingsPageTitle } from './SettingsNav'
import { SettingsSection } from './SettingsSection'

type FileSource = (typeof FILE_SOURCES)[number]['source']
type ListenFileSource = (typeof LISTEN_FILE_SOURCES)[number]['source']
type FileOption = {
  source: FileSource | ListenFileSource
  label: string
  hint: string
  accept: string
}
const fileSource = (source: FileSource) =>
  FILE_SOURCES.find((s) => s.source === source)!
const listenFileSource = (source: ListenFileSource) =>
  LISTEN_FILE_SOURCES.find((s) => s.source === source)!

const tile = 'flex flex-col gap-1 rounded-card border border-line p-4'

/** Settings → Import (DESIGN.md §18): every way in, in CLAUDE.md's import order, then the jobs. */
export function ImportsPage(props: {
  imports: ImportJob[]
  trakt: TraktConnection
  traktReturn: { ok: boolean; message: string } | null
}) {
  const navigate = useNavigate()
  const [trakt, setTrakt] = createSignal(props.trakt)
  const [jobs, setJobs] = createSignal<ImportJob[]>(props.imports)
  const [uploading, setUploading] = createSignal<FileOption['source'] | null>(
    null,
  )
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

  async function uploadListens(source: ListenFileSource, file: File) {
    setProblem(null)
    setUploading(source)
    try {
      const text = await readListenFile(file)
      await open(
        await uploadListenHistory({
          data: { source, filename: file.name, text },
        }),
      )
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

  function FileTile(p: { source: FileSource }) {
    const option = fileSource(p.source)
    return (
      <UploadTile
        option={option}
        onFile={(file) => void upload(option.source, file)}
      />
    )
  }

  function ListenFileTile(p: { source: ListenFileSource }) {
    const option = listenFileSource(p.source)
    return (
      <UploadTile
        option={option}
        onFile={(file) => void uploadListens(option.source, file)}
      />
    )
  }

  function UploadTile(p: { option: FileOption; onFile: (file: File) => void }) {
    const option = p.option
    return (
      <FileField
        class={`${tile} size-auto items-stretch justify-start`}
        accept={option.accept}
        maxFiles={1}
        disabled={uploading() !== null}
        onFileAccept={(files) => {
          const file = files.at(0)
          if (file) p.onFile(file)
        }}
        onFileReject={() =>
          setProblem(`That is not a file Aaru reads for ${option.label}.`)
        }
      >
        <FileFieldHiddenInput />
        <FileFieldTrigger
          variant="ghost"
          size="bare"
          class="-m-4 flex h-auto flex-col items-start gap-1 rounded-card p-4 text-left font-normal whitespace-normal text-ink hover:bg-surface hover:text-ink"
        >
          <span class="font-medium">
            {uploading() === option.source
              ? 'Uploading…'
              : `Import from ${option.label}`}
          </span>
          <span class="text-xs text-muted">{option.hint}</span>
        </FileFieldTrigger>
      </FileField>
    )
  }

  return (
    <>
      <SettingsPageTitle
        title="Import"
        description="Aaru matches every row first and shows you the plan. Nothing changes until you approve it, and an import undoes in one step."
      />

      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mb-6">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>
      <Show when={props.traktReturn}>
        {(result) =>
          result().ok ? (
            <p role="status" class="mb-6 rounded-panel bg-surface p-3 text-sm">
              {result().message}
            </p>
          ) : (
            <Alert variant="destructive" class="mb-6">
              <AlertDescription>{result().message}</AlertDescription>
            </Alert>
          )
        }
      </Show>

      <SettingsSection title="Trakt">
        <TraktImport
          connection={trakt()}
          returnTo={() => `${window.location.origin}/app/settings/import`}
          onDisconnected={() => setTrakt({ connected: false })}
        />
      </SettingsSection>

      <SettingsSection id="history-sources" title="Bring your history">
        <div class="grid gap-3 sm:grid-cols-2">
          <div id="stremio" class={`${tile} scroll-mt-6 sm:col-span-2`}>
            <span class="font-medium">Import from Stremio</span>
            <StremioHistoryImport class="mt-1" />
          </div>
          <FileTile source="imdb" />
          <FileTile source="letterboxd" />
          <FileTile source="goodreads" />
          <CatImport onImported={(job) => void open(job)} />
          <FileTile source="netflix" />
          <FileTile source="tvtime" />
          <FileTile source="mal" />
          <form class={`${tile} gap-2 sm:col-span-2`} onSubmit={importAniList}>
            <TextField
              value={anilistName()}
              onChange={setAnilistName}
              validationState={anilistProblem() ? 'invalid' : 'valid'}
              class="gap-1"
            >
              <TextFieldLabel class="text-base">
                Import from AniList
              </TextFieldLabel>
              <TextFieldDescription class="text-xs text-muted">
                Your username. Its anime and manga lists must be public.
              </TextFieldDescription>
              <div class="mt-1 flex flex-wrap gap-2">
                <TextFieldInput
                  name="username"
                  autocomplete="off"
                  autocapitalize="off"
                  spellcheck={false}
                  placeholder="username"
                  class="min-w-0 flex-1"
                />
                <Button
                  variant="outline"
                  type="submit"
                  disabled={anilistBusy() || anilistName().trim() === ''}
                >
                  {anilistBusy() ? 'Starting…' : 'Import'}
                </Button>
              </div>
              <TextFieldErrorMessage class="text-sm text-danger">
                {anilistProblem()}
              </TextFieldErrorMessage>
            </TextField>
          </form>
          <FileTile source="auto" />
        </div>
      </SettingsSection>

      <SettingsSection id="music-history" title="Music history">
        <p class="mb-3 max-w-prose text-sm text-muted">
          Past listening goes to your Music log, never your library. Each listen
          counts on the day you played it, and an import undoes in one step.
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <ListenAccountForm
            service="lastfm"
            label="Last.fm"
            description="Your username. Your recent listening must not be hidden in Last.fm's privacy settings."
            onImported={(job) => void open(job)}
          />
          <ListenAccountForm
            service="listenbrainz"
            label="ListenBrainz"
            description="Your username. Listens on ListenBrainz are public."
            onImported={(job) => void open(job)}
          />
          <ListenFileTile source="spotify" />
          <ListenFileTile source="youtube" />
        </div>
      </SettingsSection>

      <SettingsSection id="imports" title="Imports">
        <Show
          when={jobs().length > 0}
          fallback={<p class="text-sm text-muted">No imports yet.</p>}
        >
          <ul class="-my-3 divide-y divide-line">
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
        </Show>
      </SettingsSection>
    </>
  )
}

/** MUS-004: a Last.fm or ListenBrainz username, read by the server in the background. */
function ListenAccountForm(props: {
  service: 'lastfm' | 'listenbrainz'
  label: string
  description: string
  onImported: (job: ImportJob) => void
}) {
  const [name, setName] = createSignal('')
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function submit(event: SubmitEvent) {
    event.preventDefault()
    if (busy()) return
    setProblem(null)
    setBusy(true)
    try {
      const job = await startListenAccountImport({
        data: { service: props.service, username: name() },
      })
      setName('')
      props.onImported(job)
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : `That ${props.label} import could not be started.`,
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <form class={`${tile} gap-2`} onSubmit={submit}>
      <TextField
        value={name()}
        onChange={setName}
        validationState={problem() ? 'invalid' : 'valid'}
        class="gap-1"
      >
        <TextFieldLabel class="text-base">
          Import from {props.label}
        </TextFieldLabel>
        <TextFieldDescription class="text-xs text-muted">
          {props.description}
        </TextFieldDescription>
        <div class="mt-1 flex flex-wrap gap-2">
          <TextFieldInput
            name="username"
            autocomplete="off"
            autocapitalize="off"
            spellcheck={false}
            placeholder="username"
            class="min-w-0 flex-1"
          />
          <Button
            variant="outline"
            type="submit"
            disabled={busy() || name().trim() === ''}
          >
            {busy() ? 'Starting…' : 'Import'}
          </Button>
        </div>
        <TextFieldErrorMessage class="text-sm text-danger">
          {problem()}
        </TextFieldErrorMessage>
      </TextField>
    </form>
  )
}
