import {
  Link,
  createFileRoute,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { Alert, AlertDescription, Button, Card } from '~/components/ui'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { TMDB_NOTICE } from '../lib/credits'
import { deleteAccount } from '../lib/imports/server'

export const Route = createFileRoute('/_shell/app_/settings/about')({
  head: () => ({ meta: [{ title: 'About · Settings · Aaru' }] }),
  component: About,
})

function About() {
  const router = useRouter()
  const navigate = useNavigate()
  const [problem, setProblem] = createSignal<string | null>(null)
  const [confirmingDelete, setConfirmingDelete] = createSignal(false)
  const [deleting, setDeleting] = createSignal(false)

  async function remove() {
    setProblem(null)
    setDeleting(true)
    try {
      await deleteAccount()
      await router.invalidate()
      await navigate({ to: '/' })
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'The account was not deleted.',
      )
    } finally {
      setDeleting(false)
      setConfirmingDelete(false)
    }
  }

  return (
    <>
      <SettingsPageTitle title="About" />
      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mt-4">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>

      <Card class="mt-6 block p-5">
        <h3 class="font-display text-xl font-medium">About Aaru</h3>
        <p class="mt-2 text-sm text-muted">{TMDB_NOTICE}</p>
        <div class="mt-4 flex gap-4 text-sm font-semibold">
          <Link to="/about" class="text-accent hover:underline">
            About and credits
          </Link>
          <Link to="/privacy" class="text-accent hover:underline">
            Privacy policy
          </Link>
        </div>
      </Card>

      <section class="mt-12 rounded-card border border-danger/30 p-5">
        <h3 class="font-display text-xl font-medium">Delete account</h3>
        <p class="mt-2 text-sm text-muted">
          Deletes your library, lists, imports and sessions from Aaru for good.
          Export your data first, in Imports &amp; export, if you want to keep
          it.
        </p>
        <Button
          variant="danger-outline"
          size="sm"
          onClick={() => setConfirmingDelete(true)}
          class="mt-4"
        >
          Delete account
        </Button>
        <ConfirmDialog
          open={confirmingDelete()}
          title="Delete account?"
          description="This cannot be undone. Export your data first if you want to keep it."
          confirmLabel="Delete account and library"
          cancelLabel="Keep it"
          busy={deleting()}
          onConfirm={() => void remove()}
          onCancel={() => setConfirmingDelete(false)}
        />
      </section>
    </>
  )
}
