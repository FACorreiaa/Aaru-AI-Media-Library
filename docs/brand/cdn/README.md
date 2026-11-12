# cdn.aaruapp.com

Aaru's own address for brand media that is too heavy for git. Today it holds one file: the 3D
owl's model for the web (BRD-011), which the staging Worker's `OWL_3D_MODEL_URL` points at.

It is a Cloudflare Worker with static assets and no code (`wrangler.jsonc` here). A single small file does not
need a bucket. `R2.md` says when that changes and how to move without changing an address.

## Rules

- **A new cut is a new path.** `/aaru/owl3d/v1/owl.glb` is cached for a year as immutable, so it
  is never overwritten: the next model goes to `v2`, and the Worker var changes with it.
- **Every deploy replaces the whole set.** A file missing from `out/cdn` disappears from the
  address, so keep the earlier versions in the folder while anything still points at them.
- Nothing personal and nothing secret goes here. Every file is public and readable from any site.

## Deploy

```sh
# 1. Build the model (see docs/superpowers/plans/2026-11-12-owl-3d-experiment.md, Phase 1).
# 2. Lay the files out as they are served:
mkdir -p docs/brand/out/cdn/aaru/owl3d/v1
cp docs/brand/out/owl-3d/owl.glb docs/brand/out/cdn/aaru/owl3d/v1/
cat > docs/brand/out/cdn/_headers <<'HEADERS'
/aaru/*
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=31536000, immutable
  X-Content-Type-Options: nosniff
HEADERS
# 3. Deploy with the aaruapp.com token (Workers Scripts, Workers Routes and DNS edit):
cd aaru-client && CLOUDFLARE_API_TOKEN=… npx wrangler deploy --config ../docs/brand/cdn/wrangler.jsonc
```
