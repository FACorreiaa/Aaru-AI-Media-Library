import { useNavigate, useRouter } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { GoogleSignInButton } from '../GoogleSignInButton'
import { AppearanceSection } from '../AppearanceSection'
import { Alert, AlertDescription, Button } from '~/components/ui'
import { linkGoogle, signOut } from '../../lib/session/session'
import { forgetTonight } from '../../lib/home/tonight-cache'
import { forgetAccount, forgetSession } from '../../lib/session/query'
import type { AccountPageData } from '../../lib/settings/account'
import { plusLine } from '../../lib/plus/model'
import { FavoritesEditor } from './FavoritesEditor'
import { ProfileEditor } from './ProfileEditor'
import { SettingsPageTitle } from './SettingsNav'
import { SettingsSection } from './SettingsSection'

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

      <Show when={props.data.plus}>
        {(plus) => (
          <SettingsSection title="Aaru Plus" description={plusLine(plus())}>
            <Show when={!plus().plus}>
              <p class="max-w-prose text-sm text-muted">
                Plus lifts the monthly limit on captures. It is bought in the
                Aaru app on iPhone, iPad or Mac, and works here as soon as it
                is.
              </p>
            </Show>
          </SettingsSection>
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
    </>
  )
}
