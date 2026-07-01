# Chatwoot API, Webhooks, Automation & Enterprise Boundary — Code-Level Reference

Status: research complete, code-verified against `vendor/chatwoot/` at tag `v4.15.1`. This
deepens `docs/INTEGRATIONS_ROADMAP.md`'s MCP/Freshdesk/GitHub findings with the actual
mechanisms — REST API surface, auth, the outbound webhook system, the automation rule
engine, and the enterprise/CE code boundary — so future integration work (n8n, a Freshdesk
migration script, a custom MCP server) knows exactly what it's building against and never
accidentally depends on enterprise-only code in the self-hosted CE deployment.

## Key files

| File | What it is |
|---|---|
| `vendor/chatwoot/swagger/index.yml`, `swagger/tag_groups/application.yml`, `client.yml`, `platform.yml` | OpenAPI 3.1 spec entry points — three separate API surfaces (Application, Client, Platform) |
| `vendor/chatwoot/swagger/paths/application/` | ~90 path files, one per resource action, for the agent-facing "Application API" |
| `vendor/chatwoot/app/controllers/api/base_controller.rb` | Base controller for all `/api` controllers; wires up auth before_actions |
| `vendor/chatwoot/app/controllers/concerns/access_token_auth_helper.rb` | Actual API-token validation logic (`AccessToken.find_by(token:)`) |
| `vendor/chatwoot/app/models/webhook.rb` | Webhook model — allowed event list, account/inbox scoping |
| `vendor/chatwoot/lib/webhooks/trigger.rb` | Outbound HTTP delivery logic (signing, retries, timeout) |
| `vendor/chatwoot/app/jobs/webhook_job.rb` | Async job wrapper around `Webhooks::Trigger` |
| `vendor/chatwoot/app/listeners/webhook_listener.rb` | Maps internal domain events → webhook payloads |
| `vendor/chatwoot/app/models/automation_rule.rb` | Automation rule model — condition/action whitelist |
| `vendor/chatwoot/app/listeners/automation_rule_listener.rb` | Maps internal domain events → automation rule evaluation |
| `vendor/chatwoot/app/services/automation_rules/action_service.rb` | Executes an automation rule's actions, including `send_webhook_event` |
| `vendor/chatwoot/app/controllers/api/v1/accounts/automation_rules_controller.rb` | REST CRUD for automation rules (so rules are scriptable too) |
| `vendor/chatwoot/enterprise/lib/captain/` | Captain AI's LLM prompt/tool/service code |
| `vendor/chatwoot/enterprise/app/controllers/api/v1/accounts/captain/` | Captain's REST controllers |
| `vendor/chatwoot/config/features.yml` | Master feature-flag list, including which flags are `premium: true` |
| `vendor/chatwoot/app/models/concerns/featurable.rb` | How feature flags are stored/checked per-account (bitfield, not a hard code fork) |

## REST API surface & auth

The swagger tree (`vendor/chatwoot/swagger/`) is split into three independent OpenAPI documents, each with its own tag list (`vendor/chatwoot/swagger/tag_groups/application.yml:1`, `client.yml`, `platform.yml`):

- **Application API** (agent/admin facing, what n8n or a migration script would use) — tags include Agents, Contacts, Contact Labels, Conversations, Conversation Assignments, Conversation Labels, Custom Attributes, Custom Filters, Inboxes, Integrations, Labels, Messages, Profile, Reports, Teams, **Webhooks**, **Automation Rule**, Help Center, Account AgentBots (`vendor/chatwoot/swagger/tag_groups/application.yml:15-49`).
- **Client API** — a narrower, contact-facing surface for widget/client apps: Contacts API, Conversations API, Messages API (`vendor/chatwoot/swagger/tag_groups/client.yml`).
- **Platform API** — account/user provisioning at the platform-admin level (separate from the other two; not read in detail here, out of scope for the integrations in the roadmap).

The path files under `vendor/chatwoot/swagger/paths/application/` (~90 files) confirm resource groups match `app/controllers/api/v1/accounts/`: `automation_rule/{create,index,show,update,delete}.yml`, `webhooks/{create,index,update,delete}.yml`, `conversation/*.yml` (assignments, custom_attributes, filter, labels, messages, meta, toggle_status/priority/typing_status), `contacts/*.yml` (crud, filter, search, merge, labels, conversations), `teams/*.yml`, `reports/*.yml`, `inboxes/*.yml`, `integrations/hooks/*.yml`. This is a straight match to `vendor/chatwoot/app/controllers/api/v1/accounts/` (verified subdirectories: `actions`, `articles`, `assignment_policies`, `captain`, `channels`, `contacts`, `conversations`, `inboxes`, `integrations`, plus per-channel dirs for `google`, `microsoft`, `instagram`, `tiktok`, `twitter`, `whatsapp`, `notion`).

**Auth mechanism**: every `Api::BaseController` subclass runs `authenticate_access_token!` when an `api_access_token` header is present, otherwise falls back to session auth (`vendor/chatwoot/app/controllers/api/base_controller.rb:4-6`). The actual check is in `AccessTokenAuthHelper#authenticate_access_token!` (`vendor/chatwoot/app/controllers/concerns/access_token_auth_helper.rb:14-21`): it looks up `AccessToken.find_by(token: token)` from the `api_access_token` request header, and sets `Current.user` to the token's owner if that owner is a `User` or `AgentBot` (`access_token_auth_helper.rb:23-28`). A second guard, `validate_bot_access_token!`, restricts `AgentBot`-owned tokens to a small allowlist of endpoints/actions (`BOT_ACCESSIBLE_ENDPOINTS`, `access_token_auth_helper.rb:2-7`) — conversations show/toggle/create/update, message create, assignment create, label index/create. A **user-owned** access token (the kind you'd generate from Profile Settings, matching swagger's `userApiKey` securityScheme definition, `vendor/chatwoot/swagger/tag_groups/application.yml` bottom) is not subject to that allowlist and gets normal Pundit-policy-based authorization instead — this is the token type any external integration (n8n, migration script, third-party MCP server) should use, since bot tokens are deliberately restricted.

## Webhooks (outbound)

Chatwoot's own outbound webhook system is a real, native, always-available mechanism (no enterprise/premium gate found).

- **Model**: `Webhook` (`vendor/chatwoot/app/models/webhook.rb:22-40`) belongs to an `account`, optionally to an `inbox`, has a `url`, an optional `secret`, and a `subscriptions` jsonb array validated against a fixed whitelist, `ALLOWED_WEBHOOK_EVENTS` (`webhook.rb:26-27`):
  `conversation_status_changed`, `conversation_updated`, `conversation_created`, `contact_created`, `contact_updated`, `message_created`, `message_updated`, `webwidget_triggered`, `inbox_created`, `inbox_updated`, `conversation_typing_on`, `conversation_typing_off`.
- **Two webhook types**: `account_type` (fires for all matching events account-wide) and `inbox_type` (scoped to one inbox's `Channel::Api` webhook_url) — `webhook.rb:24`, dispatch logic in `vendor/chatwoot/app/listeners/webhook_listener.rb:110-131`.
- **Dispatch path**: domain events (via Rails' pub/sub event bus, `Events::Dispatcher` pattern shared with automation rules — not traced further here) are handled by `WebhookListener`, one method per event name (`webhook_listener.rb:2-92`), each building a `payload` hash from `conversation.webhook_data` / `message.webhook_data` / `contact.webhook_data` merged with `event: <event_name>` and (for update events) `changed_attributes`. Delivery is queued via `WebhookJob.perform_later(url, payload, webhook_type, secret:, delivery_id:)` (`webhook_job.rb:1-6`), which synchronously calls `Webhooks::Trigger.execute` (`lib/webhooks/trigger.rb:22-24`).
- **Payload delivery mechanics** (`lib/webhooks/trigger.rb:41-63`): POSTs `payload.to_json` via `SafeFetch.fetch` with a `WEBHOOK_TIMEOUT` global config (default 5s, `trigger.rb:118-123`). If a `secret` is set, it signs the body with `X-Chatwoot-Signature: sha256=<HMAC-SHA256(secret, "#{timestamp}.#{body}")>` and sends `X-Chatwoot-Timestamp` + `X-Chatwoot-Delivery` (UUID) headers (`trigger.rb:54-63`) — this is exactly what n8n's webhook-trigger node would need to verify authenticity.
- **Error handling** is asymmetric by webhook type: `agent_bot_webhook` failures with HTTP 429/500 are retried via `RetryableError` (`trigger.rb:2-3, 29, 125-127`); `api_inbox_webhook` failures mark the originating message as `failed` (`trigger.rb:72-73, 100-102`); plain account webhooks just log a warning on failure (`trigger.rb:34-37`) — i.e. a broken n8n endpoint silently drops account-type webhook deliveries rather than retrying, worth knowing operationally.
- **Management**: full CRUD via `Api::V1::Accounts::WebhooksController` per `swagger/paths/application/webhooks/{create,index,update,delete}.yml` — webhooks can be provisioned by API call, not just the admin UI, so n8n's target webhook could be registered by a setup script.

## Automation rules engine

A separate, higher-level mechanism from raw webhooks — conceptually a condition/action rule engine that (among other actions) *can* fire an ad-hoc webhook, making the two mechanisms complementary rather than redundant.

- **Model**: `AutomationRule` (`vendor/chatwoot/app/models/automation_rule.rb:20-107`) stores `event_name`, jsonb `conditions`, jsonb `actions`, `active` flag, scoped to an account.
- **Trigger events** (`event_name`) confirmed in `vendor/chatwoot/app/listeners/automation_rule_listener.rb:2-35`: `conversation_updated`, `conversation_created`, `conversation_opened`, `conversation_resolved`, `message_created`. Each rule is evaluated by `AutomationRules::ConditionsFilterService` against the account's active rules for that event, then executed via `AutomationRules::ActionService` if conditions match (`automation_rule_listener.rb:31-33, 53-56`).
- **Condition attributes** whitelist (`automation_rule.rb:38-40`): `content`, `email`, `country_code`, `status`, `message_type`, `browser_language`, `assignee_id`, `team_id`, `referer`, `city`, `company_name`, `inbox_id`, `mail_subject`, `phone_number`, `priority`, `conversation_language`, `labels`, `private_note`, plus any account custom attribute keys (`automation_rule.rb:70`).
- **Action types** whitelist (`automation_rule.rb:43-46`): `send_message`, `add_label`, `remove_label`, `send_email_to_team`, `assign_team`, `assign_agent`, `remove_assigned_agent`, `remove_assigned_team`, **`send_webhook_event`**, `mute_conversation`, `send_attachment`, `change_status`, `resolve_conversation`, `open_conversation`, `pending_conversation`, `snooze_conversation`, `change_priority`, `send_email_transcript`, `add_private_note`.
- **`send_webhook_event` confirmed as a first-class automation action**: `AutomationRules::ActionService#send_webhook_event` (`vendor/chatwoot/app/services/automation_rules/action_service.rb:38-41`) builds `payload = conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")` and calls `WebhookJob.perform_later(webhook_url[0], payload)` — i.e. it reuses the exact same delivery job/HTTP mechanics as the native `Webhook` model above, just triggered from rule conditions instead of a blanket event subscription, and **without HMAC signing** (no `secret:` kwarg passed, contrast with `webhook_listener.rb:114-116` which does pass one) — a gap worth flagging if payload authenticity matters for the n8n endpoint.
- **Management**: full CRUD + `clone` via `Api::V1::Accounts::AutomationRulesController` (`vendor/chatwoot/app/controllers/api/v1/accounts/automation_rules_controller.rb:1-68`), matching `swagger/paths/application/automation_rule/*.yml` — rules are scriptable/provisionable by API, same as webhooks.
- **Relationship to plain webhooks**: a plain `Webhook` subscription fires unconditionally for every matching event account/inbox-wide; an automation rule only fires its `send_webhook_event` action when its specific conditions match (e.g. "only when `priority = urgent` AND `labels` includes `github`"). For n8n purposes, this means condition-based filtering can happen inside Chatwoot (via an automation rule) instead of every event being pushed to n8n and filtered there — useful for the GitHub-visibility and general "notify n8n selectively" use cases in the roadmap.

## Captain AI

Confirmed: **Captain's entire implementation lives under `vendor/chatwoot/enterprise/`**, not in the OSS/CE app tree.

- Core LLM logic: `vendor/chatwoot/enterprise/lib/captain/` — `conversation_completion_service.rb`, `prompt_renderer.rb`, `response_schema.rb`, `assistant_action_schema.rb`, Liquid prompt templates under `prompts/` (`assistant.liquid`, `conversation_completion.liquid`, `scenario.liquid`), and a `tools/` directory with 8 tool classes (`add_contact_note_tool.rb`, `add_label_to_conversation_tool.rb`, `add_private_note_tool.rb`, `faq_lookup_tool.rb`, `handoff_tool.rb`, `http_tool.rb`, `resolve_conversation_tool.rb`, `update_priority_tool.rb`) — this `tools/` directory is the internal tool-calling mechanism Captain already has for itself; it is not exposed as an MCP interface (consistent with the roadmap's note that chatwoot#14382, external-MCP-servers-as-Captain-tools, is still an open unshipped issue).
- REST controllers: `vendor/chatwoot/enterprise/app/controllers/api/v1/accounts/captain/` — `assistants_controller.rb`, `documents_controller.rb`, `inboxes_controller.rb`, `copilot_messages_controller.rb`, `copilot_threads_controller.rb`, `scenarios_controller.rb`, `bulk_actions_controller.rb`, `custom_tools_controller.rb`, `assistant_responses_controller.rb`.
- Related enterprise-only models: `captain_inbox.rb`, `copilot_message.rb`, `copilot_thread.rb`, `article_embedding.rb` (`vendor/chatwoot/enterprise/app/models/`).
- **Feature-flag confirmation**: `vendor/chatwoot/config/features.yml` marks `captain_integration` (line 136-139), `captain_v1_action_classifier` (147-150), `captain_integration_v2` (177-180ish), `captain_document_auto_sync`, and `captain_tasks` all with `premium: true` and `enabled: false` by default.
- **Important nuance not to over-read**: `premium: true` in `config/features.yml` is a metadata flag consumed by `Featurable` (`vendor/chatwoot/app/models/concerns/featurable.rb:44-46` — a per-account bitfield flag, `feature_<name>` on the `feature_flags` column), not a hard license check baked into the code. There is no code-level license-server call gating Captain in this self-hosted CE checkout (the only external call found, `vendor/chatwoot/enterprise/lib/enterprise/chatwoot_hub.rb:1-8`, is `Enterprise::ChatwootHub`, which just points at `hub.2.chatwoot.com` and isn't a license check in the reviewed code). In practice this means the `premium` label reflects Chatwoot Cloud's commercial packaging, and self-hosted CE could technically flip the flag — but doing so is explicitly out of scope here per the roadmap's decision to treat Captain as unavailable, and Studio Zerotredici has not evaluated the ethics/ToS of enabling premium-labeled code paths on self-hosted CE. Treat the roadmap's "paid feature, not viable today" conclusion as still correct for planning purposes; this is a deeper code-level explanation of *why*, not a reversal of that decision.

## Enterprise vs CE boundary

`vendor/chatwoot/enterprise/` mirrors the main `app/` structure (`controllers`, `models`, `services`, `jobs`, `listeners`, `policies`, `views`, `helpers`, `mailers`, `builders`, `dispatchers`, `drops`, `fields`, `finders`, `presenters`) plus a `lib/` with `captain/`, `enterprise/`, `voice/`, `tasks/`. Rough file counts confirm `services` (104 files) and `models`/`views` (59/98) are the largest enterprise areas, controllers next (55).

Confirmed gated-to-enterprise feature areas (by locating their code exclusively under `enterprise/` and/or a `premium: true` flag in `config/features.yml`):

- **Captain AI** (all of it — assistants, copilot, document embeddings, tools) — see above.
- **SLA policies** — `enterprise/app/models/sla_policy.rb`, `applied_sla.rb`, `sla_event.rb`; `config/features.yml:123-127` marks `sla` as `premium: true`.
- **Custom Roles** — `enterprise/app/models/custom_role.rb`; `config/features.yml:140-143` marks `custom_roles` as `premium: true`.
- **Agent capacity policies** — `enterprise/app/models/agent_capacity_policy.rb`, `inbox_capacity_limit.rb`, controllers under `enterprise/app/controllers/api/v1/accounts/agent_capacity_policies/`.
- **Companies** (B2B contact grouping) — `enterprise/app/models/company.rb`, controllers under `enterprise/app/controllers/api/v1/accounts/companies/`.
- **SAML SSO** — `enterprise/app/models/account_saml_settings.rb`.
- **Voice/calling** — `enterprise/app/models/call.rb`, `enterprise/lib/voice/`.
- **Help Center embedding search** — `article_embedding.rb`, flagged `premium: true` in `config/features.yml:128-131` (name `help_center_embedding_search`).
- Enterprise also owns its own `super_admin/` controllers and `devise_overrides/`, `webhooks/` namespaces under `enterprise/app/controllers/enterprise/` — these look like admin-portal and auth extension points rather than end-user features; not fully explored here (would need a deeper pass if custom auth work is ever planned).

**What is confirmed core/CE** (i.e. safe to build against without any enterprise dependency): the entire REST API surface documented above (Conversations, Contacts, Inboxes, Agents, Teams, Labels, Custom Attributes, Custom Filters, Reports, Help Center articles/portal minus embedding search), the Webhook model/delivery system, the Automation Rule engine (all 5 trigger events and all ~18 actions including `send_webhook_event`), Teams, and inbox/channel management (email, WhatsApp, Telegram, API channel, widget). None of these required opening any file under `enterprise/` to trace end-to-end — confirmed by their controllers, models, listeners, and jobs all living under the plain `app/` tree.

**Extension pattern to be aware of**: per `vendor/chatwoot/CLAUDE.md`'s "Enterprise Edition Notes" and confirmed in code (e.g. `vendor/chatwoot/app/models/webhook.rb`'s final line `Webhook.include_mod_with('Audit::Webhook')` and `automation_rule.rb`'s `AutomationRule.prepend_mod_with('AutomationRule')`), several CE models are deliberately built with `prepend_mod_with`/`include_mod_with` hooks so the enterprise tree can extend/override CE behavior without forking it. This is Chatwoot's own internal extension mechanism (for their commercial product), not something this deployment should rely on or fight against — it only matters if a future custom-branding or feature change needs to touch a file that has one of these hooks, since the enterprise overlay may silently change its behavior at boot time if the enterprise tree happens to be loaded (it is not loaded in this project's Docker image, which uses the plain `chatwoot/chatwoot:v4.15.1-ce` tag — worth double-checking that `-ce` tag genuinely excludes the `enterprise/` directory at image-build time if this ever becomes load-bearing, not independently re-verified here beyond reading the Dockerfile recipe already covered in `docs/BRANDING_FORK_PLAN.md`).
