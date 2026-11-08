# Independently quality-check marketing video deliverables

Act as a meticulous video QA reviewer. Read `marketing/prompts/00-video-production-rules.md`, `marketing/strategy.md`, `marketing/features.md`, `marketing/rules/video-playbook.md`, the relevant scripts/storyboards, approved claims, and the actual rendered video files available in the workspace.

For each video that **actually exists**, inspect its visible content and audio by available tools, and evaluate:
1. Product accuracy: no fabricated features, workflows, screens, pricing, or customer results.
2. UI fidelity: text is readable and actual interactions match the source app.
3. Timing: shot duration, speech pace, caption synchronization, complete video runtime.
4. Format: expected aspect ratio/resolution, no accidental letterboxing/cropping, safe caption/CTA placement.
5. Branding: name, logo, typography, colors, tone, CTA and platform availability.
6. Sound: understandable voice, balanced music, no clipping, permitted source material.
7. Safety/trust: no personal data, credentials, deceptive AI-presenter testimonial, or unlicensed content.
8. Export integrity: verify the file is nonempty, playable, and its path is correct.

Create a per-video `qa-report.md` with PASS / NEEDS FIX / NOT CHECKABLE for each category, concrete timestamps for issues when possible, and a prioritized corrections list. Distinguish missing source material from rendering problems. Do not claim to have visually watched a file if the available tools only expose metadata. Fix simple edit issues only when safe and authorized; **do not trigger paid regeneration without approval**. Do not publish.
