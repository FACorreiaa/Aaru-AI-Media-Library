import { getAccount } from '../imports/server'
import { getSignInConfig } from '../session/session'
import { getPushSetup } from '../push/server'
import { loadSocial } from '../social/server'

/** What Settings' Account page reads. `/app/settings` shows the same page on a desktop. */
export async function loadAccountPage() {
  const [account, signIn, push, social] = await Promise.all([
    getAccount(),
    getSignInConfig(),
    getPushSetup(),
    loadSocial(),
  ])
  return { account, push, social, googleClientId: signIn.googleClientId }
}

export type AccountPageData = Awaited<ReturnType<typeof loadAccountPage>>
