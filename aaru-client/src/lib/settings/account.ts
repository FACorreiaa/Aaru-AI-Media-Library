import { getConcertPlace } from '../concerts/server'
import type { ConcertPlaceSetting } from '../concerts/model'
import { getAccount } from '../imports/server'
import { getEntitlement } from '../plus/server'
import type { Entitlement } from '../plus/server'
import { getSignInConfig } from '../session/session'
import { getPushSetup } from '../push/server'
import { loadSocialSettings } from '../social/server'

/** What Settings → Account reads: who you are, how you sign in, and Aaru Plus. */
export async function loadAccountPage() {
  const [account, signIn, plus] = await Promise.all([
    getAccount(),
    getSignInConfig(),
    // An extra: without an answer, the Plus section stays hidden.
    getEntitlement().catch((): Entitlement | null => null),
  ])
  return { account, googleClientId: signIn.googleClientId, plus }
}

export type AccountPageData = Awaited<ReturnType<typeof loadAccountPage>>

/** What Settings → Friends & privacy reads: your handle, who sees your library, the city. */
export async function loadPrivacyPage() {
  const [account, sharing, concerts] = await Promise.all([
    getAccount(),
    loadSocialSettings(),
    // An extra: without an answer, the Location section stays hidden.
    getConcertPlace().catch((): ConcertPlaceSetting | null => null),
  ])
  return { handle: account.handle, sharing, concerts }
}

/** What Settings → Notifications reads. */
export const loadNotificationsPage = () => getPushSetup()
