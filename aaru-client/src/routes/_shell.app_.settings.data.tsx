import { Link, createFileRoute } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { SettingsSection } from '../components/settings/SettingsSection'
import {
  Alert,
  AlertDescription,
  Button,
  buttonVariants,
} from '~/components/ui'
import { actionBy, canUndo, whenLabel } from '../lib/history/model'
import type { Action } from '../lib/history/model'
import { listActions, undoAction } from '../lib/history/server'
import { periodLabel, recapShortcuts } from '../lib/recap/model'

export const Route = createFileRoute('/_shell/app_/settings/data')({
  head: () => ({ meta: [{ title: 'Your data · Settings · Aaru' }] }),
  loader: async () => {
    try {
      return { actions: await listActions(), problem: null }
    } catch (error) {
      return {
        actions: [] as Action[],
        problem:
          error instanceof Error
            ? error.message
            : 'Your history could not be loaded.',
      }
    }
  },
  component: YourData,
})

/** Settings → Your data (DESIGN.md §18): recaps, History with Undo, Export. */
function YourData() {
  const data = Route.useLoaderData()
  const [actions, setActions] = createSignal<Action[]>(data().actions)
  const [busy, setBusy] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(data().problem)

  async function undo(action: Action) {
    if (busy()) return
    setProblem(null)
    setBusy(action.id)
    try {
      const inverse = await undoAction({ data: { id: action.id } })
      setActions([
        inverse,
        ...actions().map((a) =>
          a.id === action.id ? { ...a, undoneAt: inverse.createdAt } : a,
        ),
      ])
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That could not be undone.',
      )
      // The journal may have moved on (undone elsewhere): show what it holds now.
      setActions(await listActions().catch(() => actions()))
    } finally {
      setBusy(null)
    }
  }

  return (
    <>
      <SettingsPageTitle title="Your data" />

      <SettingsSection
        id="recaps"
        title="Recaps"
        description="What you watched, read and listened to, as a story you can share."
      >
        <div class="flex flex-wrap gap-2">
          <For each={recapShortcuts(new Date())}>
            {(period) => (
              <Link
                to="/app/recap"
                search={period}
                class={buttonVariants({ variant: 'outline', size: 'sm' })}
              >
                {periodLabel(period)}
              </Link>
            )}
          </For>
        </div>
      </SettingsSection>

      <SettingsSection
        id="history"
        title="History"
        description="Every change to your library, newest first: yours, an import's, or a connection's. Undo puts it back."
      >
        <Show when={problem()}>
          {(message) => (
            <Alert variant="destructive" class="mb-3">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>
        <Show
          when={actions().length > 0}
          fallback={<p class="text-sm text-muted">Nothing yet.</p>}
        >
          <ul class="-my-3 divide-y divide-line">
            <For each={actions()}>
              {(action) => (
                <li class="flex items-center justify-between gap-4 py-3">
                  <div class="min-w-0">
                    <p
                      class="text-sm"
                      classList={{
                        'text-muted line-through':
                          action.undoneAt !== undefined,
                      }}
                    >
                      {action.summary}
                    </p>
                    <p class="mt-0.5 text-xs text-muted">
                      {actionBy(action)} · {whenLabel(action.createdAt)}
                      <Show when={action.undoneAt}> · Undone</Show>
                    </p>
                  </div>
                  <Show when={canUndo(action)}>
                    <Button
                      variant="outline"
                      size="xs"
                      class="shrink-0"
                      disabled={busy() !== null}
                      aria-label={`Undo: ${action.summary}`}
                      onClick={() => void undo(action)}
                    >
                      {busy() === action.id ? 'Undoing…' : 'Undo'}
                    </Button>
                  </Show>
                </li>
              )}
            </For>
          </ul>
        </Show>
      </SettingsSection>

      <SettingsSection
        id="export"
        title="Export"
        description="Everything Aaru holds for you. The spreadsheet opens anywhere and imports back into Aaru."
      >
        {/* Plain links, not router links: the Worker answers with a download. */}
        <div class="flex flex-wrap gap-3">
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
      </SettingsSection>
    </>
  )
}
