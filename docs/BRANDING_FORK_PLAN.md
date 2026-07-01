# Custom-Branded Chatwoot Build — Plan (not yet implemented)

Status: **planning only**. Nothing in this doc has been built. No CI, no custom
image, no registry, no code changes to `vendor/chatwoot/` exist yet. This is
the reference to work from once Christian greenlights implementation.

## Why

Studio Zerotredici wants its own visual identity (logo, colors, typography)
applied to the Chatwoot agent dashboard, not just the customer-facing widget,
as a differentiator for the 15-person team. Confirmed this is compatible with
Chatwoot's license (see below) and worth doing as a maintainable overlay
rather than a deep fork (see Architecture below) specifically so upgrades
stay tractable — including Christian's idea of eventually automating the
upgrade-and-reapply cycle with an agent.

## License basis (verified against the actual source, not assumed)

Read directly from `vendor/chatwoot/LICENSE` and `vendor/chatwoot/enterprise/LICENSE`:

- Everything **outside** `enterprise/` is MIT ("Chatwoot Expat" license) — free to use, modify, and redistribute derivatives.
- Everything **inside** `enterprise/` requires a paid Chatwoot Enterprise subscription for production use. We don't touch this directory at all — see Build Recipe below, which strips it entirely, matching Chatwoot's own official build process.
- Chatwoot's [FAQ](https://developers.chatwoot.com/self-hosted/faq#how-can-i-customise-the-chatwoot-branding-) explicitly encourages "enhancing Community Edition software to cater to specific business niches." Their own words for what they *discourage*: "clones of Chatwoot Cloud (SaaS), Rebranding Services" — i.e., reselling a white-labeled Chatwoot-as-a-service to other companies. That's not this use case (internal helpdesk, own team, own clients seeing our own brand) — we're squarely inside the encouraged use.

**Conclusion: legally and by Chatwoot's own stated norms, this is fine.** No ambiguity requiring legal sign-off beyond this.

## Architecture: overlay, not a permanent fork

Do **not** hand-edit files throughout the 8,278-file vendored tree. Instead:

1. Keep `vendor/chatwoot/` as an unmodified, re-clonable reference at a pinned tag (current: `v4.15.1`). Treat it as disposable/regenerable, not something we hand-maintain.
2. Maintain a small, separate `branding/` directory in this repo containing only:
   - Replacement logo/favicon assets (from `studio_zerotredici/corporate_identity/Logo/`)
   - A color/SCSS token override file
   - The one or two files that hold the app display name / "Powered by Chatwoot" string
3. A build script/Dockerfile step copies `branding/` files over the equivalent paths in a fresh `vendor/chatwoot/` checkout, then builds — never a permanent hand-edited fork.
4. **This is what makes future automation realistic.** A dozen overlaid files is a diff an agent (or Christian) can mechanically reapply against any new upstream tag. Editing Chatwoot's own components throughout the tree would turn every upgrade into a manual merge — avoid that.

### Research complete — see `docs/chatwoot-knowledge/branding-injection-points.md`

Done 2026-07-01, code-grounded (every claim cites `vendor/chatwoot/path:LINE`), full
detail in that doc. **Key finding that changes this plan's scope:** Chatwoot CE
already ships a native, database-backed white-labeling system for the highest-value
items — no code overlay needed for these at all:

- **Installation name, logo (light/dark), "Powered by" attribution** — all driven by
  the `installation_configs` table (seeded from `config/installation_config.yml`),
  exposed to the frontend via `window.globalConfig`. Changing the DB row is enough;
  `Branding.vue`'s `replaceInstallationName()` even rewrites the "Powered by
  Chatwoot" string automatically once `INSTALLATION_NAME` changes.
- **Catch:** these specific keys default `locked: true` in the YAML (no
  `locked: false` declared), so they're **not** exposed in the Super Admin UI or via
  Dokploy env vars — need a one-time `rails runner`/seed script against
  `installation_configs` after first deploy, not a `branding/` overlay file.

**What genuinely still needs a build-time overlay** (per the architecture below):
- The primary brand **color** — SCSS custom properties in
  `app/javascript/dashboard/assets/scss/_next-colors.scss` (compiled at build time,
  can't be changed via DB/env).
- **Favicon + `public/manifest.json`** — fully static, not templated at all; the
  manifest hardcodes `"Chatwoot"` as plain JSON.
- Login-screen logo usage was **not conclusively confirmed** (no dedicated
  login-specific component found) — verify visually against a running instance
  before assuming the sidebar/dashboard logo override covers it too.

This means the actual `branding/` overlay is much smaller than originally scoped —
essentially just the color SCSS file + favicon/manifest — plus one one-time DB seed
script for name/logo/attribution, not a set of hand-edited Vue components.

## Verified build recipe (reproduced from Chatwoot's own CI, not invented)

Source: `vendor/chatwoot/.github/workflows/publish_foss_docker.yml` — this is
literally the script Chatwoot's own team uses to produce the `-ce` Docker Hub
tags we're already running. Our custom build should mirror it exactly, plus
our overlay step:

```bash
# 1. Start from a fresh checkout at the pinned tag (not the possibly-stale vendor/ copy)
git clone --depth 1 --branch v4.15.1 https://github.com/chatwoot/chatwoot.git build-src
cd build-src

# 2. Strip enterprise code (matches upstream's own -ce recipe exactly)
rm -rf enterprise spec/enterprise

# 3. Apply our branding overlay on top (paths TBD — see research section above)
cp -r ../branding/* .

# 4. Mark the edition, same as upstream does
echo 'ENV CW_EDITION="ce"' >> docker/Dockerfile

# 5. Build with Chatwoot's own unmodified Dockerfile
docker build -f docker/Dockerfile -t ghcr.io/studio-zerotredici/chatwoot-013:v4.15.1-ce-013 .
```

## Open decisions before implementation starts

- **Registry**: GHCR under a Studio Zerotredici org/PAT — needs to exist and have a token available to CI. Private, presumably (internal branding assets + a build that's specific to us, no reason to make it public).
- **CI location**: this repo already has `.github/` and `.husky/` scaffolding left over from its previous life as the custom Next.js app — repurpose that, or start clean? Either works; repurposing saves nothing meaningful, so default to starting clean unless there's a reason to keep the old scaffolding.
- **Tag scheme**: something like `v4.15.1-ce-013` (upstream version + our marker) so it's obvious at a glance which upstream release an image is built from.
- **Upgrade cadence & smoke test**: who verifies a rebuilt image before it replaces production in `docker-compose.yml`? Propose: rebuild on a schedule or on-demand, deploy to a staging Dokploy service first, manual go/no-go before repointing production.
- **"Smart agent" upgrade automation**: realistic once the overlay is small and proven manually a few times first. Don't automate an unproven process — do it by hand/checklist for the first 2-3 upstream upgrades, then consider having an agent run the mechanical steps (clone, strip, overlay, build, tag, push) with a human still gating the production cutover.

## Next step

Once Christian confirms scope, the actual next actions are (in order):

1. ~~Locate the exact branding injection points~~ — done, see
   `docs/chatwoot-knowledge/branding-injection-points.md`.
2. Write the one-time DB seed script (`rails runner`) for `INSTALLATION_NAME` /
   `LOGO` / `LOGO_DARK` / `LOGO_THUMBNAIL` / `BRAND_NAME` / `BRAND_URL`, and verify
   the login-screen logo question visually against a running instance.
3. Create the (now much smaller) `branding/` overlay directory: just the SCSS color
   token file + favicon/manifest.json, populated with Studio Zerotredici assets from
   `studio_zerotredici/corporate_identity/`.
4. Set up GHCR access and a build script (or GitHub Action) implementing the recipe
   above.
5. Build once manually, verify visually, before wiring up any automation.
6. Update `docker-compose.yml` to point at the custom image tag, deploy to staging
   first.

None of this has started. This document is the plan only.
