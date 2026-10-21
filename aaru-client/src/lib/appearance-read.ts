import { createIsomorphicFn } from '@tanstack/solid-start'
import { getCookie } from '@tanstack/solid-start/server'
import {
  APPEARANCE_COOKIE,
  appearanceFromCookieHeader,
  parseAppearance,
} from './appearance'

/** This device's appearance: from the request on the server, from `document.cookie` after. */
export const readAppearance = createIsomorphicFn()
  .server(() => parseAppearance(getCookie(APPEARANCE_COOKIE)))
  .client(() => appearanceFromCookieHeader(document.cookie))
