import { getConcertPlace } from '../concerts/server'
import type { ConcertPlaceSetting } from '../concerts/model'
import { getAccount } from '../imports/server'
import { getSignInConfig } from '../session/session'
import { getPushSetup } from '../push/server'
import { loadSocial } from '../social/server'

/** What Settings' Account page reads. `/app/settings` shows the same page on a desktop. */
export async function loadAccountPage() {
  const [account, signIn, push, social, concerts] = await Promise.all([
    getAccount(),
    getSignInConfig(),
    getPushSetup(),
    loadSocial(),
    // An extra: without an answer, the "Concerts near" section stays hidden.
    getConcertPlace().catch((): ConcertPlaceSetting | null => null),
  ])
  return {
    account,
    push,
    social,
    concerts,
    googleClientId: signIn.googleClientId,
  }
}

export type AccountPageData = Awaited<ReturnType<typeof loadAccountPage>>
