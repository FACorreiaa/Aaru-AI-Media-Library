import { describe, expect, it } from 'vitest'
import { appleAppSiteAssociation } from './apple'

describe('apple-app-site-association', () => {
  it('claims only invite links, for the App Store and Beta apps', async () => {
    const response = appleAppSiteAssociation()
    expect(response.headers.get('Content-Type')).toBe('application/json')
    const body = await response.json<{
      applinks: { details: { appIDs: string[]; components: object[] }[] }
    }>()
    const [detail] = body.applinks.details
    expect(detail.appIDs).toEqual([
      '84X9WYBF36.com.fernandocorreia.aaru',
      '84X9WYBF36.com.fernandocorreia.aaru.beta',
    ])
    expect(detail.components).toEqual([
      { '/': '/i/*', comment: 'Friend invite links' },
    ])
  })
})
