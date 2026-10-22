import { getConcertPlace } from '../concerts/server'
import type { ConcertPlaceSetting } from '../concerts/model'
import { getAccount } from '../imports/server'
import { getSignInConfig } from '../session/session'
import { getPushSetup } from '../push/server'
import { loadSocialSettings } from '../social/server'

/** What Settings' Account page reads. `/app/settings` shows the same page on a desktop. */
export async function loadAccountPage() {
  const [account, signIn, push, sharing, concerts] = await Promise.all([
    getAccount(),
    getSignInConfig(),
    getPushSetup(),
    loadSocialSettings(),
    // An extra: without an answer, the "Concerts near" section stays hidden.
    getConcertPlace().catch((): ConcertPlaceSetting | null => null),
  ])
  return {
    account,
    push,
    sharing,
    concerts,
    googleClientId: signIn.googleClientId,
  }
}

export type AccountPageData = Awaited<ReturnType<typeof loadAccountPage>>
