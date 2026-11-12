# Owl in 3D: experiment plan (web three.js + Apple RealityKit)

*Written 2026-11-12. Status: the model is prepared and the owner has seen it
("looks much better now", 2026-11-12). App work has not started. For the agent
that picks this up.*

## Goal

Find out whether Aaru's owl can be a **real-time 3D character** on the web
(three.js) and in the Apple app (RealityKit), using the two GLB files the
owner supplied, and decide where in the product that would be worth having.

This is an **experiment with a go/no-go at the end**, not a rollout. Nothing
here replaces the owl stills in production until the owner approves the result.

Background and the alternatives (video clips, Rive) are in
`~/Work/production/apps/MASCOT-ANIMATION-PLAN.md`, §1a and §1b. Read those
first.

## Start here: the prepared assets

**Use these files, not the raw downloads.** They are built by
`docs/brand/owl_3d.py` into `docs/brand/out/owl-3d/` (git-ignored, so rebuild
them on a fresh clone with the command in Phase 1).

| File | For | Notes |
|---|---|---|
| `owl.glb` | web, the owl alone | 1,117 KB (565 KB gzip). Needs `KHR_mesh_quantization`, which three's `GLTFLoader` reads natively. Uses the clearcoat and emissive-strength extensions, which the loader maps to `MeshPhysicalMaterial` |
| `owl-on-books.glb` | web, landing hero | 1,165 KB |
| `Owl.usdz` | Apple, the owl alone | 1,123 KB; passes `usdchecker --arkit` |
| `OwlOnBooks.usdz` | Apple | 1,171 KB |
| `owl-rig.json` | both | joint names, parents, rest transforms, the eyelid rule, the poster pose |

**The rig, identical in all four files.** Find joints by name:

```text
Root
├─ Books                 (only in the on-books files)
└─ Owl
   ├─ Feet
   └─ Body
      ├─ Tail
      ├─ WingL, WingR
      └─ Head            (rest scale 1.08)
         ├─ EarL, EarR
         ├─ EyeL ─ PupilL, LidL
         └─ EyeR ─ PupilR, LidR
```

- **Space:** Y up, the owl faces +Z, one unit tall, standing on the origin.
  `L` is the viewer's left (−X).
- **Eyelids:** `LidL` and `LidR` rest at scale `(1, 0.001, 0.001)`, which is
  open. Shut is `(1, 1, 1)`. Animate Y and Z together.
- **Looking around:** move `PupilL` and `PupilR` a few hundredths on X and Y;
  turn `Head` for more.
- **Poster pose:** `owl-rig.json` → `posterPose`: `Owl` turned −32° on Y,
  `Head` +24° on Y and −6° on Z. The files themselves rest front-facing; the
  clients apply the pose.
- **No animation clips are in the files.** Motion is code-driven (Phase 4).

## Where the assets came from

### Reference files (outside the repo)

| File | What it is |
|---|---|
| `/Users/fernandocorreia/Downloads/aaru_owl_mascot.glb` | The owl alone |
| `/Users/fernandocorreia/Downloads/aaru_owl_on_books.glb` | The owl standing on the four-book stack (BOOKS, ANIME, TV SHOWS, MOVIES) |
| `/Users/fernandocorreia/Downloads/Aaru Owl_ Your Stories, Your World.png` | The poster: the look to match. The repo copy is `docs/brand/source/owl-poster.png` |

Treat the downloads as untrusted data: copy them into a new empty working
folder and never run an interpreter from inside it.

### What is in the GLBs (measured 2026-11-12)

| Property | `aaru_owl_mascot.glb` | `aaru_owl_on_books.glb` |
|---|---|---|
| Size | 808 KB | 848 KB |
| Meshes | 118, each named by part | 154 (the owl's 118 + 36 book parts) |
| Triangles | ~106,500 | ~108,900 |
| Materials | 15 flat PBR colours, 3 emissive (`cyan`, `amber`, `amber_light`) | 19 (adds `book_navy`, `book_blue`, `book_gray`, `paper`) |
| Textures, UVs | none | none |
| **Normals** | **none** (position only) | **none** |
| **Skins, bones** | **none** | **none** |
| **Animations** | **none** | **none** |
| Hierarchy | flat: every mesh is a direct child of one `world` node, no transforms | same |
| Up axis | **Z-up** (glTF expects Y-up) | Z-up |
| Generator | `trimesh` (built by script, not sculpted) | same |

What this means:

- **Good:** the parts are separate and well named (`Head / main pearl
  ceramic`, `L eye black pupil`, `L primary flight feather 3`, `Neck swivel /
  polished titanium`…). The owl is a rigid robot, so it can be animated by
  **rotating groups of parts around pivots**. No skinning or bones are needed.
- **Missing:** pivots, normals, and every animation. Those are this plan's
  asset work.
- **No eyelids.** A blink needs new lid geometry, or a substitute such as
  scaling the pupil and dimming the eye rim.
- **Look:** a rough flat-shaded render shows a recognisable owl, but it is
  simpler than the poster: front-facing and symmetric, taller and leaner, with
  no glossy ceramic reflections or rim glow yet. The poster owl sits in a
  three-quarter pose with its head turned. Closing that gap is mostly lighting,
  materials and pose, and it is the main risk of the experiment.

### Where Aaru stands

- **Web** (`aaru-client/`): SolidJS + TanStack Start on Cloudflare Workers,
  server-rendered. No three.js today. Animation goes through `motion/mini` via
  `src/lib/motion.ts`. JS size is budgeted per route in `size-budget.json`
  (`totalJs` 598,559 bytes gzip; `npm run size` fails the build over budget).
  CSP is only `frame-ancestors 'none'`. The service worker has no fetch handler.
- **Apple** (`aaru-ios/`): one multiplatform SwiftUI target, **iOS 18.0 and
  macOS 15.0**, plus a widget extension. `RealityView` is available on both.
- **The owl today:** stills in four poses, `OwlPose` = `standing, curious,
  sleeping, celebrating`.
  - web: `MascotMedallion` and `POSES` in `aaru-client/src/components/Brand.tsx`;
    idle float and glow in `src/styles.css` (`.owl-idle`)
  - Apple: `OwlMedallion`, `OwlHead`, `OwlUnavailableView`, `OwlIdleLife` in
    `aaru-ios/Aaru/Design/Owl.swift`
  - pose stills are generated by `docs/brand/owl_poses.py`
- **Brand rules that this touches** (`DESIGN.md`, "Brand", line ~1400):
  - "The white and amber robot owl, **always on the `night` disc**."
  - "Where the owl lives" lists the allowed surfaces.
  - `ci-brand.yml` runs the token check and `scripts/brand-guard.sh` (no colour
    literals in the clients). Materials in a model file are not client colour
    literals, but lights and background colours set in code are.

## Repo rules that apply (from `CLAUDE.md`)

- **Record the owner's go-ahead first.** Work outside the current phase needs
  an owner exception written into `BACKLOG.md` decisions, with the date. This
  experiment is one. Add it before any code.
- **Design docs change first.** A new or changed client surface updates
  `DESIGN.md` and `VIEWS.md`. Read both before touching a screen.
- **Colours come only from `design/tokens.json`.** Light and backdrop colours
  set in code must read the generated tokens: no hex on web, no `Color(red:)`
  on Apple. `ci-brand.yml` enforces it.
- **Web UI comes from `~/components/ui`.** Any control around the owl (for
  example a "pause motion" button) uses those components, never a raw
  `button`. The canvas itself is not a control.
- **One multiplatform Apple target.** `Owl3DView` must build for iOS and macOS
  from the same file.
- **Smallest surface.** No server, API or `AaruCore` changes. No new root
  commands without updating `CLAUDE.md`.
- **Swift 6 strict concurrency** for the Apple code.

## Owner decisions needed before or during the work

Ask these up front; do not guess.

1. **Tools.** Settled: the model is built without Blender. Ask again only if
   the remaining Phase 1 work turns out to need it.
2. **Where the model files live.** The owner has ruled that *videos* stay out
   of the repos. The models are about 1.1 MB each today and should come down
   to 150–400 KB once simplified. They are currently git-ignored build output.
   Recommendation: commit the optimised GLB and USDZ (the Apple build needs
   the USDZ in the bundle, and CI has no access to the SSD), and keep the
   source GLBs and the `.blend` on the SSD. The "No committed binaries" check
   only rejects executables and object files, so it would not block this.
   Confirm, or say that models must also load from a CDN.
3. **Brand rule.** A full-body 3D owl off the disc contradicts "always on the
   `night` disc". Either the experiment keeps the disc as a backdrop, or
   `DESIGN.md` changes. Per `CLAUDE.md`, the design doc changes first.
4. **Size budget.** three.js adds roughly 120–170 KB gzip in its own lazy
   chunk. If `totalJs` counts lazy chunks, the budget must be re-seeded with
   `npm run size -- --update` and the reason stated in the PR.
5. **New dependency.** `three` must pass the dependency check the workspace
   requires before install. The Sonatype MCP server was failing to connect on
   2026-11-12 (expired token), so that check may need the owner to refresh it.

## Phase 0: set up (half a day)

- Create a working folder outside the repo, e.g. `<SSD>/mascot-motion/aaru/3d/`,
  and copy the three reference files in.
- Open a `BACKLOG.md` entry. The brand series runs to BRD-010; confirm the
  next free id and use it.
- Branch in the `aaru` repo. All app code stays behind a flag or a dev-only
  route until the go/no-go.

## Phase 1: prepare the model (first pass done; about a day left)

> **Status 2026-11-12: first pass done, without Blender.**
> `docs/brand/owl_3d.py` (standard library only) builds all four files and
> `owl-rig.json` into `docs/brand/out/owl-3d/`, which is git-ignored:
>
> ```sh
> cd docs/brand && python3 owl_3d.py --owl <aaru_owl_mascot.glb> \
>   --books <aaru_owl_on_books.glb> --out out/owl-3d
> ```
>
> | | Source | Now |
> |---|---|---|
> | Axis | Z-up | Y-up, facing +Z, 1 unit tall, on the origin |
> | Joints | none | 16: `Root, Owl, Feet, Body, Tail, WingL/R, Head, EarL/R, EyeL/R, PupilL/R, LidL/R` (+ `Books`) |
> | Normals | none | smooth, 45° crease |
> | Eyelids | none | `LidL`, `LidR`; shut by scaling Y and Z from 0.001 to 1 |
> | Triangles | 106,500 | 84,000 |
> | Draw calls | 118 | 60 |
> | Materials | flat | glossy clearcoat ceramic, brighter amber and cyan lights |
> | `owl.glb` | 808 KB | 1,117 KB (565 KB gzip); it grew because normals were added |
> | `Owl.usdz` | — | 1,123 KB; passes `usdchecker --arkit` |
>
> **Checked:** both USDZ files validate and render (`usdrecord`) with the
> parts in place, lids hidden when open and covering the eyes when shut. The
> GLB is structurally valid.
>
> **Not done yet, still open in this phase:**
> - The GLB has **not been loaded in three.js**, and the USDZ has not been
>   loaded in RealityKit. Do that first in Phases 2 and 3.
> - Size and draw calls miss the targets (≤ 400 KB, ≤ 40). Next step: real
>   mesh simplification, e.g. `gltf-transform simplify` + meshopt, once the
>   dependency check works.
> - The rest pose is still front-facing and symmetric. `owl-rig.json` carries
>   a `posterPose` (body and head turned) for the clients to apply; body
>   proportions are unchanged apart from a head 8% larger.
> - The shut lids read as large white domes. They may need to be smaller or
>   shaped as a lower-edge curve.
> - The book spines have no titles; the source has none.
>
> Steps 1–4, 6 and 7 below are done by the script; step 5 is partly done.

The original steps, for reference. The script does these without Blender; use
Blender only if the remaining work needs it. It must stay re-runnable: source
in, GLB and USDZ out.

1. **Import and fix the axis** so the owl is Y-up, standing on the origin,
   facing +Z, about 1 unit tall.
2. **Add normals.** Smooth shading with a sharp-edge angle (start at 35°), so
   ceramic plates look curved and panel seams stay crisp.
3. **Group the parts under pivots.** Empties placed at the real joints:

   | Pivot | Parts (by name prefix) | Moves |
   |---|---|---|
   | `Body` | torso, chest, belly, haunches, tail | breathe, lean |
   | `Head` (at the neck swivel) | head, crown, crest, ears, brows, beak, forehead inset, both eyes | turn, tilt, nod |
   | `EyeL`, `EyeR` | socket, bezel, rim, dome, pupil, iris, catchlights | look direction |
   | `PupilL`, `PupilR` | pupil, iris accent, catchlights | dilate, blink substitute |
   | `EarL`, `EarR` | ear parts | flick |
   | `WingL`, `WingR` (at the shoulder gimbal) | wing substrate, shoulder, flight feathers, tips, overlays, seam | lift, flutter |
   | `Books` (second file only) | all `BOOKS /`, `ANIME /`, `TV SHOWS /`, `MOVIES /` parts | static |

4. **Merge meshes** that share a material inside the same pivot. 118 separate
   meshes is 118 draw calls; aim for 40 or fewer.
5. **Reduce triangles** to about 30–40k for the owl, keeping the eyes and face
   at full detail.
6. **Decide the blink.** Either add two simple lid meshes per eye, or use the
   pupil-scale substitute. Lids look better; try them first.
7. **Export**
   - `owl.glb` and `owl-on-books.glb` for web (quantised; no Draco or meshopt
     at first, so no decoder is needed and Workers compresses the file in
     transit)
   - `Owl.usdz` and `OwlOnBooks.usdz` for Apple
8. **Verify** with the script's own report: triangle count, draw calls, file
   sizes, pivot names present, normals present, no missing materials.

**Do not bake animation clips into the files.** Blender's USD export writes
one timeline, and getting several named clips into RealityKit is fragile. The
motion lives in code instead (Phase 4), which also allows the owl to react to
the pointer.

**Gate 1: passed for the experiment.** The owner saw the prepared model on
2026-11-12 and said it looks much better. Carry on to the app spikes with
these assets. The remaining items above are improvements to make alongside,
not blockers; re-run the script and re-export whenever one lands, and keep the
joint names stable so the app code does not change.

## Phase 2: web spike (1–2 days)

- Copy `owl.glb` and `owl-on-books.glb` from `docs/brand/out/owl-3d/` to where
  decision 2 puts them, and load `owl.glb` with `GLTFLoader`. No Draco or
  meshopt decoder is needed. Look joints up with `getObjectByName`.
- Apply `posterPose` from `owl-rig.json` on load.
- Add `three` as a dependency. Import it **only** with a dynamic `import()`
  inside `onMount`, so it is its own chunk, never runs on the Worker during
  server rendering, and never loads for someone who doesn't see the owl.
- New component `aaru-client/src/components/Owl3D.tsx` with the same props the
  stills take: `pose`, `idle`, `class`, `decorative`. It must:
  - render the existing still first (`MascotMedallion`'s image), then swap to
    the canvas once the model has loaded and the first frame is drawn
  - keep the still permanently if WebGL is unavailable, the model fails to
    load, `prefers-reduced-motion: reduce` is set, or `saveData` is on
  - use a transparent canvas (`alpha: true`) so it works on the disc and off it
  - light the owl with three's built-in `RoomEnvironment` through
    `PMREMGenerator`. That needs no HDR file and gives the ceramic and metal
    something to reflect. Add one key light and one rim light in the amber
    and ice-blue token colours, read from the CSS variables, not literals.
  - cap the pixel ratio at 2, pause the render loop when off-screen
    (`IntersectionObserver`) and when the tab is hidden, and dispose the
    renderer on cleanup
  - never mount more than one canvas per page
- Mount it on a dev-only route first, then on `routes/sign-in.tsx` behind the
  flag.
- Run `npm run check && npm run lint && npm run typecheck && npm test`, then
  `npm run build && npm run size`.

**Measure and record:** chunk size (gzip), model size over the wire, time from
navigation to first 3D frame, frame rate on a mid-range phone and on a laptop,
and whether the sign-in page's first paint changed.

## Phase 3: Apple spike (1–2 days)

- New view `aaru-ios/Aaru/Design/Owl3DView.swift`, API matching `OwlMedallion`:
  `Owl3DView(pose:idle:size:)`.
- `RealityView` with a virtual camera (no AR), loading `Owl.usdz` from the
  bundle with the async `Entity` initialiser, then finding the joints with
  `findEntity(named:)`. The names are the same as on web. Confirm the first
  time that RealityKit keeps the hierarchy and names from the USDZ.
- Apply the same `posterPose`.
- Show the existing `Image(pose.image)` until the entity is ready, and keep it
  when `accessibilityReduceMotion` is on or Low Power Mode is enabled.
- Lighting: an image-based light plus one directional key light. Match the web
  result by eye.
- Build for iOS Simulator and for macOS with the commands in `CLAUDE.md`. Run
  the unit tests.

**Questions this spike must answer** (they are not known in advance):

1. Can a non-AR `RealityView` have a **transparent background** over SwiftUI
   content on iOS 18 and on macOS 15? If not, the owl must sit on an opaque
   backdrop (the `night` disc would do), which also settles decision 3.
2. Does the look match the web version closely enough with the same model and
   comparable lights?
3. Memory and energy cost of one `RealityView` on the Welcome screen,
   measured in Instruments.

Widgets and the Live Activity cannot host this. They keep stills.

## Phase 4: motion (2–3 days)

Write the motion **once, as data**, and play it with a small driver on each
platform, so web and Apple move identically.

- `design/owl-motion.json`: for each state, a list of tracks. A track is a
  joint name from `owl-rig.json` (`Body`, `Head`, `LidL`, `PupilL`, `EarL`,
  `WingL`, `Tail`…), a property (rotation X/Y/Z, scale, emissive strength), and
  keyframes with easing. Loops and one-shots are marked as such.
- States to build, matching `OwlPose`:

  | State | Kind | Motion |
  |---|---|---|
  | `standing` (idle) | loop | slow rise and fall on `Body` (translate, not scale, so the head and wings don't swell), small `Head` drift, blink with `LidL`/`LidR` every 4–7 s, faint amber pulse |
  | `curious` | loop | `Head` tilt 12–15°, one `EarL` flick, pupils widen (`PupilL`/`PupilR` scale) |
  | `sleeping` | loop | `Head` lowered, lids at scale 1, slower rise and fall, glow dimmed |
  | `celebrating` | one-shot | `WingL`/`WingR` lift and flutter twice, `Head` up, `Tail` fans, glow bright, back to idle |

- Changes between states blend over about 250 ms. A one-shot returns to the
  current loop.
- **Interactive layer, the reason to do 3D at all:** the head and pupils turn
  a few degrees toward the pointer on web and toward a touch on Apple, eased,
  clamped, and off under Reduce Motion.
- Drivers: `aaru-client/src/lib/owl-motion.ts` and
  `aaru-ios/Aaru/Design/OwlMotion.swift`. Unit-test the interpolation on both
  sides against the same fixture values.

## Phase 5: where it would make sense

Count of files that show the owl today: 29 on web, 24 in the Apple app. Most
of them should **not** become 3D. First assessment below; the audit confirms
or corrects each row.

### Candidates

| Verdict | Surface | Web | Apple | Why |
|---|---|---|---|---|
| **Yes** | Sign-in / Welcome | `src/routes/sign-in.tsx` | `Aaru/WelcomeView.swift` | One large owl, signed-out, nothing else competing. Today the web one is hidden on phones |
| **Yes** | Landing hero | `src/routes/index.tsx` | — | The owl on the book stack is the poster itself; use `owl-on-books` |
| **Yes** | First run's opening screen (§0a) | `src/routes/app_.welcome.tsx`, `components/onboarding/KindsStep.tsx` | `Onboarding/OnboardingParts.swift` | First impression; one instance |
| Maybe | Invite landing | `src/routes/i.$code.tsx` | `Social/InviteSheet.swift` | Signed-out and single, but a sheet is small on a phone |
| Maybe | Assistant card while it works | `components/assistant/AssistantCard.tsx` | assistant card | A reacting owl fits, but check the rendered size; under ~96 px it is not worth it |
| Maybe | Badge earned | `components/achievements/BadgeReveal.tsx` | `Achievements/UnlockToast.swift` | `celebrating` suits it; the toast is small and brief |
| Maybe | 404, route error, load failed | `components/RouteError.tsx` | `Design/LoadFailedView.swift` | `curious` suits it, but an error page should not depend on WebGL or a download |
| **No** | Screen-level empty states (library, lists, calendar, discover, insights, sports, groups, search…) | ~14 route and component files | ~14 views | Many instances, small, and often several per session. Keep stills |
| **No** | Agent mark and small heads | `OwlMark`, `OwlButton`, `AgentPresence`, `AppShell` | `OwlHead`, `AaruAvatar` | Too small; they already "breathe" |
| **No** | Recap cards and anything rendered to an image | `components/recap/RecapCards.tsx` | `Recap/RecapCards.swift` | Must be a still |
| **No** | Widgets, Live Activity, browser extension, OG image, app icon | — | `AaruWidgets/` | Cannot host 3D |

A useful by-product for every "No" row: once the model exists, **render the
four pose stills from it** (replacing or supplementing `owl_poses.py`), so the
stills and the 3D owl are the same character from the same source.

### Audit procedure

For each file that renders the owl (find them with a search for
`MascotMedallion`, `OwlEmpty`, `OwlMark`, `OwlButton`, `AgentPresence` on web
and `OwlMedallion`, `OwlUnavailableView`, `OwlHead` on Apple), record:

1. the rendered size in points at phone and desktop widths
2. how many owls can be on screen at once
3. whether the surface is signed-out or inside the app
4. whether it is ever rendered to an image or shown in a widget
5. what the owl is doing there (welcoming, waiting, celebrating, apologising)
6. whether `DESIGN.md` "Where the owl lives" already allows it

Rule of thumb for the verdict: 3D only where the owl is **at least ~160 pt,
alone on screen, and the moment benefits from it reacting**. Write the result
as a table in `docs/audit/` next to the existing audits.

## Phase 6: evaluate and decide

Put the 3D owl, the current still, and (if the Higgsfield pilot has run) the
video clip side by side on the sign-in screen, on web and on a phone.

**Go** only if all of these hold:

| Criterion | Target |
|---|---|
| Recognisably the poster's owl | Owner's judgement on the side-by-side |
| Web JS added, lazy | ≤ 170 KB gzip, and zero added to any route's first load |
| Model over the wire | ≤ 400 KB |
| First 3D frame after navigation | ≤ 1.5 s on a mid-range phone on 4G; the still shows until then |
| Frame rate | 60 fps on a recent phone, never under 30 fps on a mid-range one |
| Sign-in first paint | unchanged (the still is the first paint) |
| Fallbacks | still shown with Reduce Motion, no WebGL, load failure, Low Power Mode |
| Apple | transparent or disc-backed rendering works on iOS 18 and macOS 15, and looks like the web one |
| Checks | `npm run size`, lint, typecheck, tests, `ci-brand.yml`, Apple build and tests all pass |

**If it is a go:** update `DESIGN.md` (brand rule and "Where the owl lives"),
then ship the "Yes" rows to the beta channel first.

**If it is a no-go:** record why in the backlog entry. The prepared model is
still worth keeping for rendering pose stills and as the start frame source
for Higgsfield clips.

## Risks

| Risk | What to do |
|---|---|
| The model does not look like the poster | Gate 1 catches it before any app code. Fix with lighting and pose first; ask for a better source model if the shape is the problem |
| No blink without eyelids | Add lid meshes in Phase 1; pupil-scale fallback |
| three.js breaks the size budget | Lazy chunk only; re-seed `totalJs` with a stated reason if lazy chunks count |
| Server rendering imports three on the Worker | Dynamic import inside `onMount` only; verify with `npm run build` and a signed-out page load |
| RealityView cannot be transparent | Use the `night` disc as an opaque backdrop |
| Web and Apple look different | Same model, same motion data; tune lights side by side; accept small differences |
| Emissive parts don't glow without bloom | Keep the existing soft glow behind the owl (`.owl-idle::before`, `OwlGlow`) instead of adding a post-processing pass |
| Battery and heat on phones | One instance, paused off-screen, still under Low Power Mode |
| Two renderers to maintain | The motion data and pivot names are shared; only the two small drivers differ |

## Out of scope

- Any other app's mascot.
- AR, visionOS, or placing the owl in the room.
- Replacing the small owl marks or the empty-state stills with 3D.
- Server changes. This is client-only.

## Deliverables

1. `docs/brand/owl_3d.py` (written) and the four model files plus
   `owl-rig.json` (built; final location per decision 2), slimmed to the size
   and draw-call targets.
2. `Owl3D.tsx`, `owl-motion.ts`, and the flagged sign-in integration on web.
3. `Owl3DView.swift`, `OwlMotion.swift`, and the flagged Welcome integration
   on Apple.
4. `design/owl-motion.json`.
5. The placement audit table in `docs/audit/`.
6. A short results note with the measurements, the side-by-side captures, and
   a go or no-go recommendation.
