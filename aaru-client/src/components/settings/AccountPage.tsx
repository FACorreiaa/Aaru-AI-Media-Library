import { useNavigate, useRouter } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { GoogleSignInButton } from '../GoogleSignInButton'
import { AppearanceSection } from '../AppearanceSection'
import { Alert, AlertDescription, Button } from '~/components/ui'
import { linkGoogle, signOut } from '../../lib/session/session'
import type { AccountPageData } from '../../lib/settings/account'
import { ProfileEditor } from './ProfileEditor'
import { SettingsPageTitle } from './SettingsNav'
import { SettingsSection } from './SettingsSection'

const providerNames = {
  apple: 'Apple',
  email: 'Email',
  google: 'Google',
} as const

/** Settings → Account (DESIGN.md §18): name and handle, how you sign in, this device's
 * appearance, and Sign out, which lives here only (UX-009). */
export function AccountPage(props: { data: AccountPageData }) {
  const router = useRouter()
  const navigate = useNavigate()
  const [account, setAccount] = createSignal(props.data.account)
  const [problem, setProblem] = createSignal<string | null>(null)

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
        handle={account().handle}
        displayName={account().displayName}
        onSaved={(user) => {
          setAccount({
            ...account(),
            handle: user.handle,
            displayName: user.displayName,
          })
          // The sidebar's account row reads the session.
          void router.invalidate()
        }}
      />

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

      <AppearanceSection />

      <SettingsSection
        title="Sign out"
        description="Signs this browser out. Your library stays as it is."
      >
        <Button variant="outline" onClick={() => void leave()}>
          Sign out
        </Button>
      </SettingsSection>
    </>
  )
}
