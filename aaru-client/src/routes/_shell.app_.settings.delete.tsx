import {
  Link,
  createFileRoute,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { SettingsPageTitle } from '../components/settings/SettingsNav'
import { SettingsSection } from '../components/settings/SettingsSection'
import { Alert, AlertDescription, Button } from '~/components/ui'
import { deleteAccount } from '../lib/imports/server'

// Settings → Delete account (DESIGN.md §18, UX-021): its own last page, in danger styling.
export const Route = createFileRoute('/_shell/app_/settings/delete')({
  head: () => ({ meta: [{ title: 'Delete account · Settings · Aaru' }] }),
  component: DeleteAccount,
})

function DeleteAccount() {
  const router = useRouter()
  const navigate = useNavigate()
  const [problem, setProblem] = createSignal<string | null>(null)
  const [confirming, setConfirming] = createSignal(false)
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
      setConfirming(false)
    }
  }

  return (
    <>
      <SettingsPageTitle title="Delete account" />
      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mb-6">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>
      <SettingsSection
        tone="danger"
        title="Delete your account"
        description={
          <>
            Your library, lists, imports, friends, groups and sessions leave
            Aaru for good.{' '}
            <Link
              to="/app/settings/data"
              hash="export"
              class="font-semibold text-accent hover:underline"
            >
              Export your data
            </Link>{' '}
            first if you want to keep it.
          </>
        }
      >
        <Button variant="destructive" onClick={() => setConfirming(true)}>
          Delete account
        </Button>
      </SettingsSection>
      <ConfirmDialog
        open={confirming()}
        title="Delete account?"
        description="This cannot be undone. Everything in your library goes with it."
        confirmLabel="Delete account and library"
        cancelLabel="Keep it"
        busy={deleting()}
        onConfirm={() => void remove()}
        onCancel={() => setConfirming(false)}
      />
    </>
  )
}
