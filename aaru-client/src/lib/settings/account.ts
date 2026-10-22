import { getConcertPlace } from '../concerts/server'
import type { ConcertPlaceSetting } from '../concerts/model'
import { getAccount } from '../imports/server'
import { getSignInConfig } from '../session/session'
import { getPushSetup } from '../push/server'
import { loadSocial } from '../social/server'

/** What Settings → Account reads: who you are and how you sign in. */
export async function loadAccountPage() {
  const [account, signIn] = await Promise.all([getAccount(), getSignInConfig()])
  return { account, googleClientId: signIn.googleClientId }
}

export type AccountPageData = Awaited<ReturnType<typeof loadAccountPage>>

/** What Settings → Friends & privacy reads: your handle, friends, and the concerts city. */
export async function loadFriendsPage() {
  const [account, social, concerts] = await Promise.all([
    getAccount(),
    loadSocial(),
    // An extra: without an answer, the Location section stays hidden.
    getConcertPlace().catch((): ConcertPlaceSetting | null => null),
  ])
  return { handle: account.handle, social, concerts }
}

/** What Settings → Notifications reads. */
export const loadNotificationsPage = () => getPushSetup()
