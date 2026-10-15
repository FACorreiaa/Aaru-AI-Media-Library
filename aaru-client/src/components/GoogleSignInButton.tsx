import { onMount } from 'solid-js'

/** Google Identity Services, loaded only where the button shows. */
const SDK = 'https://accounts.google.com/gsi/client?hl=en'

interface GoogleIdApi {
  initialize: (config: {
    client_id: string
    callback: (response: { credential?: string }) => void
    nonce: string
    ux_mode: 'popup'
    use_fedcm_for_button?: boolean
  }) => void
  renderButton: (parent: HTMLElement, options: Record<string, unknown>) => void
}

declare global {
  interface Window {
    google?: { accounts: { id: GoogleIdApi } }
  }
}

export interface GoogleCredential {
  idToken: string
  nonce: string
}

function randomNonce(): string {
  return [...crypto.getRandomValues(new Uint8Array(32))]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/**
 * Sign in with Google on the web (AUTH-005): Google's own button, in a popup. Its ID token goes
 * to Aaru, which verifies it; the nonce we chose must come back inside it. The web client's
 * origin list must hold this page's origin.
 */
export function GoogleSignInButton(props: {
  clientId: string
  text?: 'continue_with' | 'signin_with'
  onCredential: (credential: GoogleCredential) => void
  onError: (message: string) => void
}) {
  let host!: HTMLDivElement
  const nonce = randomNonce()

  onMount(() => {
    const render = () => {
      const id = window.google?.accounts.id
      if (!id) return props.onError('Sign in with Google could not load.')
      id.initialize({
        client_id: props.clientId,
        nonce,
        ux_mode: 'popup',
        use_fedcm_for_button: true,
        callback: (response) => {
          if (response.credential)
            props.onCredential({ idToken: response.credential, nonce })
          else props.onError('Google sign-in did not finish. Try again.')
        },
      })
      id.renderButton(host, {
        type: 'standard',
        theme: window.matchMedia('(prefers-color-scheme: dark)').matches
          ? 'filled_black'
          : 'outline',
        size: 'large',
        shape: 'pill',
        text: props.text ?? 'continue_with',
        logo_alignment: 'center',
        // The apps are English-only; keep Google's label in step.
        locale: 'en',
        width: Math.min(host.clientWidth || 400, 400),
      })
    }
    if (window.google?.accounts.id) return render()
    const script = document.createElement('script')
    script.src = SDK
    script.async = true
    script.onload = render
    script.onerror = () => props.onError('Sign in with Google could not load.')
    document.head.appendChild(script)
  })

  return <div ref={host} class="flex min-h-11 w-full justify-center" />
}
