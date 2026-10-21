# Web design-system audit (2026-10-21)

Wave 2 · C of the whole-app audit, on branch `audit/web`. Step 1 (Foundation) moved
`aaru-client` onto shadcn-solid on Kobalte (owner decision 2026-10-21, reversing DESIGN.md §17's
"Kobalte measured and dropped"). Step 2 builds the sidebar shell of DESIGN.md §18, works through
the "Web agent must do" list in `docs/audit/ux.md`, and migrates every route to the barrel.

Paths are `aaru-client/src/`. Severity: **high** breaks a task, hides state from assistive tech or
breaks the UI rule; **med** a raw element, an ad-hoc overlay or a width cap the shell replaces;
**low** drift and polish. Status starts `open`; step 2 marks each `fixed` or
`deferred (reason)`.

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

## Findings for step 2

| ID | Sev | Where | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| WEB-001 | high | `components/ui/badge.tsx` (Kobalte `Badge`) | Kobalte gives every Badge `role="status"`, so each calendar-cell and poster badge is a live region a screen reader may announce. | Render Badge without the live role (e.g. `role="none"` default in badge.tsx, or a plain span) and keep `status` only where a count changes live. | open |
| WEB-002 | high | `components/groups/dialogs.tsx:33`, `groups/MemberList.tsx:268`, `groups/DiscussButton.tsx:75` | Native `<dialog>`s with refs, outside the components: different focus, scroll lock and motion from every other modal. | `Dialog`/`DialogContent` (`placement="sheet"` for the member sheet) or `Drawer`; drop `.group-sheet` from styles.css. | open |
| WEB-003 | med | `components/groups/ChannelHeader.tsx:96`, `groups/shell.tsx:169`, `groups/Composer.tsx:125`, `groups/MessageList.tsx:761`, `groups/ShelfView.tsx:132`, `routes/app_.groups.tsx:164` | Hand-rolled menus and popovers (`.group-pop`), with their own open state, outside-click and keyboard handling. | `DropdownMenu`, `Popover`, `Command` (mention picker) from the barrel; drop `.group-pop`. | open |
| WEB-004 | med | `routes/app_.groups.tsx:153`, `routes/app_.groups.$groupId.tsx:127` | The tablet channel drawer is fixed-position classes plus `.group-drawer`. | `Sheet`-like `Drawer` (or the §18 `Sidebar` in its sheet mode). | open |
| WEB-005 | med | 49 files, 144 places (list below) | Raw `button`/`input`/`select`/`textarea`/`dialog` JSX; the lint rule warns. | `Button`, `TextField`/`Search`, `Select`, `Checkbox`, `NumberField`, `Dialog`. Rule to `error` when done. | open |
| WEB-006 | med | `components/AppHeader.tsx`, 14 route/component files with `max-w-3xl…7xl` (`app.tsx`, `app_.discover.tsx`, `app_.library.tsx`, `app_.lists.*`, `app_.music.tsx`, `app_.insights.tsx`, `app_.imports.$id.tsx`, `app_.title.$id.tsx`, `app_.settings.tsx`, `index.tsx`, `sign-in.tsx`, `ConcertList.tsx`) | Per-page header and width caps. | One layout route with the §18 Sidebar, fluid `main`, `max-w-prose` only for reading text. | open |
| WEB-007 | med | `components/ConcertPlaceSection.tsx:35`, `StremioSection.tsx:67`, `AppearanceSection.tsx:23`, `NotificationsSection.tsx:128`, `settings/AccountPage.tsx:48`, `settings/ImportsPage.tsx:214`, `routes/app_.settings.about.tsx:49` | Settings cards pass `block` to undo `Card`'s flex/gap layout, so they keep the old look without CardHeader/CardContent. | Rebuild on `CardHeader`/`CardTitle`/`CardDescription`/`CardContent` with the §18 settings IA. | open |
| WEB-008 | med | `components/ui/tabs.tsx` (TabsTrigger), `SearchPanel.tsx`, `WeekGrid.tsx` | shadcn's TabsTrigger is `focus-visible:outline-none` and shows focus on the sliding `TabsIndicator`; Aaru has no sliding indicator, so the two callers add the outline themselves. | Give TabsTrigger Aaru's focus outline in tabs.tsx (or an Aaru `pill` variant) and drop the call-site classes. | open |
| WEB-009 | med | `components/ui/toggle-group.tsx`, the 12 former segmented controls | ToggleGroup is buttons with `aria-pressed`; the old controls were a radio group (one choice, arrows move the choice). Kobalte ToggleGroup also lets a second tap clear the choice (callers ignore `null`). | Keep ToggleGroup per the plan, or use shadcn's `SegmentedControl` (a Kobalte radio group, also in the folder) for one-of-few filters; decide once for all twelve. | open |
| WEB-010 | low | `components/ui/calendar.tsx` (`data-[today]:bg-accent`), menus (`data-[highlighted]:bg-accent`) | shadcn's highlight is Aaru's teal, so today and the selected day are both teal in the calendar; menus highlight teal (intended). | Calendar today: ring or text-accent instead of the fill. | open |
| WEB-011 | low | Mount-only dialogs (`AddToListDialog`, `CityPicker`, `EpisodeSheet`, `calendar/DaySheet`, `calendar/CalendarEpisodeSheet`, `calendar/FiltersDialog`, `recap/RecapStory`) | The parent unmounts them on close, so Kobalte's exit animation never plays (the native dialog faded out). | Keep them mounted with an `open` signal and unmount after `onOpenChange(false)` settles, or accept no exit. | open |
| WEB-012 | low | `routes/app_.title.$id.tsx:476` | Rating stars are raw buttons in a row, no group semantics. | `ToggleGroup`/`RadioGroup` of stars with a label ("Rating, 4 of 5"). | open |
| WEB-013 | low | `components/ui/sidebar.tsx`, `hooks/use-mobile.ts` | `useIsMobile` switches at 767 px; §18 wants the persistent sidebar from 1024 px with the Sheet below. | Breakpoint for the shell (a param or Aaru's own constant) when step 2 builds it. | open |
| WEB-014 | low | `package.json` (`somoto@0.0.2`) | Sonner's Solid port is a 2024 0.0.x release; it tree-shakes and respects reduced motion, but it is the least maintained dependency. | Watch; swap for `solid-sonner` if it breaks. | open |
| WEB-015 | low | `components/SearchPanel.tsx:197`, `CityPicker.tsx:106`, `AddToListDialog.tsx:116`, `sign-in.tsx:170,213` | Search and sign-in fields are raw inputs with sr-only labels and their own focus rings. | `TextField` (`TextFieldLabel`, `TextFieldInput`) or `Search`; one focus ring. | open |

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
