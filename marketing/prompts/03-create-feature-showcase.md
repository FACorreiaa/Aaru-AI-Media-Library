# Produce one individual feature showcase

**Feature to showcase:** [ENTER EXACT FEATURE NAME OR ASK CLAUDE TO SELECT THE NEXT HIGHEST-PRIORITY VERIFIED FEATURE]

Act as a product demonstration director, UI motion designer, and SaaS marketing copywriter. Read `marketing/prompts/00-video-production-rules.md`, `marketing/strategy.md`, `marketing/features.md`, `marketing/rules/video-playbook.md` (if present), and approved videos/footage. Confirm the chosen feature is implemented and identify the exact platform(s): web, iPhone/iPad, Mac, or all, and which kinds (films, shows, anime, manga, books, albums) it applies to.

## Goal
Create **one independent 20–30 second feature showcase video**, optimized for 9:16 social media, with an optional 16:9 version. The actual feature must be visible working in real recorded footage.

## Storyboard
- **0–3s — Hook:** State the problem or relevant outcome.
- **3–7s — Context:** Show where the feature lives in the app.
- **7–21s — Real demo:** 2–4 essential clicks/taps, with restrained zooms, cursor/touch emphasis, readable UI, and brief animated callouts.
- **21–26s — Benefit:** Explain the user value in plain language.
- **26–30s — CTA:** Approved brand and action.

Adjust timings to match the real workflow; do not speed footage until text becomes unreadable. No fabricated buttons, transactions, data, screenshots, or unsupported promises. Reuse Video 1's fonts, color, transitions, sound treatment, and branding.

## Execute
1. Validate implementation with code or existing demo recordings, document the verified workflow, and note any gaps.
2. Find or capture the exact source demonstration. Use demo data only; do not require production access.
3. Create `marketing/videos/feature-<short-slug>/brief.md`, `script.md`, `storyboard.md`, `shot-list.md`, `generation-plan.md`, and `social-post.md`.
4. Prefer UI compositing over AI recreation; use Higgsfield only for supporting cinematic elements if helpful.
5. Present the credits/cost and generation plan, then **wait for approval before any paid generation**.
6. After approval, render the final MP4 where tool support exists. Make a platform-appropriate alternate format if feasible; do a visual/audio QA pass and record export status in the manifest.
7. Provide a social caption with one compelling benefit and a single CTA. Do not publish.

If the requested feature is not currently available, explain the mismatch and propose a verified alternative without inventing functionality.
