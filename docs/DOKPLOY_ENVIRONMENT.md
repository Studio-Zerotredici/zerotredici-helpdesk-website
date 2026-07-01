# Dokploy Environment Tab — Chatwoot (helpdesk.zerotredici.app)

Exact list of variables to paste into this service's **Environment** tab in Dokploy. This file lists variable *names* only — never commit real secret values to this repo. Store actual values in the team vault.

Rule to remember: a variable only reaches the running container if it's *also* declared in that service's `environment:` block in `docker-compose.yml`. All variables below are already wired into `docker-compose.yml` — you only need to supply values in Dokploy, not touch the compose file.

## Required before the first deploy

| Variable | Value | Notes |
|---|---|---|
| `FRONTEND_URL` | `https://helpdesk.zerotredici.app` | Fixed, not a secret |
| `SECRET_KEY_BASE` | generate, see below | Rails session/cookie signing key |
| `POSTGRES_PASSWORD` | generate a strong password | |
| `REDIS_PASSWORD` | generate a strong password | |
| `DEFAULT_LOCALE` | `it` | Optional — defaults to `it` in the compose file if omitted |
| `MAILER_SENDER_EMAIL` | e.g. `Helpdesk Studio Zerotredici <helpdesk@zerotredici.app>` | Must be a verified SES identity |
| `SMTP_ADDRESS` | `email-smtp.<your-ses-region>.amazonaws.com` | e.g. `eu-central-1`, `eu-west-1` — match the region your SES identity is verified in |
| `SMTP_PORT` | `587` | |
| `SMTP_USERNAME` | SES **SMTP** username | Not your AWS IAM access key ID — generate from SES's "SMTP settings" page |
| `SMTP_PASSWORD` | SES **SMTP** password | Not your AWS IAM secret key |

Generate `SECRET_KEY_BASE` locally (don't reuse across environments):

```bash
head /dev/urandom | tr -dc A-Za-z0-9 | head -c 63 ; echo ''
```

Before setting `SMTP_*`: confirm the SES sending identity/domain is verified and the SES account is out of sandbox mode, or mail to non-verified recipients will bounce silently.

## Phase 2 — enable MFA (after first successful deploy)

Leave these blank for the first deploy. Chatwoot's native TOTP MFA needs Active Record Encryption keys, generated once from inside the running `rails` container:

```bash
docker exec -it <rails-container-name> sh -c "RAILS_ENV=production bundle exec rails db:encryption:init"
```

That prints three values — add them here, then redeploy:

| Variable |
|---|
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` |

**Back these three up separately, off-host, encrypted, before anything else.** They can't be regenerated: losing them makes every agent's existing MFA secret unreadable, forcing full re-enrollment. If migrating to a new server, copy these exact values — never re-run `db:encryption:init` on the new box.

## Not Dokploy variables — configured inside Chatwoot itself instead

These are commonly confused with Dokploy env vars but are **not** set here:

- **WhatsApp Embedded Signup** (`WHATSAPP_APP_ID`, `WHATSAPP_CONFIGURATION_ID`, `WHATSAPP_APP_SECRET`) — set once logged in as Chatwoot Super Admin, at `https://helpdesk.zerotredici.app/super_admin/app_config?config=whatsapp_embedded`. See `docs/DEPLOYMENT_GUIDE.md` for the full Meta setup walkthrough.
- **Telegram bot token** — pasted directly into Chatwoot's "Add Inbox → Telegram" form. Not an env var at all.

## Secrets hygiene

- This file and `docker-compose.yml` should only ever contain variable *names* and safe defaults (e.g. `FRONTEND_URL`, `DEFAULT_LOCALE`) — never real passwords, tokens, or keys.
- All real values live only in Dokploy's Environment tab and the team password vault.
- If a secret is ever pasted into a commit by mistake, treat it as compromised: rotate it (new SES SMTP credentials, new `SECRET_KEY_BASE`, etc.) rather than just removing it from a later commit.
