# zerotredici-helpdesk-website — Claude Code Handoff

## What this repo is now

This repo used to hold a custom Next.js helpdesk app (forked from `gudlab/guddesk-core`, upstream remote still attached). Commit `6b4fb65` ("refactor to chatwoot", 2026-07-01) deleted the entire prior app — everything except `.github/FUNDING.yml` and the `.husky` git hooks. Studio Zerotredici decided to stop maintaining a custom helpdesk app and instead self-host **Chatwoot** for `helpdesk.zerotredici.app`, deployed via Dokploy on our own VPS.

This repo's new job: be the source of truth for that Chatwoot deployment — the Docker Compose file Dokploy pulls from, plus the operational docs for running it.

## Current state (as of this handoff)

- `docker-compose.yml` — a working first draft: 4 services (`rails`, `sidekiq`, `postgres` with `pgvector`, `redis`), pinned to `chatwoot/chatwoot:v4.15.1-ce`, bind-mounting persistent data on the VPS at `/var/www/studio_zerotredici/helpdesk.zerotredici.app/data/{storage,postgres,redis}`.
- `docs/DEPLOYMENT_GUIDE.md` — full rationale, deployment steps, MFA rollout (Phase 2), WhatsApp/Telegram integration walkthroughs, backup posture, security notes. Read this before touching the compose file — it explains *why* things are the way they are (e.g. why `-ce` not `latest`, why bind mounts not named volumes, why Redis is password-protected when upstream's own template isn't).
- `docs/DOKPLOY_ENVIRONMENT.md` — the copy-paste list of variables that go in Dokploy's Environment tab. This is the only place variable *names* should be documented; never put real secret values in this repo.
- `vendor/chatwoot/` — a plain (no `.git`) reference checkout of upstream `chatwoot/chatwoot` at tag `v4.15.1`, ~146 MB / 8,278 files. Not a submodule, not built from, not deployed from — it's there for code reference and for locating the branding injection points described in `docs/BRANDING_FORK_PLAN.md`. Treat it as disposable/regenerable, not something to hand-edit in place.
- `docs/BRANDING_FORK_PLAN.md` — **planning only, nothing built yet.** Covers the license basis (verified: MIT outside `enterprise/`, fine for this use case), the "overlay not fork" architecture, and Chatwoot's own official CE build recipe (reproduced from their `publish_foss_docker.yml`, not invented). Read this in full before starting any custom-image work — it also lists what still needs research (exact files for logo/name/color overrides) before implementation can start.
- `docs/INTEGRATIONS_ROADMAP.md` — **planning only, nothing built yet.** Covers the broader feature wishlist beyond branding: a `gbrain` knowledge-graph pass over `vendor/chatwoot/`, MCP/AI integration (two directions, graded by maturity), Freshdesk data import (open question: one-time migration vs. ongoing bridge), the `supporto@zerotredici.com` email channel, per-agent signatures, Teams (future org structure), and GitHub issue/PR visibility for a WEB team. Summary table at the bottom shows what's native Chatwoot config vs. what needs custom work.
- Nothing has been deployed yet. This is pre-first-deploy.

## Conventions to follow

- **Persistent data path convention**: `/var/www/{company}/{domain}/data/*` on the Dokploy VPS, bind-mounted (not named Docker volumes). Same pattern used for Termix at `shell.zerotredici.com`. Keep this consistent if the compose file changes.
- **Dokploy Environment tab rule**: a variable only reaches a container if it's declared in that service's `environment:` block in the compose file. If you add a new env var, wire it into `docker-compose.yml` *and* document it in `docs/DOKPLOY_ENVIRONMENT.md`, in the same change.
- **No manual Traefik labels or network declarations** — Dokploy injects those from its Domains UI once you point a domain at a service/port.
- **Never commit secrets.** `docker-compose.yml` and `docs/DOKPLOY_ENVIRONMENT.md` should only ever contain variable names and non-secret defaults (`FRONTEND_URL`, `DEFAULT_LOCALE`, etc.). Real values live in Dokploy's Environment tab and the team vault only.
- **Pin image versions.** Don't switch `chatwoot/chatwoot:v4.15.1-ce` to `latest`. When upgrading, check the [releases page](https://github.com/chatwoot/chatwoot/releases) and changelog, upgrade iteratively if jumping multiple versions, and re-run through the validation checklist in `docs/DEPLOYMENT_GUIDE.md`.

## Open items for the next session

1. **Custom-branded image**: decided in principle (license is clear, recipe is known — see `docs/BRANDING_FORK_PLAN.md`), but implementation hasn't started. Next actual step is research: locate the exact files in `vendor/chatwoot/app/javascript/` that render the logo, app name, and color tokens, before writing any overlay files. Confirm with Christian before setting up GHCR/CI — the plan doc lists the open decisions (registry, tag scheme, upgrade cadence).
2. **Wire this repo into Dokploy as a Git-based Compose source** (Project → Service → Docker Compose → point at this repo/branch) rather than pasting the compose manually into the Dokploy UI — that way this repo stays the single source of truth.
3. **First deploy**: fill in real values for the Dokploy Environment tab per `docs/DOKPLOY_ENVIRONMENT.md`, deploy, run through the Operational Validation Checklist in `docs/DEPLOYMENT_GUIDE.md`.
4. **Phase 2 (MFA)**: only after step 3 is verified — see `docs/DEPLOYMENT_GUIDE.md#phase-2-enable-mfa-after-bootstrap`.
5. **WhatsApp / Telegram**: no code changes needed — done entirely in the Chatwoot admin UI post-deploy, walkthroughs are in `docs/DEPLOYMENT_GUIDE.md`.
6. **GitHub integration**: Chatwoot doesn't ship one yet (Meta says Q4 2026 on their public roadmap as of 2026-07-01). If/when Studio Zerotredici wants the n8n-based bridge workaround described in `docs/DEPLOYMENT_GUIDE.md`, that's a separate n8n workflow, not a change to this repo's compose file — flag if that scope creeps in here.

## Branches

- `main` — mirrors upstream `gudlab/guddesk-core` history.
- `deploy_prod` (current branch, where the Chatwoot refactor landed) — this is the deployment-focused branch going forward.
- `develop`, `feature/docker-container` — pre-refactor branches from the old app; likely stale, confirm with Christian before touching.
