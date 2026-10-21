import { createSignal, onCleanup, onMount } from 'solid-js'
import { resolvedScheme } from '../lib/appearance'

/** Apple's JS SDK, loaded only on the sign-in page. */
const SDK =
  'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js'

interface AppleSignInResult {
  authorization: { id_token: string }
  user?: { name?: { firstName?: string; lastName?: string } }
}

declare global {
  interface Window {
    AppleID?: {
      auth: {
        init: (config: Record<string, unknown>) => void
      }
    }
  }
}

export interface AppleCredential {
  identityToken: string
  nonce: string
  displayName?: string
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  )
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

function randomNonce(): string {
  return [...crypto.getRandomValues(new Uint8Array(32))]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/**
 * Sign in with Apple on the web: Apple's own button, in a popup. The raw nonce goes to Aaru
 * and its SHA-256 to Apple, the same contract as the Apple apps. Needs a Services ID on a
 * verified domain.
 */
export function AppleSignInButton(props: {
  servicesId: string
  onCredential: (credential: AppleCredential) => void
  onError: (message: string) => void
}) {
  const [loaded, setLoaded] = createSignal(false)
  const nonce = randomNonce()
  const dark = resolvedScheme() === 'dark'

  const onSuccess = (event: Event) => {
    const result = (event as CustomEvent<AppleSignInResult>).detail
    const name = [result.user?.name?.firstName, result.user?.name?.lastName]
      .filter(Boolean)
      .join(' ')
    props.onCredential({
      identityToken: result.authorization.id_token,
      nonce,
      displayName: name || undefined,
    })
  }
  const onFailure = (event: Event) => {
    // Closing Apple's popup is not an error worth showing.
    const code = (event as CustomEvent<{ error?: string }>).detail.error
    if (
      code !== 'popup_closed_by_user' &&
      code !== 'user_cancelled_authorize'
    ) {
      props.onError('Apple sign-in did not finish. Try again.')
    }
  }

  onMount(() => {
    document.addEventListener('AppleIDSignInOnSuccess', onSuccess)
    document.addEventListener('AppleIDSignInOnFailure', onFailure)
    const init = async () => {
      window.AppleID?.auth.init({
        clientId: props.servicesId,
        scope: 'name email',
        redirectURI: `${window.location.origin}/sign-in`,
        usePopup: true,
        nonce: await sha256Hex(nonce),
      })
      setLoaded(true)
    }
    if (window.AppleID) return void init()
    const script = document.createElement('script')
    script.src = SDK
    script.async = true
    script.onload = () => void init()
    script.onerror = () => props.onError('Sign in with Apple could not load.')
    document.head.appendChild(script)
  })

  onCleanup(() => {
    document.removeEventListener('AppleIDSignInOnSuccess', onSuccess)
    document.removeEventListener('AppleIDSignInOnFailure', onFailure)
  })

  return (
    <div
      id="appleid-signin"
      class="h-13 w-full overflow-hidden rounded-full"
      classList={{ 'opacity-0': !loaded() }}
      data-color={dark ? 'white' : 'black'}
      data-border="false"
      data-type="sign-in"
      data-mode="center-align"
      data-border-radius="50"
      data-height="52"
    />
  )
}
