# Deploying GudDesk on Dokploy

This is the concrete, Studio Zerotredici-specific companion to
[`content/docs/self-hosting.mdx`](./content/docs/self-hosting.mdx) and
[`.claude/context/deployment.md`](./.claude/context/deployment.md). It covers
exactly what's needed to get **this fork** fully working on our own Dokploy
instance — including login and email, which don't work out of the box until
the steps below are done.

Scope: this repo is **GudDesk only**. It does not call or depend on GudCal,
GudForm, or GudAgent anywhere in the codebase — it's a fully standalone
Next.js + Postgres app, and its database is not shared with those other
Gud* products. Those three are separate GudLab products/repos; the only real
integration direction is GudAgent *calling into* GudDesk's REST API later,
not the reverse. Nothing below requires them.

## Two-phase plan

**Phase 1 (this section): get it running with default/hosted features.**
Bundled Postgres (one stack, no extra Dokploy resource), Pusher Cloud for
real-time (zero extra infra), Resend for email. Goal: a fully working
GudDesk — login, chat, email — with the least amount of infrastructure to
stand up first.

**Phase 2 (further down): personalize.** Once phase 1 is confirmed working,
swap Pusher Cloud for self-hosted Soketi (EU data residency) — a pure env
var change, no redeploy of code. Optionally externalize Postgres to a
managed Dokploy resource later if you want independent backup/scaling from
the app container.

## Why login/email don't "just work" yet

Two things needed fixing in this fork before go-live, both now done in code
(see git log):

1. **Migrations weren't run automatically.** The Dockerfile now uses
   `entrypoint.sh`, which runs `prisma migrate deploy` on every container
   start before starting the server — idempotent, safe to run on every boot.
2. **Email sender addresses were placeholders.** `auth.config.ts` (magic
   link), `actions/forgot-password.ts`, `actions/invite-workspace-member.ts`,
   and `lib/email-notifications.ts` all hardcoded either Resend's sandbox
   address `onboarding@resend.dev` (which Resend restricts to only deliver
   to your own Resend account email, not real users) or a `guddesk.com`
   domain we don't own. They now read `EMAIL_FROM` / `EMAIL_REPLY_TO_DOMAIN`
   with a dev-only fallback — **these must be set to a domain verified in
   our Resend account before go-live** (step 3 below).

Good news already in the fork: Google OAuth is not the only login method —
`auth.config.ts` has Credentials (email+password, bcrypt) and Resend magic
link alongside it, so login isn't blocked on setting up Google OAuth at all.

---

# Phase 1 — get it running

## Step 1 — Deploy as a Dokploy Compose app (bundled Postgres)

`docker-compose.yml` bundles Postgres alongside the app as one stack — no
separate Dokploy-managed Postgres resource needed for this phase:

1. In Dokploy: create a new application pointed at this repo
   (`Studio-Zerotredici/zerotredici-helpdesk-website`), deploy type
   **Compose** (not Application/Dockerfile-only, and not Nixpacks — see the
   013 report for why Dockerfile-based builds: deterministic, pinned builds
   with the widget/Contentlayer build chain baked into the image).
2. Dokploy builds the `app` service from the repo's own `Dockerfile` (via
   `build: .` in `docker-compose.yml`) and starts the bundled `postgres`
   service alongside it, on an internal network — Postgres is never
   exposed on a host port.
3. Assign a domain to the `app` service, port `3000`, enable TLS (same
   domain-per-service pattern used for Soketi in step 2 of phase 2 below).
4. **Caveat learned from a prior Dokploy Compose deployment (Termix):**
   values set in Dokploy's Environment tab only reach the container if the
   compose file's `environment:` block actually references them (as
   `${VAR}` interpolation) — a plain `env_file:` pointing at a
   Dokploy-generated `.env` should work, but if a var isn't showing up
   inside the container, check it's referenced explicitly rather than
   assuming implicit passthrough.

## Step 2 — Environment variables (phase 1 minimum)

Copy `.env.example` as your starting point and fill in real values as
Dokploy **secrets** (not committed anywhere). Minimum for a working
login+email+chat deploy in this phase:

| Variable | Required for | Notes |
|---|---|---|
| `NEXT_PUBLIC_APP_URL` | everything | `https://desk.yourdomain.com`, no trailing slash |
| `AUTH_SECRET` | sessions | `openssl rand -base64 32` — set explicitly, don't autogenerate |
| `AUTH_TRUST_HOST` | reverse proxy | `true` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | bundled Postgres | `docker-compose.yml` computes `DATABASE_URL` from these — set a real password, never the default |
| `RESEND_API_KEY` | magic link / reset / invites | from resend.com |
| `EMAIL_FROM` | magic link / reset / invites | e.g. `GudDesk <support@yourdomain.com>` — domain must be verified in Resend (step 3) |
| `EMAIL_REPLY_TO_DOMAIN` | reply-by-email | optional, e.g. `mail.yourdomain.com`, needs Resend inbound routing |
| `PUSHER_APP_ID` / `PUSHER_SECRET` / `NEXT_PUBLIC_PUSHER_KEY` / `NEXT_PUBLIC_PUSHER_CLUSTER` | real-time (Pusher Cloud) | create a free app at pusher.com |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google login | optional, step 5 |
| `ANTHROPIC_API_KEY` | AI features | optional — leave unset if sending conversation content to a US provider isn't acceptable |

Email+password login (Credentials provider) works with just `AUTH_SECRET`
and the bundled Postgres — no Resend/Pusher/Google needed for that path
alone, but Resend is needed for the rest of the golden path (invites,
password reset).

## Step 3 — Verify the Resend sending domain

1. resend.com → Domains → Add Domain → add the SPF/DKIM/DMARC records it
   gives you to our DNS (Cloudflare) via the `cloudflare-dns` skill.
2. Wait for verification (usually minutes, can take longer for DNS
   propagation).
3. Use an address on that domain for `EMAIL_FROM`, e.g.
   `GudDesk <support@yourdomain.com>`.
4. Reply-by-email (`EMAIL_REPLY_TO_DOMAIN`) is optional — only set it up if
   we want agents to be able to reply to visitors from their email client;
   it needs Resend's inbound-email routing pointed at
   `POST https://desk.yourdomain.com/api/email/inbound`.

## Step 4 — Pusher Cloud (real-time)

1. pusher.com → create a free app (EU cluster region for data residency,
   e.g. `eu`).
2. Copy `app_id` / `key` / `secret` / `cluster` into `PUSHER_APP_ID` /
   `NEXT_PUBLIC_PUSHER_KEY` / `PUSHER_SECRET` / `NEXT_PUBLIC_PUSHER_CLUSTER`.
3. Leave `PUSHER_HOST` / `NEXT_PUBLIC_PUSHER_HOST` unset — that's what
   selects Pusher Cloud over self-hosted Soketi (see phase 2).

If skipped entirely, GudDesk still works — the widget/inbox fall back to
4-second polling instead of real-time.

## Step 5 — Google OAuth (optional)

1. console.cloud.google.com → APIs & Services → Credentials → Create OAuth
   client ID (Web application).
2. Authorized redirect URI: `https://desk.yourdomain.com/api/auth/callback/google`.
3. Set `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`.

Skip this entirely if email+password is enough for our agents — nothing
else depends on it.

## Step 6 — First deploy

Build and deploy the GudDesk stack in Dokploy. On container start,
`entrypoint.sh` runs `prisma migrate deploy` (applies `prisma/migrations/`)
before starting the server — first boot creates the schema automatically,
no manual `pnpm prisma db push` needed. The Prisma CLI used for this is
installed into an isolated `/opt/prisma-cli` directory in the Dockerfile's
runner stage (not copied from the builder stage) — pnpm's non-hoisted
`node_modules` keeps the CLI's own private dependencies
(`@prisma/engines`, `@prisma/config`, ...) as symlinks into
`node_modules/.pnpm`, which a plain `COPY` leaves dangling once separated
from that store; a scoped `pnpm add` in its own directory resolves them
correctly. Verified end-to-end against a real Postgres container — this
part of the Dockerfile is no longer a guess.

## Step 7 — Verification checklist

- [ ] `https://desk.yourdomain.com` loads, register/login pages render
- [ ] Create the first account via email+password (Credentials) — this
      should work even before Google OAuth is configured
- [ ] Set up a workspace, get the widget snippet, embed it on a test page
- [ ] Send a message from the widget, confirm it appears in the inbox
      (real-time via Pusher Cloud, or within ~4s via polling if skipped)
- [ ] Trigger "forgot password" — confirm the email arrives (proves
      `EMAIL_FROM` + Resend domain verification worked)
- [ ] Invite a teammate to the workspace — confirm the invite email arrives
- [ ] If Google OAuth configured: log in with Google

Once this checklist passes, phase 1 is done — move to phase 2 whenever
personalization is worth the extra infra.

---

# Phase 2 — personalize

## Self-hosted Soketi (replace Pusher Cloud)

We can self-host real-time chat instead of using Pusher Cloud, per the
013 self-hosting review (EU data residency). Dokploy ships Soketi as a
**built-in template** — use that instead of a hand-rolled compose file:

1. In Dokploy: **Create Service → Templates**, search "Soketi", or go to
   the project → **Create Service → Compose → Advanced → Base64 import**
   and paste the blob from
   [docs.dokploy.com/docs/templates/soketi](https://docs.dokploy.com/docs/templates/soketi).
   The template's compose is:
   ```yaml
   services:
     soketi:
       image: quay.io/soketi/soketi:1.6.1-16-debian
       environment:
         SOKETI_DEBUG: "1"
         SOKETI_HOST: "0.0.0.0"
         SOKETI_PORT: "6001"
         SOKETI_METRICS_SERVER_PORT: "9601"
       restart: unless-stopped
   ```
2. The template doesn't set app credentials, so Soketi falls back to its
   public default demo app (`app-id` / `app-key` / `app-secret`) — **add**
   `SOKETI_DEFAULT_APP_ID`, `SOKETI_DEFAULT_APP_KEY`,
   `SOKETI_DEFAULT_APP_SECRET` as extra env vars on the imported service
   with real random values (e.g. `openssl rand -hex 16` for key/secret).
   Write these down — GudDesk needs the exact same three values.
3. The template exposes two domains (`serviceName: soketi`): port `6001`
   (the websocket endpoint, e.g. `ws.yourdomain.com`) and port `9601`
   (Prometheus metrics — keep this one internal/off, or protect it,
   don't publish it alongside the main domain). Enable TLS on the
   websocket domain. WebSocket upgrade requests are plain HTTP requests
   with an `Upgrade` header — Traefik proxies them transparently, no
   special config needed.
4. Deploy. Confirm `https://ws.yourdomain.com` responds.
5. Set `PUSHER_HOST` / `NEXT_PUBLIC_PUSHER_HOST` (+ `PUSHER_PORT` /
   `NEXT_PUBLIC_PUSHER_PORT` / `PUSHER_USE_TLS` /
   `NEXT_PUBLIC_PUSHER_FORCE_TLS`) to point at Soketi, matching
   `PUSHER_APP_ID` / `NEXT_PUBLIC_PUSHER_KEY` / `PUSHER_SECRET` to the
   `SOKETI_DEFAULT_*` values from step 2. This is a pure env var change —
   restart the app, no rebuild needed. See `.env.example` for the exact
   variable block.

## Externalizing Postgres (optional)

Phase 1's bundled Postgres is fine indefinitely for a single-app deploy.
If we later want independent backup/scaling/restart from the app
container (e.g. multiple apps sharing one DB host, or Dokploy's managed
Postgres UI for point-in-time restore), move to a separate managed
Postgres resource instead: create it in Dokploy, set `DATABASE_URL`
directly in `.env` to its internal connection string, and remove the
`postgres` service (and the `POSTGRES_*` vars) from `docker-compose.yml` —
or switch the app back to a plain Dockerfile "Application" deploy type
instead of Compose.

## Rollback

Dockerfile-based deploys are pinned per commit/tag (per the 013 report's
recommendation over Nixpacks) — rollback is redeploying a previous image
tag in Dokploy, not a source rebuild. Migrations are additive
(`prisma migrate deploy` never rolls back schema automatically) — if a
rollback needs a schema rollback too, that's a manual `psql` step, not
automatic.

## Security checklist before go-live

See the 013 report ("Self-Hosting del Gud Stack", checklist on page 8) for
the full list. The ones this bundle doesn't already handle for you:

- Replace the default Postgres password (`POSTGRES_PASSWORD` in `.env`),
  never expose port 5432 publicly (the bundled `postgres` service already
  has no `ports:` mapping — don't add one)
- Store all secrets in Dokploy's secret store, not committed `.env` files
- Confirm `.env` stays git-ignored in this fork
- Document data residency (Resend region, Pusher Cloud cluster vs Soketi,
  Anthropic if enabled) for the GDPR Art. 30 register; a self-hosted Soketi
  resolves the real-time item once phase 2 is done, EU Resend region
  resolves email, leaving only the Anthropic AI features (optional, off by
  default) as a US-provider item
- `/api/widget/*` and `/api/pusher/*` intentionally allow
  `Access-Control-Allow-Origin: *` — this is by design (the widget must be
  embeddable on any customer's website), not an oversight; no action needed
  unless we want to restrict which sites can embed it
- Set up scheduled `pg_dump` backups of the Postgres volume
  (`postgres-data` in `docker-compose.yml`) and test a restore
