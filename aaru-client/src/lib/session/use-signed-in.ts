import { createSignal, onMount } from 'solid-js'
import { getSession } from './session'

/**
 * Whether the visitor is signed in, for the public pages (landing, About, Privacy; UX-014,
 * UX-015). Asked in the browser after the page renders, so their HTML stays the same for every
 * visitor and the first paint never waits on the session. False until it answers.
 */
export function useSignedIn() {
  const [signedIn, setSignedIn] = createSignal(false)
  onMount(() => {
    getSession().then(
      (session) => setSignedIn(session.signedIn),
      () => {},
    )
  })
  return signedIn
}
