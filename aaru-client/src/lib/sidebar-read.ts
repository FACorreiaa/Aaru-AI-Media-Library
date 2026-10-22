import { createIsomorphicFn } from '@tanstack/solid-start'
import { getCookie } from '@tanstack/solid-start/server'

// The sidebar's open or collapsed state, kept by shadcn's sidebar in this cookie, so the
// server renders the width the user left it at and the page does not jump on load.
const SIDEBAR_COOKIE = 'sidebar_state'

const parse = (value: string | undefined) => value !== 'false'

export const readSidebarOpen = createIsomorphicFn()
  .server(() => parse(getCookie(SIDEBAR_COOKIE)))
  .client(() => {
    const match = /(?:^|;\s*)sidebar_state=([^;]*)/.exec(document.cookie)
    return parse(match?.[1])
  })
