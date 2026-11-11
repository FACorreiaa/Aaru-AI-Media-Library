import { useNavigate, useRouter } from '@tanstack/solid-router'
import { Show, createSignal, lazy } from 'solid-js'
import { GoogleSignInButton } from '../GoogleSignInButton'
import { AppearanceSection } from '../AppearanceSection'
import { Alert, AlertDescription, Button, toast } from '~/components/ui'
import {
  linkGoogle,
  signOut,
  signOutOtherDevices,
} from '../../lib/session/session'
import { forgetTonight } from '../../lib/home/tonight-cache'
import { forgetAccount, forgetSession } from '../../lib/session/query'
import type { AccountPageData } from '../../lib/settings/account'
import { plusLine } from '../../lib/plus/model'
import { FavoritesEditor } from './FavoritesEditor'
import { ProfileEditor } from './ProfileEditor'
import { SettingsPageTitle } from './SettingsNav'
import { SettingsSection } from './SettingsSection'

const ConfirmDialog = lazy(() =>
  import('../ConfirmDialog').then((m) => ({ default: m.ConfirmDialog })),
)

const providerNames = {
  apple: 'Apple',
  email: 'Email',
  google: 'Google',
} as const

/** Settings → Account (DESIGN.md §18): your profile (SOC-001b), favorites (FAV-001), how you
 * sign in, this device's appearance, and Sign out, which lives here only (UX-009). */
export function AccountPage(props: { data: AccountPageData }) {
  const router = useRouter()
  const navigate = useNavigate()
  const [account, setAccount] = createSignal(props.data.account)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [confirmingOthers, setConfirmingOthers] = createSignal(false)
  const [signingOutOthers, setSigningOutOthers] = createSignal(false)
  const [othersDone, setOthersDone] = createSignal(false)

  async function leaveOthers() {
    setProblem(null)
    setSigningOutOthers(true)
    try {
      await signOutOtherDevices()
      setOthersDone(true)
      toast('Signed out of your other devices.')
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'Other devices were not signed out.',
      )
    } finally {
      setSigningOutOthers(false)
      setConfirmingOthers(false)
    }
  }

  const providers = () =>
    account()
      .providers.map((p) => providerNames[p])
      .join(', ') || '—'
  const canLinkGoogle = () =>
    props.data.googleClientId && !account().providers.includes('google')
      ? props.data.googleClientId
      : null

  async function leave() {
    await signOut()
    forgetAccount(router.options.context.queryClient)
    forgetTonight()
    await router.invalidate()
    await navigate({ to: '/' })
  }

  return (
    <>
      <SettingsPageTitle title="Account" />
      <Show when={problem()}>
        {(message) => (
          <Alert variant="destructive" class="mb-6">
            <AlertDescription>{message()}</AlertDescription>
          </Alert>
        )}
      </Show>

      <ProfileEditor
        account={account()}
        sharing={props.data.sharing}
        sports={props.data.sports}
        onSaved={(saved) => {
          setAccount(saved)
          // The sidebar's account row and the top bar read the session, which the tab keeps
          // cached: a new name, handle or photo shows there at once.
          forgetSession(router.options.context.queryClient)
          void router.invalidate()
        }}
      />

      <Show when={props.data.favorites}>
        {(favorites) => <FavoritesEditor favorites={favorites()} />}
      </Show>

      <SettingsSection title="Signed in with" description={providers()}>
        <Show when={canLinkGoogle()}>
          {(clientId) => (
            <div class="max-w-xs">
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
      </SettingsSection>

      {/* BIL-005: with Plus off sale a free account has nothing here to read or buy. */}
      <Show when={props.data.plus?.plus ? props.data.plus : null}>
        {(plus) => (
          <SettingsSection title="Aaru Plus" description={plusLine(plus())} />
        )}
      </Show>

      <AppearanceSection />

      <SettingsSection
        title="Sign out"
        description="Signs this browser out. Your library stays as it is."
      >
        <Button variant="outline" onClick={() => void leave()}>
          Sign out
        </Button>
      </SettingsSection>

      <SettingsSection
        title="Sign out of other devices"
        description="Signs out every other browser and phone. You stay signed in here."
      >
        <Button variant="outline" onClick={() => setConfirmingOthers(true)}>
          Sign out of other devices
        </Button>
        <Show when={othersDone()}>
          <p class="mt-2 text-sm text-muted" role="status">
            Done. Your other devices are signed out.
          </p>
        </Show>
      </SettingsSection>
      <Show when={confirmingOthers()}>
        <ConfirmDialog
          open={confirmingOthers()}
          title="Sign out of other devices?"
          description="Every other browser and phone will need to sign in again. This one stays signed in."
          confirmLabel="Sign out of other devices"
          cancelLabel="Cancel"
          busy={signingOutOthers()}
          onConfirm={() => void leaveOthers()}
          onCancel={() => setConfirmingOthers(false)}
        />
      </Show>
    </>
  )
}
