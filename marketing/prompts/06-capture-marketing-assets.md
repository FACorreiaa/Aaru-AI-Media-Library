# Capture app screenshots and recordings for marketing

Act as a QA automation specialist and product video capture operator. Read `marketing/prompts/00-video-production-rules.md`, `marketing/features.md`, all relevant READMEs, the video shot lists, and `marketing/assets/manifest.md` if present.

## Goal
Produce a reusable **library of accurate product screenshots and short recordings** from this repo's web app and its iPhone, iPad and Mac app. Do not use real customer data.

## Workflow
1. Audit existing assets and the shot lists from `marketing/videos/` to prevent duplicate captures.
2. Determine whether a local/staging **demo environment** can run safely (`marketing/rules/video-playbook.md`, "Capture environments": local Postgres + `go run ./cmd/aaru`, `npm run dev` in `aaru-client`, the iOS Simulator, `scripts/store-screenshots.sh`). Sign in only to the demo account (`aaru --seed-review`) or a fresh local one. Never film the owner's library or a real person. Never expose sign-in codes, tokens or keys, and do not connect to production without explicit approval.
3. For web: if browser automation/Playwright is configured, capture clean screenshots at relevant desktop and mobile viewport sizes; capture individual user flows with slow, readable cursor actions and pauses. If automation isn't configured, explain what is missing rather than installing arbitrary tooling without permission.
4. For iOS: if a simulator or suitable device automation is available, capture screen recordings and key screens. If not, give me a recording checklist that names the exact app screens, gestures, and desired durations.
5. Capture the actual product flows needed for the full app showcase, AI presenter ad, three feature videos, and teaser. Include a neutral dashboard/home screen and branding screens.
6. Keep source footage unaltered; create separate edited copies if needed. Remove or replace any accidental sensitive information.
7. Create/update `marketing/assets/manifest.md` with file path/URL, type, platform, resolution, orientation, target feature/video, date, app revision if known, capture method, and review status.
8. Store large video files outside ordinary Git tracking or use existing approved media storage/LFS.

## Deliverable
Capture everything feasible **without modifying app code or production data**. Then report completed captures, missing footage, blockers, and the exact manual instructions for any outstanding iOS/web assets. Do not use Higgsfield or incur generation charges during this task.
