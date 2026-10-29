// Universal links: the Apple apps claim aaruapp.com/i/* (friend invites, SOC-002) and /s/*
// (share links, SHR-002), so either opens Aaru when it is installed, and the web page when it
// is not. Apple's CDN fetches this file
// from /.well-known/apple-app-site-association; it must be JSON with no redirect.
const TEAM_ID = '84X9WYBF36'
const APP_IDS = ['com.fernandocorreia.aaru', 'com.fernandocorreia.aaru.beta']

export const APPLE_APP_SITE_ASSOCIATION = {
  applinks: {
    details: [
      {
        appIDs: APP_IDS.map((id) => `${TEAM_ID}.${id}`),
        components: [
          { '/': '/i/*', comment: 'Friend invite links' },
          { '/': '/s/*', comment: 'Share links' },
        ],
      },
    ],
  },
}

export function appleAppSiteAssociation(): Response {
  return new Response(JSON.stringify(APPLE_APP_SITE_ASSOCIATION), {
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  })
}
