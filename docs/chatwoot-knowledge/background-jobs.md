# Chatwoot background jobs (Sidekiq) — reference notes

Chatwoot runs all asynchronous work through Rails' `ActiveJob` on a `Sidekiq` backend
(`vendor/chatwoot/Gemfile:136`), with the `worker` process (our `sidekiq` Compose service)
started as `bundle exec sidekiq -C config/sidekiq.yml` (`vendor/chatwoot/Procfile:3`). Ten
named queues are drained in strict priority order (higher queues starve lower ones only
when empty), concurrency defaults to 10 threads via `SIDEKIQ_CONCURRENCY`
(`vendor/chatwoot/config/sidekiq.yml:4,32,34`), and periodic/cron-style jobs are driven by
the `sidekiq-cron` gem (`vendor/chatwoot/Gemfile:138`) reading a static schedule from
`config/schedule.yml`, loaded into Redis on boot (`vendor/chatwoot/config/initializers/sidekiq.rb:36-50`).
Jobs fall into four rough categories — outbound message delivery, webhook/integration
dispatch, conversation/notification lifecycle management, and scheduled housekeeping —
and several of them (webhook delivery, Slack, WhatsApp/Telegram/Instagram/etc. inbound
events, email sending) are the natural integration points for future n8n bridging work.

## Key files

| File | What it is |
|---|---|
| `vendor/chatwoot/config/sidekiq.yml` | Queue list, priority order, concurrency, timeout, max retries |
| `vendor/chatwoot/config/initializers/sidekiq.rb` | Redis config for client/server, dequeue logging middleware, loads `schedule.yml` into `sidekiq-cron` on boot |
| `vendor/chatwoot/config/schedule.yml` | The periodic/cron job schedule (source of truth for `sidekiq-cron`) |
| `vendor/chatwoot/Procfile` | Process types: `web` (Rails), `worker` (Sidekiq), `release` (migrations) |
| `vendor/chatwoot/app/jobs/application_job.rb` | Base job class all jobs inherit from (or `MutexApplicationJob`) |
| `vendor/chatwoot/app/jobs/mutex_application_job.rb` | Base class adding Redis-lock (`with_lock`) support for jobs needing mutual exclusion |
| `vendor/chatwoot/app/jobs/webhook_job.rb` | Generic outbound webhook delivery job (account/inbox/agent-bot webhooks) |
| `vendor/chatwoot/lib/webhooks/trigger.rb` | The actual HTTP delivery + signing + error-handling logic used by `WebhookJob` |
| `vendor/chatwoot/app/jobs/hook_job.rb` | Dispatches internal events to third-party *integrations* (Slack, Dialogflow, Google Translate, LeadSquared, Linear) |
| `vendor/chatwoot/app/jobs/event_dispatcher_job.rb` | Publishes internal domain events (`critical` queue) into `Rails.configuration.dispatcher` |
| `vendor/chatwoot/app/jobs/send_reply_job.rb` | Routes an outgoing message to the correct channel-specific delivery service (WhatsApp, Twilio, Telegram, Email, etc.) |
| `vendor/chatwoot/app/jobs/conversation_reply_email_job.rb` | Sends the "you have a new reply" transactional email to a contact |
| `vendor/chatwoot/app/jobs/trigger_scheduled_items_job.rb` | The 5-minute cron entry point that fans out to several other scheduled jobs |
| `vendor/chatwoot/app/jobs/internal/trigger_daily_scheduled_items_job.rb` | Daily cron entry point (staggers per-install daily jobs across the day) |
| `vendor/chatwoot/app/jobs/internal/trigger_hourly_scheduled_items_job.rb` | Hourly cron entry point — currently an empty hook (CE has nothing hourly; Enterprise doesn't override it either, per search) |
| `vendor/chatwoot/enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb` | Enterprise-only addition to the 5-minute cron: triggers SLA checks |
| `vendor/chatwoot/enterprise/app/jobs/enterprise/internal/trigger_daily_scheduled_items_job.rb` | Enterprise-only addition to the daily cron: Captain (AI) document sync jobs |

Note: our deployment runs `chatwoot/chatwoot:v4.15.1-ce` (CE image). Whether Enterprise-module
code (`vendor/chatwoot/enterprise/...`) is actually loaded/active in the `-ce` build image
was **not verified in this pass** — flagging as unclear rather than assuming either way.

## Queue configuration

From `vendor/chatwoot/config/sidekiq.yml:16-33`, queues are declared without weights, so
Sidekiq drains them strictly top-to-bottom — a queue is only serviced once every queue
above it is empty:

1. `critical`
2. `high`
3. `medium`
4. `default`
5. `mailers`
6. `action_mailbox_routing`
7. `low`
8. `scheduled_jobs`
9. `deferred`
10. `purgable`
11. `housekeeping`
12. `async_database_migration`
13. `bulk_reindex_low`
14. `active_storage_analysis`
15. `active_storage_purge`
16. `action_mailbox_incineration`

Other settings (`vendor/chatwoot/config/sidekiq.yml:4,7,8,32,34`):
- `concurrency`: `ENV['SIDEKIQ_CONCURRENCY']`, default **10** threads (same default reused for both `production` and `staging` env blocks — i.e. this is the one Sidekiq tunable exposed via env var).
- `timeout: 25` — Sidekiq's shutdown grace period, not a per-job execution timeout.
- `max_retries: 3` — default retry ceiling (individual jobs can override via `retry_on`).

`vendor/chatwoot/config/initializers/sidekiq.rb:9-25` adds an optional dequeue logger
(`ENABLE_SIDEKIQ_DEQUEUE_LOGGER` env flag) and, in production, switches Sidekiq's own
logger to JSON format and suppresses default per-job start/stop log lines
(`config[:skip_default_job_logging] = true`, line 30) — relevant if we want structured
logs for our Dokploy log pipeline.

## Job categories

`vendor/chatwoot/app/jobs/` contains ~75 job classes (excluding specs). Grouped by
apparent purpose rather than listed exhaustively:

- **Outbound message delivery** — `SendReplyJob` (channel router), `Webhooks::FacebookDeliveryJob`, `ConversationReplyEmailJob`, `Notification::EmailNotificationJob`, `Notification::PushNotificationJob`. These take an already-composed message/notification and push it out to the contact or agent.
- **Inbound webhook/event ingestion** — `Webhooks::WhatsappEventsJob`, `Webhooks::FacebookEventsJob`, `Webhooks::InstagramEventsJob`, `Webhooks::LineEventsJob`, `Webhooks::SmsEventsJob`, `Webhooks::TelegramEventsJob`, `Webhooks::TiktokEventsJob`, `Webhooks::TwilioEventsJob`, `Webhooks::TwilioDeliveryStatusJob`. These parse provider-specific payloads from controllers and turn them into Chatwoot conversations/messages.
- **Outbound webhook/integration dispatch** — `WebhookJob` (generic account/inbox/agent-bot webhook, via `Webhooks::Trigger`), `HookJob` (Slack/Dialogflow/Google Translate/LeadSquared/Linear integration dispatch), `SendOnSlackJob`, `UpdateSlackMessageJob`, `SlackUnfurlJob`, `AgentBots::WebhookJob`.
- **Conversation & notification lifecycle** — `Conversations::ResolutionJob` (auto-resolve), `Conversations::ReopenSnoozedConversationsJob`, `Conversations::ActivityMessageJob`, `Conversations::UserMentionJob`, `Conversations::UpdateMessageStatusJob`, `Notification::ReopenSnoozedNotificationsJob`, `Notification::RemoveOldNotificationJob`, `Notification::RemoveDuplicateNotificationJob`, `Notification::DeleteNotificationJob`, `Account::ConversationsResolutionSchedulerJob`.
- **Auto-assignment** — `AutoAssignment::AssignmentJob`, `AutoAssignment::PeriodicAssignmentJob`.
- **Contacts/companies/avatars** — `Contacts::BulkActionJob`, `Companies::FetchAvatarsJob`, `Avatar::AvatarFromFaviconJob`, `Avatar::AvatarFromGravatarJob`, `Avatar::AvatarFromUrlJob`, `ContactIpLookupJob`, `UserSessionIpLookupJob`.
- **Campaigns** — `Campaigns::TriggerOneoffCampaignJob`.
- **Channel/template sync** — `Channels::Whatsapp::TemplatesSyncJob` + `TemplatesSyncSchedulerJob`, `Channels::Twilio::TemplatesSyncJob`, `Inboxes::FetchImapEmailInboxesJob`, `Inboxes::FetchImapEmailsJob`, `Inboxes::SyncWidgetPreChatCustomFieldsJob` + `Update...`.
- **Scheduled/cron entry points & housekeeping** (see next section) — `TriggerScheduledItemsJob`, `Internal::TriggerDailyScheduledItemsJob`, `Internal::TriggerHourlyScheduledItemsJob`, `Internal::CheckNewVersionsJob`, `Internal::DeleteAccountsJob`, `Internal::RemoveOrphanConversationsJob`, `Internal::RemoveStaleContactInboxesJob`, `Internal::RemoveStaleContactsJob`, `Internal::RemoveStaleRedisKeysJob`, `Internal::ProcessStaleContactsJob` (currently disabled, see below), `Internal::SeedAccountJob`.
- **One-off data/migration jobs** — everything under `app/jobs/migration/` (search index backfills, label cache rebuilds, reporting-event backfills, OpenAI hook validation) — these are one-time maintenance jobs run during version upgrades, not recurring.
- **Misc/platform** — `EventDispatcherJob` (internal pub/sub for domain events), `ActionCableBroadcastJob` (websocket push), `BulkActionsJob`, `DataImportJob`, `DeleteObjectJob`, `MacrosExecutionJob`, `Labels::UpdateJob` / `Labels::RemoveAssociationsJob`, `Crm::SetupJob`, `Account::BrandingEnrichmentJob`, `Account::ContactsExportJob`, `Agents::DestroyJob`, `Agent Bots::WebhookJob`.

## Scheduled/periodic jobs

Confirmed via `sidekiq-cron` + `vendor/chatwoot/config/schedule.yml` (loaded into Redis
at boot by `vendor/chatwoot/config/initializers/sidekiq.rb:40-50`, tagged `source: 'schedule'`
so entries removed from the YAML are cleaned up from Redis on the next deploy):

| Cron | Job | Cadence |
|---|---|---|
| `0 0 * * *` | `Internal::TriggerDailyScheduledItemsJob` | Daily @ 00:00 UTC |
| `*/5 * * * *` | `TriggerScheduledItemsJob` | Every 5 minutes |
| `0 * * * *` | `Internal::TriggerHourlyScheduledItemsJob` | Hourly |
| `*/1 * * * *` | `Inboxes::FetchImapEmailInboxesJob` | Every minute |
| `30 22 * * *` | `Internal::RemoveStaleContactInboxesJob` | Daily @ 22:30 UTC |
| `30 22 * * *` | `Internal::RemoveStaleRedisKeysJob` | Daily @ 22:30 UTC |
| `30 04 * * *` | `Internal::ProcessStaleContactsJob` | **Disabled** — commented out, "investigating if this job is the source of orphan conversations" (`config/schedule.yml:43-49`) |
| `0 1 * * *` | `Internal::DeleteAccountsJob` | Daily @ 01:00 UTC — deletes accounts marked for deletion |
| `*/30 * * * *` | `AutoAssignment::PeriodicAssignmentJob` | Every 30 min — assignment_v2 sweep |
| `30 22 * * *` | `Notification::RemoveOldNotificationJob` | Daily @ 22:30 UTC — purges notifications >1 month, trims to 300/user |
| `0 */12 * * *` | `Internal::RemoveOrphanConversationsJob` | Every 12 hours |

(`vendor/chatwoot/config/schedule.yml:7-76`)

`TriggerScheduledItemsJob` (`vendor/chatwoot/app/jobs/trigger_scheduled_items_job.rb:4-22`)
is itself a fan-out that, every 5 minutes, enqueues:
- Due one-off `Campaign` sends (`Campaigns::TriggerOneoffCampaignJob`)
- `Conversations::ReopenSnoozedConversationsJob`
- `Notification::ReopenSnoozedNotificationsJob`
- `Account::ConversationsResolutionSchedulerJob` (drives auto-resolve, see `Conversations::ResolutionJob` above)
- `Channels::Whatsapp::TemplatesSyncSchedulerJob`

If the Enterprise module is active, `Enterprise::TriggerScheduledItemsJob`
(`vendor/chatwoot/enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb:1-10`) is
mixed in via `prepend_mod_with` and additionally enqueues `Sla::TriggerSlasForAccountsJob`
every 5 minutes.

`Internal::TriggerDailyScheduledItemsJob` (`vendor/chatwoot/app/jobs/internal/trigger_daily_scheduled_items_job.rb:4-24`)
deliberately staggers a version-check job to a stable-but-installation-specific minute of
the day (derived from an MD5 hash of the installation identifier, line 23) so that many
self-hosted instances don't all hit the Chatwoot Hub at once — it schedules
`Internal::CheckNewVersionsJob` for later that same day, production-only (line 13).
If Enterprise is active, `Enterprise::Internal::TriggerDailyScheduledItemsJob`
(`vendor/chatwoot/enterprise/app/jobs/enterprise/internal/trigger_daily_scheduled_items_job.rb:2-8`)
additionally schedules Captain (AI docs) sync jobs daily, weekly (Sundays), and monthly
(1st of month) depending on plan tier.

`Internal::TriggerHourlyScheduledItemsJob` (`vendor/chatwoot/app/jobs/internal/trigger_hourly_scheduled_items_job.rb:4`)
has an **empty** `perform` method in CE — it exists purely as an extension point (no
Enterprise override was found for it in this pass either).

## External-facing jobs (webhooks, email, notifications)

These are the jobs most relevant to any future n8n bridge or third-party integration work:

- **`WebhookJob`** (`vendor/chatwoot/app/jobs/webhook_job.rb:1-7`, queue `medium`) — generic outbound webhook dispatcher for account/inbox/agent-bot webhook types. Delegates to `Webhooks::Trigger.execute`.
- **`Webhooks::Trigger`** (`vendor/chatwoot/lib/webhooks/trigger.rb:1-134`) — the actual HTTP client. POSTs JSON via `SafeFetch` (SSRF-safe fetch wrapper), signs the payload with HMAC-SHA256 when a webhook secret is set (`X-Chatwoot-Signature`, `X-Chatwoot-Timestamp` headers, lines 57-61), tags deliveries with `X-Chatwoot-Delivery` (line 56), reads a configurable timeout from `GlobalConfig.get_value('WEBHOOK_TIMEOUT')` defaulting to 5s (lines 118-123), and retries agent-bot webhooks on HTTP 429/500 (lines 3, 125-127). On failure for agent-bot/API-inbox webhook types it also flips conversation status or marks the message failed (lines 65-102). **This is the natural hook point for an n8n integration**: any n8n webhook registered as an "account webhook" in the Chatwoot admin UI would flow through this exact code path, receive the standard signed payload, and get retried by Chatwoot's own logic — no custom Chatwoot code needed.
- **`HookJob`** (`vendor/chatwoot/app/jobs/hook_job.rb:1-101`, queue `medium`, extends `MutexApplicationJob`) — dispatches internal domain events to configured *integrations* (not raw webhooks): Slack, Dialogflow, Google Translate, LeadSquared (with a Redis mutex to avoid duplicate CRM lead creation, lines 67-86), Linear. Retries on lock-acquisition failure (line 2).
- **`SendReplyJob`** (`vendor/chatwoot/app/jobs/send_reply_job.rb:1-38`, queue `high`) — routes an outgoing message to the channel-specific send service: Twitter, Twilio SMS, Line, Telegram, WhatsApp, generic SMS, Instagram, TikTok, Email, or web-widget/API email notification. Facebook/Instagram-direct is special-cased (lines 22, 32-38).
- **`ConversationReplyEmailJob`** (`vendor/chatwoot/app/jobs/conversation_reply_email_job.rb:1-16`, queue `mailers`) — sends the contact-facing "new reply" transactional email (`ConversationReplyMailer`), choosing a summary vs. non-summary template depending on whether the last incoming message was itself an email.
- **`Notification::EmailNotificationJob`** / **`Notification::PushNotificationJob`** (`vendor/chatwoot/app/jobs/notification/email_notification_job.rb:1-10`, `.../push_notification_job.rb:1-7`, queue `default`) — agent-facing notification delivery (email and push respectively); both no-op/skip if the notification is already read.
- **`SendOnSlackJob`** (`vendor/chatwoot/app/jobs/send_on_slack_job.rb:1-11`, queue `medium`, mutex-locked per conversation+Slack-reference) and **`UpdateSlackMessageJob`**, **`SlackUnfurlJob`** — Slack integration send/update/unfurl.
- **Inbound provider webhook jobs** under `app/jobs/webhooks/` (WhatsApp, Facebook, Instagram, Line, SMS, Telegram, TikTok, Twilio + Twilio delivery-status) — these receive external platform callbacks. `Webhooks::WhatsappEventsJob` (`vendor/chatwoot/app/jobs/webhooks/whatsapp_events_job.rb:1-164`, queue `low`) is the most complex: it distinguishes regular inbound messages from "message echo" events (WhatsApp Business app coexistence, lines 37-73), serializes concurrent album-upload webhooks per (inbox, contact) with a 30-second Redis lock (lines 19-26), and gates on channel/account active state (lines 127-134).
- **`Internal::CheckNewVersionsJob`** (`vendor/chatwoot/app/jobs/internal/check_new_versions_job.rb:1-18`, queue `scheduled_jobs`) — the one job that calls out to Chatwoot's own SaaS ("Hub") via `ChatwootHub.sync_with_hub`, production-only. Relevant to note for anyone doing air-gapped/offline deployment review, though not itself a customization target.

Not investigated in this pass: `AgentBots::WebhookJob`, `Channels::Whatsapp::TemplatesSyncJob`/`Channels::Twilio::TemplatesSyncJob` internals, and the full `Integrations::*` service classes referenced from `HookJob` — flagging as open follow-up if deeper integration work (e.g. building an n8n bridge) proceeds.
