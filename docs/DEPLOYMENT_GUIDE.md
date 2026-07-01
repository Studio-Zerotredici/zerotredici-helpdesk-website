# Chatwoot Deployment on Dokploy — Studio Zerotredici Helpdesk

Date: 2026-07-01

Target platform: VPS managed through Dokploy (same pattern used for Termix/shell.zerotredici.com).

Persistent storage base path (on the Dokploy VPS, not in this repo):

```text
/var/www/studio_zerotredici/helpdesk.zerotredici.app
```

Assigned FQDN:

```text
helpdesk.zerotredici.app
```

> For the exact list of Dokploy Environment-tab variables, see [`DOKPLOY_ENVIRONMENT.md`](./DOKPLOY_ENVIRONMENT.md) — that file is the copy-paste source of truth. This guide covers the rationale, integrations, and MFA rollout.

## Executive Decision

Deploy Chatwoot as a four-service Docker Compose stack (Rails web, Sidekiq worker, Postgres with `pgvector`, Redis) rather than the "all-in-one" single-container image. The all-in-one image bundles Postgres/Redis inside one container, which is explicitly not recommended upstream for production and doesn't fit our bind-mount backup convention.

Use the Community Edition image tag (`-ce` suffix). The default `chatwoot/chatwoot:latest` tag ships Chatwoot's Enterprise Edition code paths gated behind a license; running self-hosted without a license means those code paths sit dormant but unaudited. The `-ce` tag strips Enterprise code entirely — fully open source (AGPL), no license ambiguity. Switch off `-ce` only if we want to trial licensed Enterprise features later.

Bootstrap first with local email/password authentication, verify HTTPS, SMTP delivery, and file storage, then enable MFA (native TOTP) as a second pass. This mirrors the two-phase rollout used for Termix (shell.zerotredici.com).

**Pin the version.** `docker-compose.yml` in this repo targets `v4.15.1-ce`, the latest stable release at time of writing — confirmed directly against the upstream git tags (`git ls-remote --tags`) and cross-checked that `v4.15.1-ce` exists and is active on [Docker Hub](https://hub.docker.com/r/chatwoot/chatwoot/tags). Verify against the releases page before deploying — Chatwoot ships frequently — and re-verify before any future upgrade.

## Source Findings

Official Chatwoot Docker docs provide a `docker-compose.production.yaml` template with four services (`rails`, `sidekiq`, `postgres`, `redis`), configured via a `.env` file, with containers bound only to `127.0.0.1` and a reverse proxy (Nginx in their docs) in front. Under Dokploy, Traefik plays that role instead — no reverse-proxy config needed on our side.

Dokploy also ships an official Chatwoot blueprint (`docs.dokploy.com/docs/templates/chatwoot`) using named Docker volumes. For Studio Zerotredici deployments, per our storage convention, these become absolute bind mounts on the VPS:

```text
/var/www/studio_zerotredici/helpdesk.zerotredici.app/data/storage   → /app/storage      (rails + sidekiq, attachments)
/var/www/studio_zerotredici/helpdesk.zerotredici.app/data/postgres → /var/lib/postgresql/data
/var/www/studio_zerotredici/helpdesk.zerotredici.app/data/redis    → /data
```

Postgres must use a `pgvector`-enabled image (`pgvector/pgvector:pg16`), not stock Postgres — Chatwoot's AI/search features (Captain) require the `vector` extension, and `rails db:chatwoot_prepare` will fail without it. No manual `init-vector.sql` bind-mount is needed; `db:chatwoot_prepare` creates the extension itself on current Chatwoot versions (Dokploy's own blueprint recently dropped that file for the same reason — see [PR #794](https://github.com/Dokploy/templates/pull/794)).

Redis is protected with `REDIS_PASSWORD` (upstream's own template leaves Redis unauthenticated by default — tightened here since Redis holds session/job data and only `expose` is used, never a host port).

As with Termix: **Dokploy Environment tab values only reach a container if the compose file declares them in that service's `environment` block**, and manual Traefik labels/network declarations are unnecessary — Dokploy injects them from the Domains UI.

## Compose File

`docker-compose.yml` at the root of this repo. Summary of services:

- `rails` — web app, port `3000` (internal only, routed via Dokploy Domains UI)
- `sidekiq` — background job worker, shares the same image/env as `rails`
- `postgres` — `pgvector/pgvector:pg16`, `pg_isready` healthcheck
- `redis` — `redis:alpine`, password-protected, `redis-cli ping` healthcheck

`rails db:chatwoot_prepare` is baked into the `rails` service's start command (`bundle exec sh -c 'rails db:chatwoot_prepare && rails s ...'`), so migrations run automatically on every deploy — safe and idempotent, and means you don't need a separate manual migration step after each redeploy. `rails` and `sidekiq` both wait on `postgres`/`redis` reaching `service_healthy` (not just `service_started`) before starting, so a slow cold-start Postgres can't cause a migration to run against a not-yet-ready database.

## Networking Model (read before troubleshooting a 404)

`docker-compose.yml` deliberately declares **no external network** — only the
internal `chatwoot-backend` bridge network the four services use to talk to
each other (e.g. `rails` → `postgres`/`redis`). This is intentional, not an
oversight:

- When you assign the domain to the `rails` service in Dokploy's Domains UI
  (deployment step 5 below), **Dokploy automatically injects Traefik routing
  labels and connects that specific service to its own `dokploy-network`** at
  deploy time — you can see the final result via Dokploy's "Preview Compose"
  button before deploying. Don't hand-write Traefik labels or declare an
  external network yourself for this; Dokploy generates it.
- `dokploy-network` is Traefik's routing plane only — it has nothing to do
  with how `rails`/`sidekiq`/`postgres`/`redis` reach each other, which is
  handled entirely by the internal `chatwoot-backend` network already in the
  compose file.
- **Known Dokploy bug** ([Dokploy/dokploy#3435](https://github.com/Dokploy/dokploy/issues/3435)):
  in some cases, a Compose-deployed service doesn't actually get connected to
  `dokploy-network` even though the Traefik labels look correct, so the
  domain 404s. If `https://helpdesk.zerotredici.app` 404s after a deploy with
  the domain correctly configured, the documented workaround is to add the
  network explicitly to the `rails` service (exact name matters — it must be
  `dokploy-network`, not an invented name) and redeploy:
  ```yaml
  services:
    rails:
      networks:
        - chatwoot-backend
        - dokploy-network
  networks:
    dokploy-network:
      external: true
  ```
  Only add this if the 404 actually happens — don't pre-emptively declare it,
  since Dokploy's automatic injection is the documented default behavior and
  works in the normal case.

## Host Preparation

Run once on the Dokploy VPS before the first deploy:

```bash
mkdir -p /var/www/studio_zerotredici/helpdesk.zerotredici.app/data/storage
mkdir -p /var/www/studio_zerotredici/helpdesk.zerotredici.app/data/postgres
mkdir -p /var/www/studio_zerotredici/helpdesk.zerotredici.app/data/redis
```

The official Postgres and Chatwoot images self-adjust ownership of their data directories on first start; no manual `chown` should be needed. If attachment uploads fail with permission errors after first boot, check `docker logs` on the `rails` container before changing host permissions.

## Dokploy Deployment Steps

1. In Dokploy: Project → New Service → Docker Compose.
2. Point it at this repo (Git-based Compose source) so `docker-compose.yml` is pulled directly, rather than pasting it manually — keeps this repo as the single source of truth for the compose file.
3. Confirm all three bind-mount paths point under `/var/www/studio_zerotredici/helpdesk.zerotredici.app/data/`.
4. Set the environment variables listed in [`DOKPLOY_ENVIRONMENT.md`](./DOKPLOY_ENVIRONMENT.md) in the Environment tab.
5. Add the domain `helpdesk.zerotredici.app` in Dokploy's Domains UI, targeting service `rails` on port `3000`.
6. Deploy. First boot runs `db:chatwoot_prepare` — can take a minute or two.
7. Visit `https://helpdesk.zerotredici.app` and complete the initial admin account setup (first registered user becomes the account admin/owner).
8. Confirm outbound email works: invite a second agent and check that the invite email arrives via SES.

## Phase 2: Enable MFA After Bootstrap

Chatwoot's native MFA (TOTP, per-user, opt-in) requires **v4.6+** — well below our pinned `v4.15.1-ce` — and Active Record Encryption keys to store user TOTP secrets. Full variable list and generation command are in [`DOKPLOY_ENVIRONMENT.md`](./DOKPLOY_ENVIRONMENT.md#phase-2--enable-mfa-after-first-successful-deploy).

Once enabled, each agent turns it on individually: **Profile Settings → Security → Enable Two-Factor Authentication**, scan the QR code, save the 10 backup codes.

Chatwoot has no account-wide MFA enforcement toggle yet — this is an open upstream feature request ([chatwoot#13834](https://github.com/chatwoot/chatwoot/issues/13834)). Track manually which agents have it enabled.

Admin recovery if an agent loses both their authenticator and backup codes (run inside the `rails` container):

```bash
rake mfa:reset[user@example.com]
rake mfa:generate_backup_codes[user@example.com]
```

## Connecting WhatsApp Business

Chatwoot supports WhatsApp via the official Meta Cloud API. Two setup paths:

### Recommended: Embedded Signup (OAuth, no manual webhook config)

**One-time super-admin setup**, before any agent can use this flow: `https://helpdesk.zerotredici.app/super_admin/app_config?config=whatsapp_embedded`, then set:

- `WHATSAPP_APP_ID`
- `WHATSAPP_CONFIGURATION_ID`
- `WHATSAPP_APP_SECRET`

To obtain these from Meta:

1. Go to [Meta for Developers](https://developers.facebook.com/) → My Apps → Create App → type **Business**.
2. In the app dashboard, add the **WhatsApp** product and accept the WhatsApp Business Terms.
3. Copy **App ID** and **App Secret** from Settings → Basic.
4. Go to **Facebook Login for Business → Configurations**, create a configuration:
   - Login variation: WhatsApp Embedded Signup
   - Asset: WhatsApp Account (manage-account permission)
   - Permissions: `whatsapp_business_management`, `whatsapp_business_messaging`, `business_management`
5. Copy the generated **Configuration ID**.
6. Before going live, subscribe the app to the `messages` webhook field for the WhatsApp Business Account (otherwise the embedded flow throws error #100 during setup).

**Connecting the inbox** (any Chatwoot admin/agent, once the above is configured):

1. Settings → Inboxes → Add Inbox → WhatsApp → "WhatsApp Cloud".
2. Click "Connect with WhatsApp Business".
3. Log in with the Facebook account managing the WABA.
4. Select/create a business portfolio, WhatsApp Business Account, and phone number.
5. Chatwoot registers the webhook and phone number automatically — done.

Note: Meta reviews new WhatsApp Business setups for Commerce Policy compliance and may follow up within 24 hours if there's an issue.

### Fallback: Manual Setup (no embedded signup)

Use this if the app isn't approved for embedded signup yet, or you want to reuse an existing Meta system user:

1. In Meta Business Settings, create a **System User** with Admin role, assign the WhatsApp asset, and generate a permanent access token.
2. In Chatwoot: Settings → Inbox → WhatsApp, enter phone number, phone number ID, and Business Account ID.
3. Configure the webhook in Meta's app dashboard as:
   ```text
   https://helpdesk.zerotredici.app/webhooks/whatsapp/{phone_number}
   ```

## Connecting Telegram

Simpler than WhatsApp — no Meta review required:

1. In Telegram, message **@BotFather**, run `/newbot`, follow the prompts to name the bot. BotFather returns an API token.
2. In Chatwoot: Settings → Inboxes → Add Inbox → Telegram.
3. Paste the bot's API token → Create Telegram Channel.
4. Add agents to the new inbox.
5. Verify: the inbox name should match the bot's `@username`; send the bot a test message and confirm it lands in Chatwoot.

Chatwoot auto-registers the Telegram webhook for the bot — no manual webhook URL entry needed.

Optional — Telegram **Business** mode (lets a bot answer on behalf of a real Telegram Business account, added in Chatwoot v4.3.0, so it's available on our pinned v4.15.1): in BotFather run `/business_mode`, select the bot, confirm. Then create the Telegram inbox in Chatwoot using that same bot token — Chatwoot auto-detects Business Mode and registers the correct webhook.

## GitHub Integration — Not Yet Available

Checked the current (as of 2026-07-01) official integrations page directly: [chatwoot.com/features/integrations](https://www.chatwoot.com/features/integrations/) lists **GitHub under "Coming Q4 2026"**, not under "Available Now." Some search results and third-party summaries describe it as if already shipped — that's inaccurate as of today; don't rely on it being live yet.

**Workaround until it ships:** wire it yourself with Chatwoot's webhooks + REST API and the GitHub API, via n8n:

1. Chatwoot → Settings → Integrations → Webhooks → add an n8n webhook URL, subscribed to `conversation_created` / `conversation_status_changed` (or whichever event should trigger an issue).
2. n8n workflow: receive the Chatwoot webhook → call GitHub's "Create issue" API (`POST /repos/{owner}/{repo}/issues`) with the conversation summary/link → optionally call Chatwoot's REST API back to post a private note on the conversation with the resulting issue URL.
3. Chatwoot's [REST API](https://developers.chatwoot.com/api-reference/introduction) and [webhooks guide](https://www.chatwoot.com/hc/user-guide/articles/1677693021-how-to-use-webhooks) have everything needed for both directions.

This workflow would live as a separate n8n flow, not inside this repo's compose file.

## Backup and Restore

Back up the entire directory on the VPS:

```text
/var/www/studio_zerotredici/helpdesk.zerotredici.app/data
```

This covers three things that must not be lost or leaked:

- `data/postgres` — all conversations, contacts, accounts, and (once Phase 2 is done) encrypted MFA secrets.
- `data/storage` — attachments sent/received in conversations.
- `data/redis` — session/job queue data (lower priority, safe to lose, but back up anyway for fast recovery).

Minimum backup posture:

- Nightly backup of the full `data/` directory.
- Encrypt backups at rest.
- Keep at least one off-host copy.
- Store the three `ACTIVE_RECORD_ENCRYPTION_*` keys (once generated) in the secrets vault, not just in Dokploy's Environment tab — losing them independently of the DB backup still breaks MFA.
- Test a full restore before this becomes the production helpdesk.

## Security Notes

- Keep Chatwoot behind HTTPS only (Dokploy/Traefik terminates TLS; no internal SSL needed).
- Postgres and Redis are `expose`-only in the compose file — never bind them to a host port.
- Redis is password-protected (`REDIS_PASSWORD`); upstream's own template ships it open by default — don't copy that as-is elsewhere.
- `ENABLE_ACCOUNT_SIGNUP=false` — don't allow public self-registration on an internal helpdesk instance.
- MFA is opt-in per user; since Chatwoot has no account-wide enforcement toggle yet, track manually which agents have it enabled.
- SES SMTP credentials are separate secrets from AWS IAM keys — store them as such, and scope the SES sending identity narrowly.
- Meta tokens (WhatsApp System User token, App Secret) and the Telegram bot token are all bearer credentials — store in the same vault as other integration secrets, never in this repo.
- Pin the image tag (`v4.15.1-ce`) — don't run `latest` in production; re-verify the tag against the [releases page](https://github.com/chatwoot/chatwoot/releases) before every upgrade and run through the upgrade path iteratively if jumping multiple versions.

## Operational Validation Checklist

- DNS resolves `helpdesk.zerotredici.app` to the Dokploy VPS.
- Dokploy domain has a valid TLS certificate.
- Chatwoot UI loads over HTTPS and `db:chatwoot_prepare` completed without errors in the `rails` container logs.
- Test agent invite email delivers via SES.
- No host-level port binding exists for `3000`, `5432`, or `6379`.
- Nightly backup job covers the full `data/` directory.
- WhatsApp inbox receives and sends a test message.
- Telegram inbox receives and sends a test message.

If MFA (Phase 2) is enabled, also verify:

- A test agent can enroll TOTP and log back in with a 6-digit code.
- Backup codes are generated and one has been test-used.
- The three `ACTIVE_RECORD_ENCRYPTION_*` keys are stored in the vault, separate from the Dokploy Environment tab.

## Sources

- [Chatwoot Docker production deployment guide](https://developers.chatwoot.com/self-hosted/deployment/docker)
- [Chatwoot environment variables reference](https://developers.chatwoot.com/self-hosted/configuration/environment-variables)
- [Chatwoot MFA setup guide](https://developers.chatwoot.com/self-hosted/configuration/multi-factor-authentication)
- [Chatwoot WhatsApp Embedded Signup](https://developers.chatwoot.com/self-hosted/configuration/features/integrations/whatsapp-embedded-signup)
- [Chatwoot WhatsApp channel user guide](https://www.chatwoot.com/hc/user-guide/articles/1677832735-how-to-setup-a-whats_app-channel)
- [Chatwoot Telegram channel user guide](https://www.chatwoot.com/hc/user-guide/articles/1677838569-how-to-setup-a-telegram-channel)
- [Chatwoot integrations page (GitHub status)](https://www.chatwoot.com/features/integrations/)
- [Chatwoot webhooks guide](https://www.chatwoot.com/hc/user-guide/articles/1677693021-how-to-use-webhooks)
- [Chatwoot API reference](https://developers.chatwoot.com/api-reference/introduction)
- [Chatwoot official docker-compose.production.yaml](https://github.com/chatwoot/chatwoot/blob/develop/docker-compose.production.yaml)
- [Dokploy Chatwoot template](https://docs.dokploy.com/docs/templates/chatwoot)
- [Dokploy templates PR removing broken init-vector.sql mount](https://github.com/Dokploy/templates/pull/794)
- [Chatwoot changelog](https://www.chatwoot.com/changelog/)
- [Chatwoot GitHub releases](https://github.com/chatwoot/chatwoot/releases)
