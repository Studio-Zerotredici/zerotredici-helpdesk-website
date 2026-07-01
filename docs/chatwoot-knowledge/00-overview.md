# Chatwoot Codebase Knowledge Base — Overview

Index for a code-grounded research pass over `vendor/chatwoot/` (local, unpacked
reference checkout, pinned tag `v4.15.1`, no `.git`, ~146MB / 8,278 files) in this
repo. Every claim in these docs cites `vendor/chatwoot/path/to/file:LINE` — nothing
here is guessed from filenames or upstream docs alone. This pass was run 2026-07-01
after Studio Zerotredici decided to self-host Chatwoot CE (abandoning a custom
Next.js "GudDesk" fork that architecturally couldn't support email-as-ticket-source,
which is the actual reason for the switch).

**Scope note:** this is a reference for understanding *how Chatwoot's own code works*,
not an implementation plan. `docs/BRANDING_FORK_PLAN.md` and
`docs/INTEGRATIONS_ROADMAP.md` are the implementation-facing docs — both have been
updated to reference the relevant pages below now that their "needs research" items
are answered.

## Pages

- [data-model.md](./data-model.md) — Core Rails models: `Account`, `Conversation`,
  `Contact`, `Inbox`, `Message`, `User`, `Team`, `Label`, `CustomAttributeDefinition`,
  `ContactInbox`, `AgentBot`, cross-checked against `db/schema.rb`. Includes the
  exact entity ordering a Freshdesk import script needs to follow.
- [channels-and-inboxes.md](./channels-and-inboxes.md) — How `Channel::*` models plug
  into `Inbox` polymorphically; inbound email specifically goes through a **custom
  IMAP-polling job** (`Inboxes::FetchImapEmailsJob` → `Imap::FetchEmailService`), not
  purely Rails ActionMailbox's webhook routing — relevant to Studio Zerotredici's
  generic IMAP/SMTP setup (Stalwart/Postfix, not Google/Microsoft OAuth). Also covers
  the two independent assignment axes (individual agent vs. Team).
- [frontend-architecture.md](./frontend-architecture.md) — The Vue frontend is
  **seven independent Vite-built apps** (`dashboard`, `widget`, `sdk`, `v3`, `portal`,
  `survey`, `superadmin`), not one app with mode-switching. Dashboard and widget are
  genuinely separate bundles/stores. `portal/` (help center) is Rails+Turbo, not Vue.
- [branding-injection-points.md](./branding-injection-points.md) — **Key finding:**
  Chatwoot CE already ships native, DB-backed white-labeling for installation name,
  logo, and "Powered by" attribution (`installation_config.yml` → `InstallationConfig`
  → `window.globalConfig`) — but those specific keys default `locked: true`, so they
  need a one-time `rails runner`/seed script, not Dokploy env vars or the Super Admin
  UI. Only the primary brand **color** (SCSS custom properties) and the
  **favicon/manifest.json** genuinely need a build-time file overlay. This
  substantially shrinks `BRANDING_FORK_PLAN.md`'s original scope.
- [background-jobs.md](./background-jobs.md) — Sidekiq queue/priority config,
  `sidekiq-cron`-driven schedule (`config/schedule.yml`, 11 entries), and which jobs
  are the natural integration points for future work — `lib/webhooks/trigger.rb`
  already does HMAC-signed, retried outbound delivery.
- [api-integrations-and-enterprise.md](./api-integrations-and-enterprise.md) —
  **Key finding:** the native `Webhook` model + Automation Rule engine (with a
  `send_webhook_event` action) together can drive an **n8n integration with zero
  Chatwoot code changes** — both are CE, both fully REST-API-provisionable. Caveat:
  automation-rule-fired webhooks are *not* HMAC-signed (unlike plain webhooks), so
  that path needs network-level trust if signature verification matters. Also maps
  the enterprise/CE boundary precisely (Captain AI, SLA policies, Custom Roles,
  Companies, SAML SSO, Voice, Help Center search — all gated via a `premium: true`
  flag in `config/features.yml`, not a license-server call).

## Cross-cutting facts worth remembering

- Every branding/config claim above was verified against `vendor/chatwoot/CLAUDE.md`
  (Chatwoot's own in-repo dev guidelines), which explicitly tells contributors to use
  `replaceInstallationName()` / `components-next/` rather than hardcoding brand
  strings — i.e. Chatwoot's own team designed these as extension points.
- Three "is this native or custom work" questions from `INTEGRATIONS_ROADMAP.md` are
  now answered at the code level, not just the docs level: email channel (native, via
  IMAP polling — confirmed), Teams (native, dual-assignment confirmed), and the
  webhook/automation path for n8n (native, confirmed, with the one signing caveat
  above).
- Known gaps, honestly flagged by the research agents rather than guessed past:
  login-screen-specific logo usage (branding doc), the IMAP polling cron interval and
  Assignment V2's selection algorithm internals (channels doc), and whether the
  Enterprise module is even loadable in the pinned `-ce` image (api/enterprise doc).
  None of these block current planning; revisit if they become load-bearing.

## Maintenance

Tied to the pinned tag `v4.15.1`. Re-run (or diff-check) on major version bumps, not
continuously — same policy as `vendor/chatwoot/` itself per the root `CLAUDE.md`.
