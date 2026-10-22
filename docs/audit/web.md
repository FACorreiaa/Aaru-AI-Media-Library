# Web design-system audit (2026-10-21)

Wave 2 · C of the whole-app audit, on branch `audit/web`. Step 1 (Foundation) moved
`aaru-client` onto shadcn-solid on Kobalte (owner decision 2026-10-21, reversing DESIGN.md §17's
"Kobalte measured and dropped"). Step 2 builds the sidebar shell of DESIGN.md §18, works through
the "Web agent must do" list in `docs/audit/ux.md`, and migrates every route to the barrel.

Paths are `aaru-client/src/`. Severity: **high** breaks a task, hides state from assistive tech or
breaks the UI rule; **med** a raw element, an ad-hoc overlay or a width cap the shell replaces;
**low** drift and polish. Every finding is now `fixed` or `deferred (reason)`.

## Step 1: what landed

- Every shadcn-solid component (46, `hngngn/shadcn-solid@4c75b89`, the source the docs site
  renders) in `components/ui`, one file each under the registry's names, plus the barrel
  `components/ui/index.ts`. Registry helpers in `lib/cva.ts`, `lib/call-handler.ts`,
  `lib/combine-style.ts`, `hooks/use-mobile.ts`; one `cn` in `lib/utils.ts`; `components.json`
  on the `~/*` alias.
- Replaced: alert, alert-dialog, badge, button, card, dialog, radio-group, segmented-control,
  switch, tabs, toast. Segmented controls are `ToggleGroup` (Aaru's `ink`/`chip`/`surface`
  item variants); toasts are somoto's `toast()` through the barrel; the old AlertDialog props
  API is `components/ConfirmDialog.tsx`, composed from the AlertDialog parts.
- Theme: shadcn's variables point at Aaru's tokens in `styles.css`; `dark:` follows Aaru's
  appearance (system unless `<html data-theme>` pins one). `bg-muted` is the surface through
  Tailwind's background-only namespace, so `text-muted` keeps Aaru's meaning.
- Reduced motion: one rule in `styles.css` turns off `tw-animate-css` enter/exit, loops and
  the components' transitions. Motion stays in `lib/motion.ts` / `lib/reduced-motion.ts`.
- Lint: deep or relative `components/ui` imports are errors outside the folder; raw
  `button`/`input`/`select`/`textarea`/`dialog` JSX warns (144 warnings, below). It becomes an
  error at the end of step 2.

## Bundle

`npm run build && npm run size`, gzip -9, before = `origin/main` at `1825ab8`, after = this
branch with every caller migrated. `size-budget.json` re-seeded with `npm run size -- --update`
(3% over the after column). Without `"sideEffects": ["**/*.css"]` in `package.json` the barrel
did not tree-shake (Rollup kept every component module with a top-level call): shared JS was
152.2 KB and `/app` 174.2 KB. With it, the unused components (chart/unovis, carousel/embla,
command/cmdk, drawer, sidebar…) stay out of every route.

| Measure | Before (KB gz) | After (KB gz) | Δ |
| --- | ---: | ---: | ---: |
| total JS | 247.5 | 291.5 | +44.0 |
| CSS | 13.9 | 25.2 | +11.3 |
| shared (every page) | 72.0 | 83.7 | +11.7 |
| `/` | 80.6 | 92.3 | +11.7 |
| `/about` | 75.4 | 87.0 | +11.6 |
| `/app` | 95.3 | 115.4 | +20.1 |
| `/app_/discover` | 89.0 | 115.9 | +26.9 |
| `/app_/groups` | 85.0 | 96.6 | +11.6 |
| `/app_/groups/` | 74.0 | 85.7 | +11.7 |
| `/app_/groups/$groupId` | 75.9 | 87.5 | +11.6 |
| `/app_/groups/$groupId/` | 72.3 | 84.0 | +11.7 |
| `/app_/groups/$groupId/$channelId` | 89.6 | 101.3 | +11.7 |
| `/app_/imports/$id` | 76.2 | 87.9 | +11.7 |
| `/app_/insights` | 83.7 | 102.9 | +19.2 |
| `/app_/library` | 84.1 | 110.7 | +26.6 |
| `/app_/lists/` | 76.7 | 95.4 | +18.7 |
| `/app_/lists/$id` | 80.9 | 100.8 | +19.9 |
| `/app_/music` | 77.7 | 96.5 | +18.8 |
| `/app_/plans/$id` | 74.8 | 86.4 | +11.6 |
| `/app_/recap` | 85.8 | 105.4 | +19.6 |
| `/app_/settings` | 75.4 | 95.5 | +20.1 |
| `/app_/settings/` | 81.8 | 103.6 | +21.8 |
| `/app_/settings/about` | 75.2 | 94.2 | +19.0 |
| `/app_/settings/account` | 81.7 | 103.6 | +21.9 |
| `/app_/settings/connected` | 81.5 | 102.6 | +21.1 |
| `/app_/settings/imports` | 79.4 | 91.5 | +12.1 |
| `/app_/settings/recaps` | 73.0 | 84.7 | +11.7 |
| `/app_/title/$id` | 88.3 | 125.4 | +37.1 |
| `/app_/week` | 88.8 | 111.5 | +22.7 |
| `/auth/verify` | 73.0 | 84.6 | +11.6 |
| `/connect/extension` | 73.8 | 85.4 | +11.6 |
| `/oauth/consent` | 73.8 | 85.4 | +11.6 |
| `/privacy` | 77.3 | 89.0 | +11.7 |
| `/sign-in` | 76.1 | 87.8 | +11.7 |

## Step 2: what landed

- **Shell (DESIGN.md §18).** `routes/_shell.tsx` is one pathless layout for every `/app` page
  (files `_shell.app*.tsx`, URLs unchanged). Its `beforeLoad` is the one sign-in check, through
  `main`'s query cache (`requireSession`), and now carries `next` (UX-011). The shadcn-solid
  Sidebar is persistent and collapsible to icons from 1024px and a sheet below, with a top bar
  (wordmark, Search, menu); Home · Discover · Library · Calendar · Lists · Groups, then Insights
  and Settings, then the account row. Groups carries the mention badge. One Search dialog with
  ⌘K opens in place on every page; Home and Library lend it their library (`useSearchHost`).
  Back links name the page you came from (`BackLink`). Skip link, one Toaster.
- **Calendar** at `/app/calendar` (Week, Month, Missed); `/app/week` redirects with its search.
- **Settings**: eight pages with a rail from 768px and a list below; desktop `/app/settings`
  opens Account; `connected`, `imports`, `recaps` and the old hashes redirect; Trakt returns to
  `import`. Your data has the recaps, **History** (`GET /v1/actions`, Undo per action, by whom)
  and Export. Delete account calls the endpoint once (step 1 called it twice).
- **Title page**: Remove from library in its More menu behind a confirm
  (`DELETE /v1/library/items/{id}`), with a History link in the toast. Rating is a radio group.
- **Lint**: the raw-element rule is `error`, 0 warnings, 0 errors.
- **Merged `origin/main`** (query cache, CSRF guard, Now playing): its per-route guards fold
  into the shell; `NowPlayingCard` and `WeekStripCard` take their parts from the barrel.
- **First-load fixes found while measuring:** the router's default error and not-found pages
  imported `Button`, which put Kobalte and tailwind-merge (~13 KB) into every page's shared
  chunk; they now spell out the button's classes (one commented `eslint-disable`). `cardClass`
  moved to a module with no imports, so the landing page stops loading `cx`/tailwind-merge.

## Step 2 bundle

`npm run build && npm run size`, gzip -9. Left: `origin/main` at `4b1bb01`, built clean. Right:
this branch. `size-budget.json` re-seeded with `npm run size -- --update`.

| Measure | `origin/main` (KB gz) | This branch (KB gz) | Δ |
| --- | ---: | ---: | ---: |
| total JS | 251.6 | 364.7 | +113.1 |
| CSS | 14.0 | 25.7 | +11.7 |
| shared (every page) | 77.4 | 79.1 | +1.7 |
| `/` | 86.0 | 88.7 | +2.7 |
| `/about` | 80.8 | 83.9 | +3.1 |
| `/app` → `/_shell/app` | 99.1 | 116.1 | +17.0 |
| `/app_/discover` → `/_shell/app_/discover` | 91.3 | 114.8 | +23.5 |
| `/app_/groups` → `/_shell/app_/groups` | 89.9 | 115.6 | +25.7 |
| `/app_/groups/` → `/_shell/app_/groups/` | 79.4 | 81.1 | +1.7 |
| `/app_/groups/$groupId` → `/_shell/app_/groups/$groupId` | 81.3 | 88.0 | +6.7 |
| `/app_/groups/$groupId/` → `/_shell/app_/groups/$groupId/` | 77.8 | 79.4 | +1.6 |
| `/app_/groups/$groupId/$channelId` → `/_shell/app_/groups/$groupId/$channelId` | 95.0 | 97.7 | +2.7 |
| `/app_/imports/$id` → `/_shell/app_/imports/$id` | 81.6 | 82.9 | +1.3 |
| `/app_/insights` → `/_shell/app_/insights` | 88.3 | 93.6 | +5.3 |
| `/app_/library` → `/_shell/app_/library` | 88.9 | 108.3 | +19.4 |
| `/app_/lists/` → `/_shell/app_/lists/` | 82.2 | 86.9 | +4.7 |
| `/app_/lists/$id` → `/_shell/app_/lists/$id` | 83.1 | 102.2 | +19.1 |
| `/app_/music` → `/_shell/app_/music` | 83.1 | 88.2 | +5.1 |
| `/app_/plans/$id` → `/_shell/app_/plans/$id` | 80.2 | 81.7 | +1.5 |
| `/app_/recap` → `/_shell/app_/recap` | 87.9 | 90.1 | +2.2 |
| `/app_/settings` → `/_shell/app_/settings` | 80.9 | 81.0 | +0.1 |
| `/app_/settings/` → `/_shell/app_/settings/` | 87.2 | 79.5 | -7.7 |
| `/app_/settings/about` → `/_shell/app_/settings/about` | 80.6 | 82.9 | +2.3 |
| `/app_/settings/account` → `/_shell/app_/settings/account` | 87.2 | 92.2 | +5.0 |
| `/app_/settings/connected` → `/_shell/app_/settings/connections` | 86.9 | 98.6 | +11.7 |
| `/app_/settings/imports` → `/_shell/app_/settings/import` | 84.8 | 93.7 | +8.9 |
| `/app_/settings/recaps` → `/_shell/app_/settings/data` | 78.4 | 83.0 | +4.6 |
| `/app_/title/$id` → `/_shell/app_/title/$id` | 93.0 | 120.9 | +27.9 |
| `/app_/week` → `/_shell/app_/calendar` | 92.2 | 108.1 | +15.9 |
| `/auth/verify` | 78.4 | 93.8 | +15.4 |
| `/connect/extension` | 79.2 | 94.3 | +15.1 |
| `/oauth/consent` | 79.2 | 101.4 | +22.2 |
| `/privacy` | 82.7 | 85.6 | +2.9 |
| `/sign-in` | 81.5 | 101.9 | +20.4 |
| `/_shell` (new) | — | 138.7 | — |
| `/_shell/app_/settings/delete` (new) | — | 82.8 | — |
| `/_shell/app_/settings/friends` (new) | — | 88.7 | — |
| `/_shell/app_/settings/notifications` (new) | — | 85.9 | — |

Reading the table:

- `size-budget.mjs` measures the root's chunks plus the route's own preloads, so a child of
  `/_shell` leaves out the layout's own chunks. `/_shell` itself is 138.7 KB: shared (79.1) plus
  the shell's ~60 KB (tailwind-merge 8.4, floating-ui for the collapsed sidebar's tooltips 8.8,
  corvu's drawer for the phone sheet ~12, somoto's Toaster 8.5, the Search dialog, Kobalte's
  primitives). A signed-in page's real first load is the union: Home 99.1 → 175.7 KB, Calendar
  92.2 → 167.7, Title 93.0 → 180.5, Library 88.9 → 167.9, Settings → Account 90.6 → 153.7, a
  group channel 111.3 → 202.6. Most of it is step 1's Kobalte cost (accepted) now paid once in
  the shell rather than per page, and it is cached across navigations.
- Public pages: shared +1.7, landing +2.7 (it now asks for the session to say "Open Aaru"),
  About/Privacy +3. Sign-in +20.4, consent +22.2, the magic-link page +15.4 and the extension
  page +15.1 are `TextField`, `Checkbox` and `Button` from the barrel (WEB-015), i.e. Kobalte.
- Cheap follow-ups if the shell needs to shrink: `title` instead of `Tooltip` on the collapsed
  sidebar (−8.8), lazy-load the phone `Drawer` below 1024px (~−12), mount the Toaster on the
  first toast (−8.5). Not done here: each changes a vendored component's behaviour.

## Web items in `docs/audit/ux.md`

| Item | Status |
| --- | --- |
| UX-002, UX-006, UX-007, UX-008, UX-009, UX-004 (web) | fixed: the shell above |
| UX-005 | fixed: `/app/calendar`, `/app/week` redirects keeping search |
| UX-010 | fixed: Not found and the error page lead to `/app` under `/app`; the error page renders inside the shell there |
| UX-011 | fixed: `next` from the shell's guard, kept by sign-in, by the magic link (`lib/session/pending-next.ts`, same browser, 15 minutes) and by `/connect/extension` (`safeNext` now allows it) |
| UX-013 | fixed: tabs name the title, the list, the import, the channel and group |
| UX-014 | fixed: About and Privacy show "‹ Settings" and send the wordmark to `/app` when signed in |
| UX-015 | fixed: landing says "Open Aaru" when signed in; the FAQ names friends and groups as they are |
| UX-020…UX-027, UX-030, UX-031, UX-033, UX-034 | fixed: the eight Settings pages of §18 |
| UX-028 | deferred (owner): TV Time is a separate PR; the landing copy and `ImportSources` are untouched |
| UX-040 | fixed: "library", never "shelf", for the library (landing, sign-in, About, Home, Search, Discover, Recap, import ledger) |
| UX-041, UX-051 | fixed: a `shelf` channel reads List, a Room reads Watch party (UI only) |
| UX-042 | fixed: "group messages" wording in groups |
| UX-043 | fixed: Mark read / Mark listened; Watching; per-kind progress words in groups |
| UX-044, UX-045 | fixed: "Mark S1 · E5 watched"; one `episodeCode` ("S1 · E8") |
| UX-047 | fixed: one show-status label map |
| UX-048 | fixed: Grid / Rows; the Discover credit is built from the rows on screen |
| UX-049, UX-053 | fixed: the log page is Listens ("All listens ›"); "Year" |
| UX-050 | fixed: "This season’s list isn’t answering", "Concert listings aren’t answering" |
| UX-052 | fixed: no albums in Start watching |
| UX-054 | fixed: "watched, read and listened to" |
| UX-060, UX-061 | fixed: History with Undo; Remove from library |
| UX-064 | fixed: "gone" only on a 404, else an error with Try again |
| UX-066 | fixed: Discover's empty copy with Try again and Search; row-sized placeholders for Seasons and Concerts |
| UX-072 | fixed: an Add control on list members not in the library |
| UX-074 | fixed: handle and friends links to the new slugs |
| UX-075 | fixed: "Bring your history" on new-account Home and Library; "Clear filters" on a filtered-empty Library; one headline |
| UX-076 (web) | fixed: the Not end-to-end popover says what @aaru reads |
| UX-078 | fixed: Remove a failed import; "Showing 200 of 1,204" |
| UX-080 | fixed: Home's New list opens `/app/lists?new=1` on the name field |
| UX-081 | fixed: Recap closes back where it was opened and reloads on a new period |
| UX-083, UX-084, UX-086 | fixed: Discuss for every member, the owner's Leave hint, "All groups" on the rail and phone back |
| UX-087 | fixed: the empty calendar opens Search on Shows |
| UX-088 | fixed: `?kind=` on Library |
| UX-089 | fixed: the extension's success page has "Open Aaru" → Connections; "Disconnect" in its copy |

## Findings for step 2

| ID | Sev | Where | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| WEB-001 | high | `components/ui/badge.tsx` (Kobalte `Badge`) | Kobalte gives every Badge `role="status"`, so each calendar-cell and poster badge is a live region a screen reader may announce. | Render Badge without the live role (e.g. `role="none"` default in badge.tsx, or a plain span) and keep `status` only where a count changes live. | fixed: `Badge` is a plain `<span data-slot="badge">`; no live role anywhere |
| WEB-002 | high | `components/groups/dialogs.tsx:33`, `groups/MemberList.tsx:268`, `groups/DiscussButton.tsx:75` | Native `<dialog>`s with refs, outside the components: different focus, scroll lock and motion from every other modal. | `Dialog`/`DialogContent` (`placement="sheet"` for the member sheet) or `Drawer`; drop `.group-sheet` from styles.css. | fixed: every group dialog is the shared `Dialog`/`ConfirmDialog`; `.group-sheet` gone |
| WEB-003 | med | `components/groups/ChannelHeader.tsx:96`, `groups/shell.tsx:169`, `groups/Composer.tsx:125`, `groups/MessageList.tsx:761`, `groups/ShelfView.tsx:132`, `routes/app_.groups.tsx:164` | Hand-rolled menus and popovers (`.group-pop`), with their own open state, outside-click and keyboard handling. | `DropdownMenu`, `Popover`, `Command` (mention picker) from the barrel; drop `.group-pop`. | fixed: `DropdownMenu` and `Popover`; `.group-pop` gone. The @mention list stays inline under the composer (focus must stay in the field) with a CSS fade-in |
| WEB-004 | med | `routes/app_.groups.tsx:153`, `routes/app_.groups.$groupId.tsx:127` | The tablet channel drawer is fixed-position classes plus `.group-drawer`. | `Sheet`-like `Drawer` (or the §18 `Sidebar` in its sheet mode). | fixed: the tablet rail and channels are a left `Drawer`; `.group-drawer` gone |
| WEB-005 | med | 49 files, 144 places (list below) | Raw `button`/`input`/`select`/`textarea`/`dialog` JSX; the lint rule warns. | `Button`, `TextField`/`Search`, `Select`, `Checkbox`, `NumberField`, `Dialog`. Rule to `error` when done. | fixed: 0 raw elements; the rule is `error`. One commented exception: `RouteError`'s Try again (see Step 2) |
| WEB-006 | med | `components/AppHeader.tsx`, 14 route/component files with `max-w-3xl…7xl` (`app.tsx`, `app_.discover.tsx`, `app_.library.tsx`, `app_.lists.*`, `app_.music.tsx`, `app_.insights.tsx`, `app_.imports.$id.tsx`, `app_.title.$id.tsx`, `app_.settings.tsx`, `index.tsx`, `sign-in.tsx`, `ConcertList.tsx`) | Per-page header and width caps. | One layout route with the §18 Sidebar, fluid `main`, `max-w-prose` only for reading text. | fixed: `AppHeader` deleted; one `_shell` layout; page frames are fluid with `auto-fill` grids. Kept on purpose: `max-w-prose` for reading text, `max-w-3xl` for the Settings form column, `max-w-[56rem]` for list and import rows (they read top to bottom), `max-w-xl`/`2xl` for the create-list form and a request card |
| WEB-007 | med | `components/ConcertPlaceSection.tsx:35`, `StremioSection.tsx:67`, `AppearanceSection.tsx:23`, `NotificationsSection.tsx:128`, `settings/AccountPage.tsx:48`, `settings/ImportsPage.tsx:214`, `routes/app_.settings.about.tsx:49` | Settings cards pass `block` to undo `Card`'s flex/gap layout, so they keep the old look without CardHeader/CardContent. | Rebuild on `CardHeader`/`CardTitle`/`CardDescription`/`CardContent` with the §18 settings IA. | fixed: every settings card is `SettingsSection` (CardHeader/CardDescription/CardContent/CardFooter) |
| WEB-008 | med | `components/ui/tabs.tsx` (TabsTrigger), `SearchPanel.tsx`, `WeekGrid.tsx` | shadcn's TabsTrigger is `focus-visible:outline-none` and shows focus on the sliding `TabsIndicator`; Aaru has no sliding indicator, so the two callers add the outline themselves. | Give TabsTrigger Aaru's focus outline in tabs.tsx (or an Aaru `pill` variant) and drop the call-site classes. | fixed: `TabsTrigger` carries Aaru's focus outline; the SearchPanel and WeekGrid overrides are gone |
| WEB-009 | med | `components/ui/toggle-group.tsx`, the 12 former segmented controls | ToggleGroup is buttons with `aria-pressed`; the old controls were a radio group (one choice, arrows move the choice). Kobalte ToggleGroup also lets a second tap clear the choice (callers ignore `null`). | Keep ToggleGroup per the plan, or use shadcn's `SegmentedControl` (a Kobalte radio group, also in the folder) for one-of-few filters; decide once for all twelve. | fixed: `Segmented` (SegmentedControl, radio) for all 13 one-of-N controls; `ui/toggle-group.tsx` deleted. `ToggleButton` stays for a real toggle |
| WEB-010 | low | `components/ui/calendar.tsx` (`data-[today]:bg-accent`), menus (`data-[highlighted]:bg-accent`) | shadcn's highlight is Aaru's teal, so today and the selected day are both teal in the calendar; menus highlight teal (intended). | Calendar today: ring or text-accent instead of the fill. | fixed: today is a ring and teal text in `ui/calendar.tsx` |
| WEB-011 | low | Mount-only dialogs (`AddToListDialog`, `CityPicker`, `EpisodeSheet`, `calendar/DaySheet`, `calendar/CalendarEpisodeSheet`, `calendar/FiltersDialog`, `recap/RecapStory`) | The parent unmounts them on close, so Kobalte's exit animation never plays (the native dialog faded out). | Keep them mounted with an `open` signal and unmount after `onOpenChange(false)` settles, or accept no exit. | fixed: `AddToListDialog`, `CityPicker`, `EpisodeSheet`, `DaySheet`, `CalendarEpisodeSheet`, `FiltersDialog`, `RecapStory` and the group dialogs take `open` and stay mounted through `lastShown` (`lib/presence.ts`) |
| WEB-012 | low | `routes/app_.title.$id.tsx:476` | Rating stars are raw buttons in a row, no group semantics. | `ToggleGroup`/`RadioGroup` of stars with a label ("Rating, 4 of 5"). | fixed: a `RadioGroup` of stars (arrow keys), with Clear |
| WEB-013 | low | `components/ui/sidebar.tsx`, `hooks/use-mobile.ts` | `useIsMobile` switches at 767 px; §18 wants the persistent sidebar from 1024 px with the Sheet below. | Breakpoint for the shell (a param or Aaru's own constant) when step 2 builds it. | fixed: the Sidebar has its own `SIDEBAR_SHEET_MAX = 1023`; `useIsMobile` keeps 767 and starts false (hydration-safe) |
| WEB-014 | low | `package.json` (`somoto@0.0.2`) | Sonner's Solid port is a 2024 0.0.x release; it tree-shakes and respects reduced motion, but it is the least maintained dependency. | Watch; swap for `solid-sonner` if it breaks. | deferred (kept by the owner): somoto 0.0.2 is the least maintained dependency (8.5 KB gz in the shell). If it breaks, swap for `solid-sonner` behind the same `toast()` barrel export |
| WEB-015 | low | `components/SearchPanel.tsx:197`, `CityPicker.tsx:106`, `AddToListDialog.tsx:116`, `sign-in.tsx:170,213` | Search and sign-in fields are raw inputs with sr-only labels and their own focus rings. | `TextField` (`TextFieldLabel`, `TextFieldInput`) or `Search`; one focus ring. | fixed: Search, City picker, Add to list and sign-in fields are `TextField`/`TextFieldInput`; one focus ring |

### Raw elements (WEB-005), by file

`components/groups/WatchPanel.tsx` 12 · `groups/dialogs.tsx` 12 · `groups/MessageList.tsx` 11 ·
`SocialSection.tsx` 8 · `routes/app_.title.$id.tsx` 6 · `ConnectionsSection.tsx` 5 ·
`groups/ShelfView.tsx` 5 · `groups/Spoilers.tsx` 5 · `routes/app_.lists.index.tsx` 5 ·
`groups/DiscussButton.tsx` 4 · `groups/MemberList.tsx` 4 · `routes/app_.groups.index.tsx` 4 ·
`CatImport.tsx` 3 · `HomeRows.tsx` 3 · `SearchPanel.tsx` 3 · `groups/ChannelList.tsx` 3 ·
`groups/TitlePicker.tsx` 3 · `routes/app_.library.tsx` 3 · two each: `AddControl`,
`AddToListDialog`, `CityPicker`, `SeasonBrowser`, `StremioSection`, `calendar/CalendarToolbar`,
`groups/ChannelHeader`, `groups/Composer`, `recap/RecapStory`, `settings/ImportsPage`,
`routes/app_.imports.$id`, `routes/app_.insights`, `routes/oauth.consent`, `routes/sign-in` ·
one each: `EpisodeSheet`, `MonthCalendar`, `MusicSection`, `SeasonMap`, `StremioHistoryImport`,
`TraktImport`, `WeekGrid`, `calendar/EpisodeRow`, `calendar/WatchButton`, `groups/AgentParts`,
`groups/GroupRail`, `groups/TitleCard`, `groups/shell`, `library/NowSection`, `routes/app`,
`routes/app_.groups`, `routes/app_.lists.$id`. `npx eslint src` lists each line.
