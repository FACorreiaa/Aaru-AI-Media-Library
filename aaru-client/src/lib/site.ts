/** Public origin for absolute URLs (Open Graph). */
export const SITE_URL = 'https://aaruapp.com'

/** The owner's X account, linked from the landing page. */
export const X_URL = 'https://x.com/fatc88'

/** Aaru's channel in the shared Discord server, linked from the landing page and About. */
export const DISCORD_URL = 'https://discord.gg/GG55YPANC'

/**
 * Store listings. One universal purchase covers iPhone and Mac, so both links open the same
 * listing; `platform=mac` shows the Mac screenshots. Unset ones read "Coming soon".
 */
export const APP_STORE_URL: string | undefined =
  'https://apps.apple.com/pt/app/aaru-media-manager/id6821299076?l=en-GB'
export const MAC_APP_STORE_URL: string | undefined =
  'https://apps.apple.com/pt/app/aaru-media-manager/id6821299076?l=en-GB&platform=mac'
export const PLAY_STORE_URL: string | undefined = undefined
