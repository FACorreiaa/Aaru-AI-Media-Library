// The "Where to watch" country (SPT-003): ISO 3166-1 alpha-2 codes, named by the runtime's
// own region names. Its own module: Settings needs only this, not the rest of Sports.

const CODES =
  'AD AE AF AG AI AL AM AO AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR ' +
  'BS BT BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ ' +
  'EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GT GU GW ' +
  'GY HK HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY ' +
  'KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU ' +
  'MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT ' +
  'PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC ' +
  'TD TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG US UY UZ VA VC VE VG VI VN VU WF WS YE YT ' +
  'ZA ZM ZW'

export const COUNTRY_CODES: readonly string[] = CODES.split(' ')

const known = new Set(COUNTRY_CODES)

export type Country = { code: string; name: string }

let names: Intl.DisplayNames | null | undefined

/** "GB" → "United Kingdom"; the code itself where the runtime has no region names. */
export function countryName(code: string): string {
  if (names === undefined) {
    try {
      names = new Intl.DisplayNames(['en'], { type: 'region' })
    } catch {
      names = null
    }
  }
  try {
    return names?.of(code) ?? code
  } catch {
    return code
  }
}

/** Every country, A to Z by name. */
export function countries(): Country[] {
  return COUNTRY_CODES.map((code) => ({ code, name: countryName(code) })).sort(
    (a, b) => a.name.localeCompare(b.name),
  )
}

/** The region in a language tag ("en-GB", "zh-Hant-TW", "pt_BR"), if it is a country. */
export function regionOf(language: string | undefined): string | null {
  if (!language) return null
  const parts = language.split(/[-_]/).slice(1)
  for (const part of parts) {
    if (/^[A-Za-z]{2}$/.test(part)) {
      const code = part.toUpperCase()
      return known.has(code) ? code : null
    }
  }
  return null
}

/** True for a code this list knows. */
export const isCountryCode = (code: string | null | undefined) =>
  !!code && known.has(code)
