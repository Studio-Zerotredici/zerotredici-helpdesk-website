# Deploying GudDesk on Dokploy

This is the concrete, Studio Zerotredici-specific companion to
[`content/docs/self-hosting.mdx`](./content/docs/self-hosting.mdx) and
[`.claude/context/deployment.md`](./.claude/context/deployment.md). It covers
exactly what's needed to get **this fork** fully working on our own Dokploy
instance — including login and email, which don't work out of the box until
the steps below are done.

Scope: this repo is **GudDesk only**. It does not call or depend on GudCal,
GudForm, or GudAgent anywhere in the codebase — it's a fully standalone
Next.js + Postgres app. Those three are separate GudLab products/repos; the
only real integration direction is GudAgent *calling into* GudDesk's REST
API later, not the reverse. Nothing below requires them.

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
   our Resend account before go-live** (step 4 below).

Good news already in the fork: Google OAuth is not the only login method —
`auth.config.ts` has Credentials (email+password, bcrypt) and Resend magic
link alongside it, so login isn't blocked on setting up Google OAuth at all.

## Step 1 — Postgres

In Dokploy: create a **Postgres** managed database resource (not the
`postgres-docker-compose.yml` in this repo — that's for local dev only).
Set a real password. Note the internal connection string for `DATABASE_URL`
in step 4. Do not expose port 5432 publicly.

## Step 2 — Soketi (self-hosted real-time)

We're self-hosting real-time chat instead of using Pusher Cloud, per the
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

If you'd rather not run Soketi yet, skip this — GudDesk works fine without
real-time (falls back to 4-second polling in the widget/inbox). You can add
it later.

## Step 3 — GudDesk application

1. In Dokploy, create a new application pointed at this repo
   (`Studio-Zerotredici/zerotredici-helpdesk-website`), build type
   **Dockerfile** (the repo's own `Dockerfile`, not Nixpacks — see the 013
   report for why: deterministic, pinned builds and the widget/Contentlayer
   build chain baked into the image).
2. Container port `3000`.
3. Point a domain at it, e.g. `desk.yourdomain.com`, enable TLS.

## Step 4 — Environment variables

Copy `.env.example` as your starting point and fill in real values as
Dokploy **secrets** (not committed anywhere). Minimum for a working
login+email deploy:

| Variable | Required for | Notes |
|---|---|---|
| `NEXT_PUBLIC_APP_URL` | everything | `https://desk.yourdomain.com`, no trailing slash |
| `AUTH_SECRET` | sessions | `openssl rand -base64 32` — set explicitly, don't autogenerate |
| `AUTH_TRUST_HOST` | reverse proxy | `true` |
| `DATABASE_URL` | everything | from Step 1, internal Dokploy network address |
| `RESEND_API_KEY` | magic link / reset / invites | from resend.com |
| `EMAIL_FROM` | magic link / reset / invites | e.g. `GudDesk <support@yourdomain.com>` — domain must be verified in Resend (step 5) |
| `EMAIL_REPLY_TO_DOMAIN` | reply-by-email | e.g. `mail.yourdomain.com`, needs Resend inbound routing if you want this feature |
| `PUSHER_APP_ID` / `PUSHER_SECRET` / `NEXT_PUBLIC_PUSHER_KEY` | real-time | same values as Soketi step 2 |
| `PUSHER_HOST` / `NEXT_PUBLIC_PUSHER_HOST` | real-time (Soketi) | `ws.yourdomain.com` |
| `PUSHER_PORT` / `NEXT_PUBLIC_PUSHER_PORT` | real-time (Soketi) | `443` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google login | optional, step 6 |
| `ANTHROPIC_API_KEY` | AI features | optional — leave unset if sending conversation content to a US provider isn't acceptable |

Email+password login (Credentials provider) works with just `AUTH_SECRET`
and `DATABASE_URL` — no Resend/Google needed for that path.

## Step 5 — Verify the Resend sending domain

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

## Step 6 — Google OAuth (optional)

1. console.cloud.google.com → APIs & Services → Credentials → Create OAuth
   client ID (Web application).
2. Authorized redirect URI: `https://desk.yourdomain.com/api/auth/callback/google`.
3. Set `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`.

Skip this entirely if email+password is enough for our agents — nothing
else depends on it.

## Step 7 — First deploy

Build and deploy the GudDesk app in Dokploy. On container start,
`entrypoint.sh` runs `prisma migrate deploy` (applies `prisma/migrations/`)
before starting the server — first boot creates the schema automatically,
no manual `pnpm prisma db push` needed.

**Watch the first deploy's logs** for the migration step — this is the one
part of the Dockerfile change (copying the `prisma` CLI into the slim
runner image) that couldn't be verified without an actual `pnpm install` +
Docker build, which wasn't possible in this review. If
`node ./node_modules/prisma/build/index.js migrate deploy` errors on first
boot, the fallback is running it once manually via Dokploy's "Exec into
container" / `docker exec` and adjusting the CLI invocation path in
`entrypoint.sh` to match whatever pnpm actually laid out under
`node_modules/prisma/` — everything else in the image is unaffected.

## Step 8 — Verification checklist

- [ ] `https://desk.yourdomain.com` loads, register/login pages render
- [ ] Create the first account via email+password (Credentials) — this
      should work even before Resend/Google are configured
- [ ] Set up a workspace, get the widget snippet, embed it on a test page
- [ ] Send a message from the widget, confirm it appears in the inbox
      (real-time if Soketi is up, otherwise within ~4s via polling)
- [ ] Trigger "forgot password" — confirm the email arrives (proves
      `EMAIL_FROM` + Resend domain verification worked)
- [ ] Invite a teammate to the workspace — confirm the invite email arrives
- [ ] If Google OAuth configured: log in with Google
- [ ] If Soketi configured: open browser devtools on the widget page,
      confirm a `wss://ws.yourdomain.com` connection, not polling

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

- Replace the default Postgres password, never expose port 5432
- Store all secrets in Dokploy's secret store, not committed `.env` files
- Confirm `.env` stays git-ignored in this fork
- Document data residency (Resend region, Soketi vs Pusher, Anthropic if
  enabled) for the GDPR Art. 30 register; a self-hosted Soketi resolves the
  real-time item, EU Resend region resolves email, leaving only the
  Anthropic AI features (optional, off by default) as a US-provider item
- `/api/widget/*` and `/api/pusher/*` intentionally allow
  `Access-Control-Allow-Origin: *` — this is by design (the widget must be
  embeddable on any customer's website), not an oversight; no action needed
  unless we want to restrict which sites can embed it
- Set up scheduled `pg_dump` backups of the Postgres volume and test a
  restore
