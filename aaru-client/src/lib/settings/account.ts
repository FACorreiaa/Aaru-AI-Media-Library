import { getConcertPlace } from '../concerts/server'
import type { ConcertPlaceSetting } from '../concerts/model'
import { loadFavorites } from '../favorites/server'
import type { Favorites } from '../favorites/model'
import { getAccount } from '../imports/server'
import { getEntitlement } from '../plus/server'
import type { Entitlement } from '../plus/server'
import { getSignInConfig } from '../session/session'
import { getPushSetup } from '../push/server'
import { loadSocialSettings } from '../social/server'
import type { SocialSettings } from '../social/server'
import { getSportSettings } from '../sports/settings'
import type { SportSettings } from '../sports/model'

/** What Settings → Account reads: who you are, your favorites, how you sign in, and Aaru Plus. */
export async function loadAccountPage() {
  const [account, signIn, plus, favorites, sharing, sports] = await Promise.all(
    [
      getAccount(),
      getSignInConfig(),
      // An extra: without an answer, the Plus section stays hidden.
      getEntitlement().catch((): Entitlement | null => null),
      // An extra too: without an answer, the Favorites section stays hidden.
      loadFavorites().catch((): Favorites | null => null),
      // Extras for the profile (SOC-001b): the email switch, and the link to Sports.
      loadSocialSettings().catch((): SocialSettings | null => null),
      getSportSettings().catch((): SportSettings | null => null),
    ],
  )
  return {
    account,
    googleClientId: signIn.googleClientId,
    plus,
    favorites,
    sharing,
    sports: sports?.available ?? false,
  }
}

export type AccountPageData = Awaited<ReturnType<typeof loadAccountPage>>

/** What Settings → Friends & privacy reads: your handle, who sees your library, the city,
 * and the Sports country. */
export async function loadPrivacyPage() {
  const [account, sharing, concerts, sports] = await Promise.all([
    getAccount(),
    loadSocialSettings(),
    // An extra: without an answer, the Location section stays hidden.
    getConcertPlace().catch((): ConcertPlaceSetting | null => null),
    // An extra too: without an answer, or with Sports off, the Sports section stays hidden.
    getSportSettings().catch((): SportSettings | null => null),
  ])
  return { handle: account.handle, sharing, concerts, sports }
}

/** What Settings → Notifications reads. */
export const loadNotificationsPage = () => getPushSetup()
