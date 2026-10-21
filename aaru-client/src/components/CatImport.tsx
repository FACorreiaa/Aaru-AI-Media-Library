import { Show, createSignal } from 'solid-js'
import { readImportFile } from '../lib/imports/file'
import { startCatFeedImport, uploadCatImport } from '../lib/imports/server'
import type { ImportJob } from '../lib/imports/server'
import { Button } from './ui/button'

const field =
  'min-h-11 min-w-0 flex-1 rounded-panel border-0 bg-surface px-4 text-base text-ink placeholder:text-muted/70 focus:ring-2 focus:ring-accent focus:outline-none'

// IMP-009/010: Pogdesign CAT has no list export, so its shows come in three ways: the iCal link,
// the iCal file, or a pasted list. Only shows come across; CAT's watched episodes do not.
export function CatImport(props: { onImported: (job: ImportJob) => void }) {
  const [link, setLink] = createSignal('')
  const [list, setList] = createSignal('')
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function run(start: () => Promise<ImportJob>, fallback: string) {
    if (busy()) return
    setProblem(null)
    setBusy(true)
    try {
      props.onImported(await start())
    } catch (error) {
      setProblem(error instanceof Error ? error.message : fallback)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div class="flex flex-col gap-3 rounded-card border border-line p-4 sm:col-span-2">
      <div>
        <h3 class="font-medium">Import from Pogdesign CAT</h3>
        <p class="text-xs text-muted">
          Your shows arrive as Plan to watch. CAT's watched episodes don't come
          across.
        </p>
      </div>
      <form
        class="flex flex-col gap-1"
        onSubmit={(event) => {
          event.preventDefault()
          void run(
            () => startCatFeedImport({ data: { url: link() } }),
            'That CAT link could not be imported.',
          )
        }}
      >
        <label for="cat-link" class="text-sm">
          Your CAT iCal link
        </label>
        <div class="flex flex-wrap gap-2">
          <input
            id="cat-link"
            type="url"
            autocomplete="off"
            spellcheck={false}
            placeholder="https://www.pogdesign.co.uk/cat/download_ics/…"
            class={field}
            value={link()}
            onInput={(e) => setLink(e.currentTarget.value)}
          />
          <Button type="submit" disabled={busy() || link().trim() === ''}>
            Import
          </Button>
        </div>
        <span class="text-xs text-muted">
          In CAT, signed in: copy the “Download iCal File” link. Aaru reads it
          once and doesn't keep it.
        </span>
      </form>
      <form
        class="flex flex-col gap-1"
        onSubmit={(event) => {
          event.preventDefault()
          void run(
            () => uploadCatImport({ data: { text: list() } }),
            'Those shows could not be imported.',
          )
        }}
      >
        <label for="cat-list" class="text-sm">
          Or paste your shows, one per line
        </label>
        <textarea
          id="cat-list"
          rows={4}
          spellcheck={false}
          placeholder={'Severance\nThe Bear\nBrothers (2026)'}
          class={`${field} py-3`}
          value={list()}
          onInput={(e) => setList(e.currentTarget.value)}
        />
        <div class="flex flex-wrap items-center gap-2">
          <Button type="submit" disabled={busy() || list().trim() === ''}>
            Import list
          </Button>
          <label class="cursor-pointer text-sm text-accent hover:underline">
            or upload the .ics file
            <input
              type="file"
              accept=".ics,.txt,text/calendar,text/plain"
              class="sr-only"
              disabled={busy()}
              onChange={(e) => {
                const file = e.currentTarget.files?.[0]
                e.currentTarget.value = ''
                if (file)
                  void run(
                    async () =>
                      uploadCatImport({
                        data: { text: await readImportFile(file) },
                      }),
                    'That file could not be imported.',
                  )
              }}
            />
          </label>
        </div>
      </form>
      <Show when={busy()}>
        <p class="text-sm text-muted" aria-live="polite">
          Starting…
        </p>
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </div>
  )
}
