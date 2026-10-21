import { useNavigate, useRouter } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { ConcertPlaceSection } from '../ConcertPlaceSection'
import { GoogleSignInButton } from '../GoogleSignInButton'
import { NotificationsSection } from '../NotificationsSection'
import { SocialSection } from '../SocialSection'
import { Alert } from '../ui/alert'
import { Button } from '../ui/button'
import { Card } from '../ui/card'
import { linkGoogle, signOut } from '../../lib/session/session'
import type { AccountPageData } from '../../lib/settings/account'
import { SettingsPageTitle } from './SettingsNav'

const providerNames = {
  apple: 'Apple',
  email: 'Email',
  google: 'Google',
} as const

/** Settings → Account: who you are, how you sign in, friends, notifications and concerts. */
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
        {(message) => <Alert class="mt-4">{message()}</Alert>}
      </Show>

      <Card class="mt-6 p-5">
        <dl class="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
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
        <Button size="sm" onClick={leave} class="mt-4">
          Sign out
        </Button>
      </Card>

      <SocialSection
        handle={account().handle}
        displayName={account().displayName}
        state={props.data.social}
        onProfileSaved={(user) =>
          setAccount({
            ...account(),
            handle: user.handle,
            displayName: user.displayName,
          })
        }
      />

      <NotificationsSection setup={props.data.push} />

      <Show when={props.data.concerts?.available ? props.data.concerts : null}>
        {(setting) => <ConcertPlaceSection setting={setting()} />}
      </Show>
    </>
  )
}
